import ApplicationServices
import Cocoa
import Defaults

// MARK: - Global State

private weak var activeWindowManipulationObserversInstance: WindowManipulationObservers?
private var pendingNotifications: [String: DispatchWorkItem] = [:]
private let windowProcessingDebounceInterval: TimeInterval = {
    let configuredDelay = TimeInterval(Defaults[.windowProcessingDebounceInterval])
    guard configuredDelay.isFinite, (0 ... 3).contains(configuredDelay) else {
        return TimeInterval(Defaults.Keys.windowProcessingDebounceInterval.defaultValue)
    }
    return configuredDelay
}()

private let spaceChangeMinimumSettleInterval: TimeInterval = 0.35
private let axObserverWorkQueue = DispatchQueue(label: "ddObsWorkQueue", qos: .userInitiated)

private let observedAXNotifications: [String] = [
    kAXWindowCreatedNotification,
    kAXUIElementDestroyedNotification,
    kAXWindowMiniaturizedNotification,
    kAXWindowDeminiaturizedNotification,
    kAXApplicationHiddenNotification,
    kAXApplicationShownNotification,
    kAXWindowResizedNotification,
    kAXWindowMovedNotification,
    kAXMainWindowChangedNotification,
    kAXFocusedUIElementChangedNotification,
    kAXFocusedWindowChangedNotification,
    kAXTitleChangedNotification,
]

class WindowManipulationObservers {
    private typealias CacheStateAdjustment = (inout Set<WindowInfo>) -> Void
    private typealias CacheStateAdjustmentPreparation = ([WindowInfo]) -> CacheStateAdjustment

    private let previewCoordinator: SharedPreviewWindowCoordinator
    private let dismissPreviewsForSpaceChange: @MainActor () -> Void

    static func shouldDismissPreviewOnAppActivation(
        isKeybindSessionActive: Bool,
        keepPreviewOnHoverActivation: Bool,
        previewHoverAction: PreviewHoverAction,
        mouseIsWithinPreviewWindow: Bool,
        hasCheckedWindows: Bool = false
    ) -> Bool {
        guard !isKeybindSessionActive, !hasCheckedWindows else { return false }
        return !(keepPreviewOnHoverActivation && previewHoverAction == .tap && mouseIsWithinPreviewWindow)
    }

    private var observers: [pid_t: AXObserver] = [:]
    private var runningApplicationsObservation: NSKeyValueObservation?
    private let debouncedTasksLock = NSLock()
    private var debouncedTasks: [String: Task<Void, Never>] = [:]
    private var cacheUpdateWorkItem: (token: UUID, workItem: DispatchWorkItem, hasStateAdjustment: Bool, needsValidation: Bool)?
    private func debounce(key: String, delay: TimeInterval = windowProcessingDebounceInterval, operation: @escaping () async -> Void) {
        let task = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                DebugLogger.log("debounce", details: "Cancelled during sleep: \(key)")
                return
            }
            guard !Task.isCancelled else {
                DebugLogger.log("debounce", details: "Cancelled after sleep: \(key)")
                return
            }
            await operation()
        }

        debouncedTasksLock.lock()
        let previousTask = debouncedTasks.updateValue(task, forKey: key)
        debouncedTasksLock.unlock()
        previousTask?.cancel()
    }

    private func cancelDebouncedTask(key: String) {
        debouncedTasksLock.lock()
        let task = debouncedTasks.removeValue(forKey: key)
        debouncedTasksLock.unlock()
        task?.cancel()
    }

    private func cancelAllDebouncedTasks() {
        debouncedTasksLock.lock()
        let tasks = Array(debouncedTasks.values)
        debouncedTasks.removeAll()
        debouncedTasksLock.unlock()

        tasks.forEach { $0.cancel() }
    }

    init(
        previewCoordinator: SharedPreviewWindowCoordinator,
        dismissPreviewsForSpaceChange: @escaping @MainActor () -> Void
    ) {
        self.previewCoordinator = previewCoordinator
        self.dismissPreviewsForSpaceChange = dismissPreviewsForSpaceChange
        activeWindowManipulationObserversInstance = self
        setupObservers()
    }

    deinit {
        cancelAllDebouncedTasks()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        removeAllObservers()
        if activeWindowManipulationObserversInstance === self {
            activeWindowManipulationObserversInstance = nil
        }
    }

    private func removeAllObservers() {
        let pids = Array(observers.keys)
        for pid in pids {
            removeObserver(for: pid)
        }
    }

    func reset() {
        cancelAllDebouncedTasks()
        removeAllObservers()
        let apps = LauncherShortcutResolver.resolvingInPlaceReexecs(NSWorkspace.shared.runningApplications).filter { $0.activationPolicy == .regular }
        for app in apps {
            createObserverForApp(app)
        }
    }

    private func setupObservers() {
        DebugLogger.measure("setupObservers") {
            let notificationCenter = NSWorkspace.shared.notificationCenter
            notificationCenter.addObserver(self, selector: #selector(appDidLaunch(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
            notificationCenter.addObserver(self, selector: #selector(appDidTerminate(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
            runningApplicationsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.old]) { [weak self] _, change in
                guard change.kind == .removal, let removedApps = change.oldValue else { return }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for app in removedApps where observers[app.processIdentifier] != nil || !WindowUtil.readCachedWindows(for: app.processIdentifier).isEmpty {
                        DebugLogger.log("runningApplicationsRemoved", details: "App: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))")
                        handleAppTermination(app)
                    }
                }
            }

            notificationCenter.addObserver(self, selector: #selector(activeSpaceDidChange(_:)), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
            notificationCenter.addObserver(self, selector: #selector(appDidActivate(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(screenParametersDidChange(_:)), name: NSApplication.didChangeScreenParametersNotification, object: nil)
            SpaceNumberResolver.refresh()

            let apps = LauncherShortcutResolver.resolvingInPlaceReexecs(NSWorkspace.shared.runningApplications).filter { $0.activationPolicy == .regular }
            DebugLogger.log("setupObservers", details: "Setting up observers for \(apps.count) running apps")

            for app in apps {
                createObserverForApp(app)
            }
        }
    }

    @objc private func appDidLaunch(_ notification: Notification) {
        guard let launchedApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              launchedApp.activationPolicy == .regular
        else {
            return
        }
        let app = LauncherShortcutResolver.resolvingInPlaceReexec(launchedApp)
        DebugLogger.log("appDidLaunch", details: "App: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))")
        createObserverForApp(app)
        handleNewWindow(for: app.processIdentifier)

        if Defaults[.showActiveAppIndicator] {
            ActiveAppIndicatorCoordinator.shared?.notifyDockItemsChanged()
        }
    }

    @MainActor
    @objc private func appDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        DebugLogger.log("appDidTerminate", details: "App: \(app.localizedName ?? "Unknown") (PID: \(app.processIdentifier))")
        handleAppTermination(app)
    }

    @MainActor
    static func didEvictTerminatedApps(_ pids: [pid_t]) {
        guard let instance = activeWindowManipulationObserversInstance else { return }
        for pid in pids {
            instance.handleAppTermination(pid: pid)
        }
    }

    @MainActor
    private func handleAppTermination(_ app: NSRunningApplication) {
        handleAppTermination(pid: app.processIdentifier)
    }

    @MainActor
    private func handleAppTermination(pid: pid_t) {
        cancelDebouncedTask(key: "windowCreation-\(pid)")
        WindowUtil.purgeAppCache(with: pid)
        removeObserver(for: pid)

        let coordinator = previewCoordinator.windowSwitcherCoordinator
        if coordinator.isKeybindSessionActive {
            for i in stride(from: coordinator.windows.count - 1, through: 0, by: -1) {
                if coordinator.windows[i].app.processIdentifier == pid {
                    coordinator.removeWindow(at: i)
                }
            }
            if coordinator.windows.isEmpty {
                previewCoordinator.hideWindow()
            }
        } else if !Defaults[.keepPreviewOnAppTerminate], !previewCoordinator.selectionKeepsPreviewsOpen {
            previewCoordinator.hideWindow()
        }

        if Defaults[.showActiveAppIndicator] {
            ActiveAppIndicatorCoordinator.shared?.notifyDockItemsChanged()
        }
    }

    @objc private func activeSpaceDidChange(_ notification: Notification) {
        DebugLogger.log("activeSpaceDidChange")
        Task { @MainActor in
            dismissPreviewsForSpaceChange()
        }
        if Defaults[.showActiveAppIndicator] {
            ActiveAppIndicatorCoordinator.shared?.handleSpaceChanged()
        }
        debounce(key: "spaceChange", delay: max(windowProcessingDebounceInterval, spaceChangeMinimumSettleInterval)) {
            SpaceNumberResolver.refresh()
            WindowUtil.scheduleAllCachedWindowMetadataReconciliations()
            await DebugLogger.measureAsync("updateAllWindowsInCurrentSpace") {
                await WindowUtil.updateAllWindowsInCurrentSpace()
            }
        }
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        SpaceNumberResolver.refresh()
    }

    @objc private func appDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else {
            return
        }

        let suppressActionDrivenDismissal = previewCoordinator.shouldSuppressActionDrivenActivationDismissal(
            for: app.processIdentifier
        )
        let tapSnapshot = previewCoordinator.tapSnapshot
        if Self.shouldDismissPreviewOnAppActivation(
            isKeybindSessionActive: tapSnapshot.isKeybindSessionActive,
            keepPreviewOnHoverActivation: Defaults[.keepPreviewOnHoverActivation],
            previewHoverAction: Defaults[.previewHoverAction],
            mouseIsWithinPreviewWindow: tapSnapshot.mouseIsWithinPreviewWindow,
            hasCheckedWindows: previewCoordinator.selectionKeepsPreviewsOpen
        ), !suppressActionDrivenDismissal {
            previewCoordinator.hideWindow()
        }

        if let dockObserver = DockObserver.activeInstance,
           let currentClickedPID = dockObserver.currentClickedAppPID,
           currentClickedPID != app.processIdentifier
        {
            dockObserver.currentClickedAppPID = nil
        }

        Self.ensureObserver(for: app)

        let activatedAt = Date()
        let appAX = AXUIElementCreateApplication(app.processIdentifier)
        axObserverWorkQueue.asyncAfter(deadline: .now() + 0.3) {
            if let focusedWindow = try? appAX.focusedWindow() {
                WindowUtil.updateWindowDateTime(element: focusedWindow, app: app, at: activatedAt)
            }
        }
    }

    /// Creates an observer for apps discovered outside the didLaunch notification path
    /// (e.g. terminal-spawned GUI processes), so they become event-driven after first contact.
    static func ensureObserver(for app: NSRunningApplication) {
        guard app.activationPolicy == .regular else { return }
        DispatchQueue.main.async {
            guard let instance = activeWindowManipulationObserversInstance,
                  instance.observers[app.processIdentifier] == nil,
                  !app.isTerminated,
                  !AXResponsiveness.isUnresponsive(app.processIdentifier)
            else { return }
            instance.createObserverForApp(app)
        }
    }

    private func createObserverForApp(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &observer) == .success, let observer else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer

        let details = "App: \(app.localizedName ?? "Unknown") (PID: \(pid))"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let registration = DebugLogger.measure("createObserverForApp", details: details) {
                let appElement = AXUIElementCreateApplication(pid)
                var failed = false
                var timedOut = false
                for notification in observedAXNotifications {
                    let start = CFAbsoluteTimeGetCurrent()
                    let result = AXObserverAddNotification(observer, appElement, notification as CFString, UnsafeMutableRawPointer(bitPattern: Int(pid)))
                    failed = failed || result == .cannotComplete
                    timedOut = timedOut || AXResponsiveness.shouldBackOff(after: result, elapsed: CFAbsoluteTimeGetCurrent() - start)
                }
                return (failed: failed, timedOut: timedOut)
            }
            guard registration.failed else { return }
            DispatchQueue.main.async {
                guard let self, self.observers[pid] === observer else { return }
                if registration.timedOut {
                    AXResponsiveness.markUnresponsive(pid)
                }
                self.removeObserver(for: pid)
            }
        }
    }

    private func removeObserverForApp(_ app: NSRunningApplication) {
        removeObserver(for: app.processIdentifier)
    }

    func removeObserver(for pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }

        DispatchQueue.global(qos: .utility).async {
            let appElement = AXUIElementCreateApplication(pid)
            for notification in observedAXNotifications {
                AXObserverRemoveNotification(observer, appElement, notification as CFString)
            }
        }
    }

    func handleNewWindow(for pid: pid_t) {
        let delay = AXResponsiveness.isUnresponsive(pid) ? AXResponsiveness.backoff : windowProcessingDebounceInterval
        debounce(key: "windowCreation-\(pid)", delay: delay) {
            if let app = LauncherShortcutResolver.application(forProcessIdentifier: pid) {
                let existingWindowIDs = Set(WindowUtil.readCachedWindows(for: pid).map(\.id))
                DebugLogger.log("handleNewWindow", details: "App: \(app.localizedName ?? "Unknown") (PID: \(pid))")
                await DebugLogger.measureAsync("updateNewWindowsForApp", details: "PID: \(pid)") {
                    await WindowUtil.updateNewWindowsForApp(app, restorePersistedOrder: false)
                }

                let discoveredWindowIDs = Set(WindowUtil.readCachedWindows(for: pid).map(\.id))
                    .subtracting(existingWindowIDs)
                if !discoveredWindowIDs.isEmpty {
                    axObserverWorkQueue.asyncAfter(deadline: .now() + 0.25) {
                        WindowUtil.removeNoninteractiveUntitledDialogs(
                            for: app,
                            candidateWindowIDs: discoveredWindowIDs
                        )
                    }
                }
            }
        }
    }

    private func notifyRunningAppDotsIfNeeded() {
        guard Defaults[.showActiveAppIndicator], Defaults[.activeAppIndicatorStyle] == .runningAppDots else { return }
        ActiveAppIndicatorCoordinator.shared?.notifyWindowsChanged()
    }

    func processAXNotification(element: AXUIElement, notificationName: String, app: NSRunningApplication, pid: pid_t) {
        DebugLogger.log("processAXNotification", details: "Notification: \(notificationName), App: \(app.localizedName ?? "Unknown") (PID: \(pid))")

        switch notificationName {
        case kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            let appAX = AXUIElementCreateApplication(app.processIdentifier)
            let focusedWindow = try? appAX.focusedWindow()
            let focusedWindowID = focusedWindow.flatMap { try? $0.cgWindowId() }
            Task { @MainActor [weak self] in
                self?.previewCoordinator.windowSwitcherCoordinator.updateActiveFocusedWindowID(focusedWindowID, for: pid)
            }
            if notificationName != kAXFocusedUIElementChangedNotification, let focusedWindow {
                Task.detached(priority: .userInitiated) {
                    await WindowUtil.cacheCreatedWindow(axWindow: focusedWindow, app: app)
                }
            }
            if app.isActive, let focusedWindow {
                WindowUtil.updateWindowDateTime(element: focusedWindow, app: app)
            }
            if let focusedWindowID {
                WindowUtil.scheduleCachedWindowMetadataReconciliation(pid: pid, windowID: focusedWindowID)
            }
            handleWindowEvent(element: element, app: app, notification: notificationName, validate: false) { _ in
                let eventWindowID = try? element.cgWindowId()
                let eventSpaceID = eventWindowID?.cgsSpaces().first.map { Int($0) }
                let eventScreenIdentifier = (try? element.position()).flatMap(WindowUtil.screenIdentifier(forWindowAt:))
                return { windowSet in
                    Self.update(windowSet: &windowSet, matching: eventWindowID, element: element) { window in
                        window.spaceID = eventSpaceID ?? window.spaceID
                        window.screenIdentifier = eventScreenIdentifier ?? window.screenIdentifier
                    }
                }
            }
        case kAXUIElementDestroyedNotification:
            if Defaults[.quitAppOnWindowClose], WindowUtil.cachedWindowWasDestroyed(element, pid: pid) {
                WindowUtil.quitAppOnLastWindowCloseIfNeeded(app: app)
            }
            handleWindowEvent(element: element, app: app, notification: notificationName, validate: true)
            notifyRunningAppDotsIfNeeded()
        case kAXWindowResizedNotification:
            let resizedWindowID = try? element.cgWindowId()
            handleWindowEvent(element: element, app: app, notification: notificationName, validate: false) { _ in
                let resizedSpaceID = resizedWindowID?.cgsSpaces().first.map { Int($0) }
                let resizedPosition = try? element.position()
                let resizedSize = resizedPosition.flatMap { _ in try? element.size() }
                let resizedScreenIdentifier = resizedPosition.flatMap(WindowUtil.screenIdentifier(forWindowAt:))
                return { windowSet in
                    Self.update(windowSet: &windowSet, matching: resizedWindowID, element: element) { window in
                        window.spaceID = resizedSpaceID ?? window.spaceID
                        window.screenIdentifier = resizedScreenIdentifier ?? window.screenIdentifier
                        if let resizedPosition, let resizedSize {
                            window.frame = CGRect(origin: resizedPosition, size: resizedSize)
                        }
                    }
                }
            }
            if let resizedWindowID {
                WindowUtil.scheduleCachedWindowMetadataReconciliation(pid: pid, windowID: resizedWindowID)
                WindowUtil.refreshCachedPreviewAfterResizeNotification(pid: pid, windowID: resizedWindowID)
            }
        case kAXWindowMovedNotification:
            let movedWindowID = try? element.cgWindowId()
            handleWindowEvent(element: element, app: app, notification: notificationName, validate: false) { _ in
                let movedSpaceID = movedWindowID?.cgsSpaces().first.map { Int($0) }
                let movedPosition = try? element.position()
                let movedSize = try? element.size()
                let movedScreenIdentifier = movedPosition.flatMap(WindowUtil.screenIdentifier(forWindowAt:))
                return { windowSet in
                    Self.update(windowSet: &windowSet, matching: movedWindowID, element: element) { window in
                        window.spaceID = movedSpaceID ?? window.spaceID
                        window.screenIdentifier = movedScreenIdentifier ?? window.screenIdentifier
                        if let movedPosition, let movedSize {
                            window.frame = CGRect(origin: movedPosition, size: movedSize)
                        }
                    }
                }
            }
            if let movedWindowID {
                WindowUtil.scheduleCachedWindowMetadataReconciliation(pid: pid, windowID: movedWindowID)
            }
        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            let windowID = try? element.cgWindowId()
            handleWindowEvent(element: element, app: app, notification: notificationName, validate: true) { _ in
                let minimizedState = try? element.isMinimized()
                return { windowSet in
                    Self.update(windowSet: &windowSet, matching: windowID, element: element) { window in
                        window.isMinimized = minimizedState ?? false
                    }
                }
            }
            if Defaults[.showActiveAppIndicator] {
                ActiveAppIndicatorCoordinator.shared?.notifyWindowsChanged()
            }
        case kAXApplicationHiddenNotification:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self else { return }
                if NSRunningApplication(processIdentifier: pid) == nil {
                    WindowUtil.purgeAppCache(with: pid)
                    removeObserver(for: pid)
                } else {
                    handleWindowEvent(element: element, app: app, notification: notificationName, validate: true) { cachedWindows in
                        let spacesByWindowID = cachedWindows.reduce(into: [CGWindowID: Int]()) { result, window in
                            result[window.id] = window.id.cgsSpaces().first.map { Int($0) }
                        }
                        return { windowSet in
                            windowSet = Set(windowSet.map { window in
                                var updated = window
                                updated.isHidden = true
                                updated.spaceID = spacesByWindowID[updated.id] ?? updated.spaceID
                                return updated
                            })
                        }
                    }
                }
            }
        case kAXApplicationShownNotification:
            handleWindowEvent(element: element, app: app, notification: notificationName, validate: true) { cachedWindows in
                let shownMetadata = cachedWindows.reduce(into: [CGWindowID: (Int?, String?)]()) { result, window in
                    let spaceID = window.id.cgsSpaces().first.map { Int($0) }
                    let screenIdentifier = (try? window.axElement.position()).flatMap(WindowUtil.screenIdentifier(forWindowAt:))
                    result[window.id] = (spaceID, screenIdentifier)
                }
                return { windowSet in
                    windowSet = Set(windowSet.map { window in
                        var updated = window
                        updated.isHidden = false
                        if let metadata = shownMetadata[updated.id] {
                            updated.spaceID = metadata.0 ?? updated.spaceID
                            updated.screenIdentifier = metadata.1 ?? updated.screenIdentifier
                        }
                        return updated
                    })
                }
            }
        case kAXWindowCreatedNotification:
            Task.detached(priority: .userInitiated) {
                await WindowUtil.cacheCreatedWindow(axWindow: element, app: app)
            }
            handleNewWindow(for: pid)
            notifyRunningAppDotsIfNeeded()
        case kAXTitleChangedNotification:
            let windowID = try? element.cgWindowId()
            if let existing = WindowUtil.readCachedWindows(for: pid).first(where: { (windowID != nil && $0.id == windowID) || $0.axElement == element }) {
                guard let freshTitle = try? existing.axElement.title(), !freshTitle.isEmpty, existing.windowName != freshTitle else { return }
                WindowUtil.updateWindowCache(for: app) { windowSet in
                    guard let current = windowSet.first(where: { $0.id == existing.id }) else { return }
                    var updated = current
                    updated.windowName = freshTitle
                    windowSet.remove(current)
                    windowSet.insert(updated)
                }
                return
            }
            handleWindowEvent(element: element, app: app, notification: notificationName, validate: false) { _ in
                let role = try? element.role()
                let freshTitle = try? element.title()
                return { windowSet in
                    guard role == kAXWindowRole as String, let freshTitle, !freshTitle.isEmpty else { return }
                    Self.update(windowSet: &windowSet, matching: windowID, element: element) { window in
                        window.windowName = freshTitle
                    }
                }
            }
        default:
            break
        }
    }

    private func handleWindowEvent(element: AXUIElement,
                                   app: NSRunningApplication,
                                   notification: String,
                                   validate: Bool = false,
                                   prepareStateAdjustment: CacheStateAdjustmentPreparation? = nil)
    {
        let inheritedValidation = cacheUpdateWorkItem?.needsValidation ?? false

        if cacheUpdateWorkItem?.hasStateAdjustment != true {
            cacheUpdateWorkItem?.workItem.cancel()
        }

        let effectiveValidate = validate || inheritedValidation
        let hasStateAdjustment = prepareStateAdjustment != nil
        let token = UUID()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DebugLogger.measure("updateWindowCache", details: "App: \(app.localizedName ?? "Unknown"), Notification: \(notification), Validate: \(effectiveValidate)") {
                let cachedWindows = WindowUtil.readCachedWindows(for: app.processIdentifier)
                let invalidWindows: [WindowInfo] = if effectiveValidate {
                    cachedWindows.filter {
                        !WindowUtil.isValidElement($0.axElement)
                    }
                } else {
                    []
                }
                let stateAdjustment = prepareStateAdjustment?(cachedWindows)

                var shouldCheckQuitPolicy = false
                WindowUtil.updateWindowCache(for: app) { windowSet in
                    let previousWindows = windowSet
                    if !invalidWindows.isEmpty {
                        windowSet = windowSet.filter { current in
                            !invalidWindows.contains { invalid in
                                invalid.axElement == current.axElement
                            }
                        }
                    }
                    stateAdjustment?(&windowSet)
                    shouldCheckQuitPolicy = effectiveValidate && !previousWindows.isEmpty && windowSet.isEmpty
                }
                if shouldCheckQuitPolicy {
                    WindowUtil.quitAppOnLastWindowCloseIfNeeded(app: app)
                }
            }
            if cacheUpdateWorkItem?.token == token {
                cacheUpdateWorkItem = nil
            }
        }
        cacheUpdateWorkItem = (token, workItem, hasStateAdjustment, effectiveValidate)
        axObserverWorkQueue.asyncAfter(deadline: .now() + windowProcessingDebounceInterval, execute: workItem)
    }

    private static func update(windowSet: inout Set<WindowInfo>,
                               matching windowID: CGWindowID?,
                               element: AXUIElement,
                               updateBlock: (inout WindowInfo) -> Void)
    {
        if let windowID,
           let existing = windowSet.first(where: { $0.id == windowID })
        {
            var updated = existing
            updateBlock(&updated)
            windowSet.remove(existing)
            windowSet.insert(updated)
            return
        }

        if let existing = windowSet.first(where: { $0.axElement == element }) {
            var updated = existing
            updateBlock(&updated)
            windowSet.remove(existing)
            windowSet.insert(updated)
        }
    }
}

func axObserverCallback(observer: AXObserver, element: AXUIElement, notificationName: CFString, userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let pid = pid_t(Int(bitPattern: userData))
    let notification = notificationName as String
    var key = "\(pid)-\(notification)"
    if notification == kAXTitleChangedNotification, let windowID = try? element.cgWindowId() {
        key += "-\(windowID)"
    }

    axObserverWorkQueue.async {
        if notification == kAXWindowCreatedNotification,
           let app = LauncherShortcutResolver.application(forProcessIdentifier: pid),
           let observerInstance = activeWindowManipulationObserversInstance
        {
            observerInstance.processAXNotification(element: element, notificationName: notification, app: app, pid: pid)
            return
        }

        pendingNotifications[key]?.cancel()

        let workItem = DispatchWorkItem {
            pendingNotifications.removeValue(forKey: key)
            if let app = LauncherShortcutResolver.application(forProcessIdentifier: pid),
               let observerInstance = activeWindowManipulationObserversInstance
            {
                observerInstance.processAXNotification(element: element, notificationName: notification, app: app, pid: pid)
            }
        }

        pendingNotifications[key] = workItem
        axObserverWorkQueue.asyncAfter(deadline: .now() + windowProcessingDebounceInterval, execute: workItem)
    }
}
