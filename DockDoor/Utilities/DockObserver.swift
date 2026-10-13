import ApplicationServices
import Carbon.HIToolbox.Events
import Cocoa
import Defaults
import IOKit

struct ApplicationInfo: Sendable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String?

    func app() -> NSRunningApplication? {
        LauncherShortcutResolver.application(forProcessIdentifier: processIdentifier)
    }
}

struct ApplicationReturnType {
    enum Status: Equatable {
        case success(NSRunningApplication)
        case notRunning(bundleIdentifier: String)
        case notFound
    }

    let status: Status
    let dockItemElement: AXUIElement?
}

struct FolderDockItemInfo {
    let url: URL
    let title: String
    let dockItemElement: AXUIElement
}

func handleSelectedDockItemChangedNotification(observer _: AXObserver, element _: AXUIElement, notificationName _: CFString, context: UnsafeMutableRawPointer?) {
    DispatchQueue.main.async {
        DockObserver.activeInstance?.processSelectedDockItemChanged()
    }
}

final class DockObserver {
    private final class CycleClickTracker {
        struct Press {
            let processIdentifier: pid_t
            let event: CGEvent
        }

        var press: Press?

        func begin(app: NSRunningApplication, event: CGEvent) -> Bool {
            guard let copy = event.copy() else { return false }
            press = Press(processIdentifier: app.processIdentifier, event: copy)
            return true
        }

        func takePress() -> Press? {
            defer { press = nil }
            return press
        }
    }

    private final class EventTapContext {
        weak var observer: DockObserver?
        let cycleClicks: CycleClickTracker?

        init(observer: DockObserver, cycleClicks: CycleClickTracker?) {
            self.observer = observer
            self.cycleClicks = cycleClicks
        }
    }

    private enum VerticalScrollAction {
        case maximize
        case center
    }

    private struct PendingRestoreState {
        let windowId: CGWindowID
        let processIdentifier: pid_t
        let action: VerticalScrollAction
        let originalFrame: CGRect
        let expirationDate: Date
    }

    private struct CachedTitleBarInfo {
        let window: WindowInfo
        let windowFrame: CGRect
        let titleBarRect: CGRect
        let timestamp: Date
    }

    private struct WindowCycleState {
        let orderedWindowIDs: [CGWindowID]
        var nextIndex: Int
    }

    private struct PendingDockClickAction {
        let token: UUID
        let task: Task<Void, Never>
    }

    weak static var activeInstance: DockObserver?
    let previewCoordinator: SharedPreviewWindowCoordinator

    var axObserver: AXObserver?
    private var previousStatus: ApplicationReturnType.Status?

    private var currentDockPID: pid_t?
    private var healthCheckTimer: Timer?
    private static let postingCanarySubtype: Int16 = 0x0D0D
    private(set) static var canPostEvents = true
    private var postingCanaryMonitor: Any?
    private var postingCanaryPending = false
    private var postingCanaryMisses = 0
    private var lastPostingCanaryUptime: TimeInterval = 0
    private var subscribedDockList: AXUIElement?
    private var accessibilityPromptShown = false
    private var awaitingAccessibilityGrant = false

    // Cmd+Tab switcher monitoring (accessed from extension file)
    var cmdTabObserver: AXObserver?
    var cmdTabPollingTimer: Timer?
    var cmdTabDiscoveryTask: Task<Void, Never>?
    var cmdTabSelectionRetryWorkItem: DispatchWorkItem?
    var cmdTabSelectionGeneration: UInt = 0
    private var dockPreviewDiscoveryTask: Task<Void, Never>?
    private var dockPreviewDiscoveryGeneration: UInt = 0

    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var eventTapContext: EventTapContext?
    private var eventTapHandlesWindowCycling = false
    private var dockClickSettingsObserver: Defaults.Observation?

    // Dock click behavior state
    private struct DockClickState {
        var currentClickedAppPID: pid_t?
        var lastHoveredPID: pid_t?
        var lastHoveredAppWasFrontmost = false
        var lastHoveredAppHadWindows = false
    }

    private let dockClickStateLock = NSLock()
    private var dockClickState = DockClickState()
    var currentClickedAppPID: pid_t? {
        get {
            dockClickStateLock.lock()
            defer { dockClickStateLock.unlock() }
            return dockClickState.currentClickedAppPID
        }
        set {
            dockClickStateLock.lock()
            dockClickState.currentClickedAppPID = newValue
            dockClickStateLock.unlock()
        }
    }

    private var windowCycleState: WindowCycleState?
    private var cycleHoverProcessIdentifier: pid_t?
    private var cycleHoverGeneration = 0
    private var dockClickActionTasks: [pid_t: PendingDockClickAction] = [:]

    // Scroll gesture state
    private var lastDockScrollActionTime: Date = .distantPast
    private let dockScrollActionDebounceInterval: TimeInterval = 0.3
    private var lastTitleBarScrollActionTime: Date = .distantPast
    private var pendingTitleBarRestoreState: PendingRestoreState?

    private let titleBarScrollActionDebounceInterval: TimeInterval = 0.35
    private let minimumTitleBarScrollDelta: Double = 0.15
    private let fallbackTitleBarHeight: CGFloat = 48
    private let maximumTitleBarHeight: CGFloat = 72

    private let titleBarCacheLock = NSLock()
    private var cachedTitleBarInfo: CachedTitleBarInfo?
    private var titleBarRefreshScheduled = false
    private let titleBarCacheMaxAge: TimeInterval = 1.0

    private var centeredWindowScale: CGFloat {
        min(max(Defaults[.titleBarScrollCenteredWindowScale], 0.2), 1.0)
    }

    private var centeredWindowWidthScale: CGFloat {
        min(max(Defaults[.titleBarScrollCenteredWindowWidthScale], 0.2), 1.0)
    }

    private var centeredWindowHeightScale: CGFloat {
        min(max(Defaults[.titleBarScrollCenteredWindowHeightScale], 0.2), 1.0)
    }

    private var centeredWindowLockAspectRatio: Bool {
        Defaults[.titleBarScrollCenteredWindowLockAspectRatio]
    }

    private var centeredWindowSizingMode: TitleBarCenteredWindowSizingMode {
        Defaults[.titleBarScrollCenteredWindowSizingMode]
    }

    @MainActor private static func isSpecialControlsApp(_ bundleId: String?) -> Bool {
        (bundleId == calendarAppIdentifier && Defaults[.enableCalendarWidget]) ||
            (isMediaApp(bundleId) && Defaults[.enableMediaWidget])
    }

    init(previewCoordinator: SharedPreviewWindowCoordinator) {
        self.previewCoordinator = previewCoordinator
        DockObserver.activeInstance = self
        postingCanaryMonitor = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) { [weak self] event in
            guard event.subtype.rawValue == DockObserver.postingCanarySubtype else { return event }
            self?.postingCanaryArrived()
            return nil
        }
        setupSelectedDockItemObserver()
        startHealthCheckTimer()
        enableDockClickDetection()
        dockClickSettingsObserver = Defaults.observe(keys: .shouldHideOnDockItemClick, .dockClickAction, options: []) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, eventTapHandlesWindowCycling != windowCyclingEnabled else { return }
                removeEventTap()
                setupEventTap()
            }
        }
    }

    deinit {
        if DockObserver.activeInstance === self {
            DockObserver.activeInstance = nil
        }
        if let postingCanaryMonitor {
            NSEvent.removeMonitor(postingCanaryMonitor)
        }
        healthCheckTimer?.invalidate()
        dockPreviewDiscoveryTask?.cancel()
        dockClickActionTasks.values.forEach { $0.task.cancel() }
        teardownObserver()
        teardownCmdTabObserver()

        removeEventTap()
    }

    private func startHealthCheckTimer() {
        healthCheckTimer?.invalidate()
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.performHealthCheck()
        }
    }

    func reset() {
        dockPreviewDiscoveryGeneration &+= 1
        dockPreviewDiscoveryTask?.cancel()
        dockPreviewDiscoveryTask = nil
        teardownObserver()
        teardownCmdTabObserver()
        setupSelectedDockItemObserver()
        removeEventTap()
        setupEventTap()
    }

    private func performHealthCheck() {
        if awaitingAccessibilityGrant, AXIsProcessTrusted() {
            awaitingAccessibilityGrant = false
            askUserToRestartApplication()
            return
        }

        if hasInputSinceLastPostingCanary {
            sendPostingCanary()
        }

        guard let currentDockPID else {
            setupSelectedDockItemObserver()
            return
        }

        let currentDockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first

        if currentDockApp?.processIdentifier != currentDockPID {
            reset()
            return
        }

        // Verify the subscribed dock list element is still valid
        // If the dock rebuilds its UI, the element becomes invalid and notifications stop
        if let subscribedElement = subscribedDockList {
            var role: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(subscribedElement, kAXRoleAttribute as CFString, &role)
            if result == .invalidUIElement || result == .cannotComplete {
                reset()
            }
        } else if axObserver != nil {
            // We have an observer but no subscribed element reference - reset to fix state
            reset()
        }

        if let subscribedElement = subscribedDockList,
           let children = try? AXUIElementCreateApplication(currentDockPID).children(),
           let currentList = children.first(where: { (try? $0.role()) == kAXListRole }),
           !CFEqual(currentList, subscribedElement)
        {
            reset()
            return
        }

        // Check event tap health
        if let eventTap {
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                removeEventTap()
                setupEventTap()
            }
        } else {
            setupEventTap()
        }
    }

    private var hasInputSinceLastPostingCanary: Bool {
        guard let idle = DockObserver.hidIdleSeconds else { return true }
        return idle + 0.5 < ProcessInfo.processInfo.systemUptime - lastPostingCanaryUptime
    }

    private static var hidIdleSeconds: TimeInterval? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        let idle = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
        return idle.map { $0.doubleValue / 1_000_000_000 }
    }

    private func sendPostingCanary() {
        if postingCanaryPending {
            postingCanaryMisses += 1
            if postingCanaryMisses >= 2, DockObserver.canPostEvents {
                updateCanPostEvents(false)
            }
        }
        postingCanaryPending = true
        NSEvent.otherEvent(
            with: .applicationDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: DockObserver.postingCanarySubtype,
            data1: 0,
            data2: 0
        )?.cgEvent?.postToPid(getpid())
        lastPostingCanaryUptime = ProcessInfo.processInfo.systemUptime
    }

    private func postingCanaryArrived() {
        postingCanaryPending = false
        postingCanaryMisses = 0
        if !DockObserver.canPostEvents {
            updateCanPostEvents(true)
        }
    }

    private func updateCanPostEvents(_ canPostEvents: Bool) {
        DockObserver.canPostEvents = canPostEvents
        DebugLogger.log("DockObserver", details: "Event posting \(canPostEvents ? "allowed" : "refused"), rebuilding event taps")
        (NSApp.delegate as? AppDelegate)?.recoverObserversAndTaps()
    }

    private func teardownObserver() {
        if let observer = axObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        axObserver = nil
        currentDockPID = nil
        subscribedDockList = nil
    }

    private func setupSelectedDockItemObserver() {
        guard let dockApp = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return
        }

        let dockAppPID = dockApp.processIdentifier
        let dockAppElement = AXUIElementCreateApplication(dockAppPID)

        guard AXIsProcessTrusted() else {
            // The health check retries setup every 5 seconds until trusted; show the prompt once per launch.
            awaitingAccessibilityGrant = true
            guard !accessibilityPromptShown else { return }
            accessibilityPromptShown = true
            MessageUtil.showAlert(
                title: "Accessibility Permissions Required",
                message: "You need to enable accessibility permissions for DockDoor to function, click OK to open System Preferences. A restart is required after granting permissions.",
                actions: [.ok, .cancel],
                completion: { _ in
                    SystemPreferencesHelper.openAccessibilityPreferences()
                }
            )
            return
        }

        currentDockPID = dockAppPID

        guard let children = try? dockAppElement.children(),
              let axList = children.first(where: { element in
                  (try? element.role()) == kAXListRole
              })
        else {
            return
        }

        if AXObserverCreate(dockAppPID, handleSelectedDockItemChangedNotification, &axObserver) != .success {
            return
        }

        guard let axObserver else { return }

        do {
            try axList.subscribeToNotification(axObserver, kAXSelectedChildrenChangedNotification) {
                CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(axObserver), .commonModes)
            }
            subscribedDockList = axList
        } catch {
            return
        }
    }

    func hideWindowAndResetLastApp() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            cancelDockPreviewDiscovery()
            previewCoordinator.hideWindow()
        }
    }

    @MainActor func processSelectedDockItemChanged() {
        HangDiagnostics.record("dock activation received")
        let currentMouseLocation = DockObserver.getMousePosition()

        guard !previewCoordinator.windowSwitcherCoordinator.windowSwitcherActive else {
            return
        }

        guard Defaults[.dockPreviewActivationMode] == .hover else {
            return
        }

        if handleHoveredFolderDockItemIfNeeded(mouseLocation: currentMouseLocation) {
            return
        }

        showPreviewForHoveredDockApp(
            mouseLocation: currentMouseLocation,
            overrideDelay: false,
            refreshLogContext: "dock hover"
        )
    }

    @MainActor
    private func showPreviewForHoveredDockApp(mouseLocation currentMouseLocation: CGPoint, overrideDelay: Bool, refreshLogContext: String) {
        guard previewCoordinator.canPresentPreviews, !previewCoordinator.selectionKeepsPreviewsOpen else { return }
        let previousDiscoveryTask = cancelDockPreviewDiscovery()
        let discoveryGeneration = dockPreviewDiscoveryGeneration
        let appUnderMouseElement = DebugLogger.measureSlow("getDockItemAppStatusUnderMouse", thresholdMs: 100) {
            getDockItemAppStatusUnderMouse()
        }

        guard let dockItemElement = appUnderMouseElement.dockItemElement
        else {
            resetWindowCycleHover()
            return
        }

        guard Defaults[.enableDockPreviews] else { return }

        if case let .notRunning(bundleIdentifier) = appUnderMouseElement.status {
            resetWindowCycleHover()
            if canShowSpecialPreview(forNotRunningBundleIdentifier: bundleIdentifier) {
                let mouseScreen = NSScreen.screenFromQuartzPoint(currentMouseLocation)
                let convertedMouseLocation = DockObserver.nsPointFromCGPoint(currentMouseLocation, forScreen: mouseScreen)
                let appName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
                    .flatMap { Bundle(url: $0) }
                    .flatMap { $0.infoDictionary?["CFBundleDisplayName"] as? String ?? $0.infoDictionary?["CFBundleName"] as? String }
                    ?? MediaRemoteService.shared.activeAppName
                    ?? "Unknown"
                previewCoordinator.showWindow(
                    appName: appName,
                    windows: [],
                    mouseLocation: convertedMouseLocation,
                    mouseScreen: mouseScreen,
                    dockItemElement: dockItemElement,
                    overrideDelay: overrideDelay,
                    onWindowTap: { [weak self] in self?.hideWindowAndResetLastApp() },
                    bundleIdentifier: bundleIdentifier
                )
            }
            return
        }

        guard case let .success(currentApp) = appUnderMouseElement.status else {
            resetWindowCycleHover()
            return
        }

        _ = updateWindowCycleHover(for: currentApp.processIdentifier)

        if WindowUtil.isAppFiltered(currentApp) {
            return
        }

        let currentAppInfo = ApplicationInfo(
            processIdentifier: currentApp.processIdentifier,
            bundleIdentifier: currentApp.bundleIdentifier,
            localizedName: currentApp.localizedName
        )

        // Build list of apps to fetch windows from
        let appsToFetchWindowsFrom: [NSRunningApplication] = Defaults[.groupAppInstancesInDock]
            ? LauncherShortcutResolver.siblingInstances(of: currentApp)
            : [currentApp]

        guard !appsToFetchWindowsFrom.isEmpty else { return }

        var cachedWindows: [WindowInfo] = []
        for appInstance in appsToFetchWindowsFrom {
            cachedWindows.append(contentsOf: WindowUtil.readCachedWindows(for: appInstance.processIdentifier))
        }
        cachedWindows = WindowUtil.collapseNativeTabsIfNeeded(cachedWindows)

        HangDiagnostics.record("dock cache ready pid=\(currentApp.processIdentifier) windows=\(cachedWindows.count)")

        updateDockClickHoverState(
            pid: currentApp.processIdentifier,
            wasFrontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == currentApp.processIdentifier,
            hadWindows: !cachedWindows.isEmpty
        )

        if WindowFetchContext.dockPreview.shouldIgnoreAppsWithSingleWindow, cachedWindows.count == 1 {
            cachedWindows = []
        }

        cachedWindows = WindowUtil.collapseNativeTabsIfNeeded(cachedWindows)

        // Filter cached windows by current space before showing preview
        if Defaults[.showWindowsFromCurrentSpaceOnly], !cachedWindows.isEmpty {
            cachedWindows = WindowUtil.filterWindowsByCurrentSpace(cachedWindows)
        }

        if Defaults[.showWindowsFromCurrentMonitorOnly], !cachedWindows.isEmpty {
            cachedWindows = WindowUtil.filterWindowsByCurrentMonitor(cachedWindows, mouseLocation: currentMouseLocation)
        }

        if !Defaults[.includeHiddenWindowsInDockPreview] {
            cachedWindows = cachedWindows.filter { !$0.isHidden && !$0.isMinimized }
        }

        let mouseScreen = NSScreen.screenFromQuartzPoint(currentMouseLocation)
        let convertedMouseLocation = DockObserver.nsPointFromCGPoint(currentMouseLocation, forScreen: mouseScreen)
        let screenOrigin = mouseScreen.frame.origin
        let currentAppPID = currentApp.processIdentifier
        let currentAppBundleId = currentApp.bundleIdentifier

        if cachedWindows.isEmpty, Defaults[.showWindowlessAppsInDockPreview] {
            cachedWindows = [WindowInfo.windowlessEntry(for: currentApp)]
        }

        let shouldShowCachedPreview = !cachedWindows.isEmpty ||
            (Self.isSpecialControlsApp(currentApp.bundleIdentifier) && Defaults[.showSpecialAppControls])

        if shouldShowCachedPreview {
            previewCoordinator.showWindow(
                appName: currentAppInfo.localizedName ?? "Unknown",
                windows: cachedWindows,
                mouseLocation: convertedMouseLocation,
                mouseScreen: mouseScreen,
                dockItemElement: dockItemElement,
                overrideDelay: overrideDelay,
                onWindowTap: { [weak self] in
                    self?.hideWindowAndResetLastApp()
                },
                bundleIdentifier: currentAppInfo.bundleIdentifier
            )
            previousStatus = .success(currentApp)
        }

        dockPreviewDiscoveryTask = Task.detached { [weak self] in
            await previousDiscoveryTask?.value
            guard !Task.isCancelled else { return }

            do {
                var windows: [WindowInfo] = []
                for appInstance in appsToFetchWindowsFrom {
                    guard !Task.isCancelled else { return }
                    try await windows.append(contentsOf: DebugLogger.measureAsync("getActiveWindows (\(refreshLogContext))", details: "PID: \(appInstance.processIdentifier)") {
                        try await WindowUtil.getActiveWindows(of: appInstance)
                    })
                }
                guard !Task.isCancelled else { return }

                if Defaults[.showWindowsFromCurrentSpaceOnly] {
                    windows = WindowUtil.filterWindowsByCurrentSpace(windows)
                }

                if Defaults[.showWindowsFromCurrentMonitorOnly] {
                    windows = WindowUtil.filterWindowsByCurrentMonitor(windows, mouseLocation: currentMouseLocation)
                }

                if !Defaults[.includeHiddenWindowsInDockPreview] {
                    windows = windows.filter { !$0.isHidden && !$0.isMinimized }
                }

                let freshWindows = windows

                await MainActor.run { [weak self] in
                    guard let self, discoveryGeneration == dockPreviewDiscoveryGeneration else { return }
                    dockPreviewDiscoveryTask = nil

                    let currentAppStatus = getDockItemAppStatusUnderMouse()
                    guard case let .success(stillHoveredApp) = currentAppStatus.status,
                          stillHoveredApp.processIdentifier == currentAppPID
                    else { return }

                    let dockPosition = DockUtils.getDockPosition()
                    guard let monitor = screenOrigin.screen() else { return }

                    if freshWindows.isEmpty {
                        if !Self.isSpecialControlsApp(currentAppBundleId) || !Defaults[.showSpecialAppControls] {
                            return
                        }
                    }

                    let didMerge = previewCoordinator.mergeWindowsIfNeeded(
                        currentAppPID,
                        windows: freshWindows,
                        dockPosition: dockPosition,
                        bestGuessMonitor: monitor
                    )
                    DebugLogger.log("WindowRefresh", details: "\(refreshLogContext) final merge, PID: \(currentAppPID), windows: \(freshWindows.count), merged: \(didMerge)")
                }
            } catch {
                guard !Task.isCancelled else { return }
                DebugLogger.log("DockObserver", details: "Failed to fetch windows for \(refreshLogContext): \(error)")
                await MainActor.run { [weak self] in
                    guard let self, discoveryGeneration == dockPreviewDiscoveryGeneration else { return }
                    dockPreviewDiscoveryTask = nil
                }
            }
        }
    }

    @MainActor
    @discardableResult
    private func cancelDockPreviewDiscovery() -> Task<Void, Never>? {
        dockPreviewDiscoveryGeneration &+= 1
        let previousTask = dockPreviewDiscoveryTask
        previousTask?.cancel()
        dockPreviewDiscoveryTask = nil
        return previousTask
    }

    @MainActor
    private func handleHoveredFolderDockItemIfNeeded(mouseLocation: CGPoint) -> Bool {
        guard let folderItem = getHoveredFolderDockItem() else { return false }
        cancelDockPreviewDiscovery()

        _ = showFolderPreviewIfPossible(folderItem: folderItem, mouseLocation: mouseLocation)
        return true
    }

    @MainActor
    private func showHoveredFolderDockItemPreviewIfPossible(mouseLocation: CGPoint) -> Bool {
        cancelDockPreviewDiscovery()
        guard let folderItem = getHoveredFolderDockItem() else { return false }
        return showFolderPreviewIfPossible(folderItem: folderItem, mouseLocation: mouseLocation)
    }

    @MainActor
    private func showFolderPreviewIfPossible(folderItem: FolderDockItemInfo, mouseLocation: CGPoint) -> Bool {
        guard Defaults[.enableDockPreviews],
              Defaults[.enableFolderWidget]
        else {
            return false
        }

        guard let accessibleURL = FolderWidgetAuthorization.accessibleURL(for: folderItem.url) else {
            return false
        }

        let mouseScreen = NSScreen.screenFromQuartzPoint(mouseLocation)
        let convertedMouseLocation = DockObserver.nsPointFromCGPoint(mouseLocation, forScreen: mouseScreen)

        previewCoordinator.showFolderWidget(
            folderURL: accessibleURL,
            folderName: folderItem.title,
            mouseLocation: convertedMouseLocation,
            mouseScreen: mouseScreen,
            dockItemElement: folderItem.dockItemElement
        )

        return true
    }

    /// Returns the currently selected (hovered) dock item, if any.
    private func getSelectedDockItem() -> AXUIElement? {
        guard let dockAppPID = currentDockPID else {
            return nil
        }

        let dockAppElement = AXUIElementCreateApplication(dockAppPID)

        var dockItems: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockAppElement, kAXChildrenAttribute as CFString, &dockItems) == .success,
              let dockItems = dockItems as? [AXUIElement],
              !dockItems.isEmpty
        else {
            return nil
        }

        var selectedChildren: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockItems.first!, kAXSelectedChildrenAttribute as CFString, &selectedChildren) == .success,
              let selected = selectedChildren as? [AXUIElement],
              let hoveredItem = selected.first
        else {
            return nil
        }

        return hoveredItem
    }

    func getHoveredDockItemElement() -> AXUIElement? {
        getSelectedDockItem()
    }

    func getHoveredApplicationDockItem() -> AXUIElement? {
        guard let item = getSelectedDockItem(),
              (try? item.subrole()) == "AXApplicationDockItem"
        else {
            return nil
        }
        return item
    }

    func getHoveredFolderDockItem() -> FolderDockItemInfo? {
        guard let item = getSelectedDockItem() else { return nil }
        guard (try? item.subrole()) != "AXApplicationDockItem" else { return nil }
        guard let url = try? item.attribute(kAXURLAttribute, NSURL.self)?.absoluteURL else { return nil }
        guard url.pathExtension != "app" else { return nil }

        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        guard values?.isDirectory == true else { return nil }

        let title = (try? item.title()) ?? FileManager.default.displayName(atPath: url.path)
        return FolderDockItemInfo(url: url, title: title, dockItemElement: item)
    }

    /// Returns all dock item children from the dock list.
    private func getAllDockItemChildren() -> [AXUIElement]? {
        guard let dockAppPID = currentDockPID else {
            return nil
        }

        let dockAppElement = AXUIElementCreateApplication(dockAppPID)

        var dockItems: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockAppElement, kAXChildrenAttribute as CFString, &dockItems) == .success,
              let dockItemsList = dockItems as? [AXUIElement],
              let dockList = dockItemsList.first
        else {
            return nil
        }

        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dockList, kAXChildrenAttribute as CFString, &children) == .success,
              let dockChildren = children as? [AXUIElement]
        else {
            return nil
        }

        return dockChildren
    }

    /// Finds the instance index of a hovered dock item among all dock items with the same bundle identifier.
    /// This is used to correctly identify which instance of a multi-instance app is being hovered.
    private func findDockItemInstanceIndex(_ hoveredItem: AXUIElement, bundleIdentifier: String) -> Int {
        guard let allDockItems = getAllDockItemChildren() else {
            return 0
        }

        // Filter to only AXApplicationDockItems with the same bundle ID
        var matchingItems: [AXUIElement] = []
        for item in allDockItems {
            guard (try? item.subrole()) == "AXApplicationDockItem",
                  let itemURL = try? item.attribute(kAXURLAttribute, NSURL.self)?.absoluteURL,
                  let itemBundle = Bundle(url: itemURL),
                  itemBundle.bundleIdentifier == bundleIdentifier
            else {
                continue
            }
            matchingItems.append(item)
        }

        // Find the index of the hovered item among matching items
        for (index, item) in matchingItems.enumerated() {
            if CFEqual(item, hoveredItem) {
                return index
            }
        }

        return 0
    }

    func getDockItemAppStatusUnderMouse() -> ApplicationReturnType {
        guard let hoveredDockItem = getHoveredApplicationDockItem() else {
            return ApplicationReturnType(status: .notFound, dockItemElement: nil)
        }

        do {
            guard let appURL = try hoveredDockItem.attribute(kAXURLAttribute, NSURL.self)?.absoluteURL else {
                throw AxError.runtimeError
            }

            let bundle = Bundle(url: appURL)
            guard let bundleIdentifier = bundle?.bundleIdentifier else {
                guard let dockItemTitle = try hoveredDockItem.title() else {
                    return ApplicationReturnType(status: .notFound, dockItemElement: hoveredDockItem)
                }

                if let app = WindowUtil.findRunningApplicationByName(named: dockItemTitle) {
                    return ApplicationReturnType(status: .success(app), dockItemElement: hoveredDockItem)
                } else {
                    return ApplicationReturnType(status: .notFound, dockItemElement: hoveredDockItem)
                }
            }

            let runningApps = LauncherShortcutResolver.runningApplications(forBundleAt: appURL, bundleIdentifier: bundleIdentifier)

            // For multiple instances, find the correct one based on dock position
            if runningApps.count > 1 {
                let instanceIndex = findDockItemInstanceIndex(hoveredDockItem, bundleIdentifier: bundleIdentifier)
                if instanceIndex < runningApps.count {
                    return ApplicationReturnType(status: .success(runningApps[instanceIndex]), dockItemElement: hoveredDockItem)
                }
            }

            if let runningApp = runningApps.first {
                return ApplicationReturnType(status: .success(runningApp), dockItemElement: hoveredDockItem)
            } else {
                return ApplicationReturnType(status: .notRunning(bundleIdentifier: bundleIdentifier), dockItemElement: hoveredDockItem)
            }
        } catch {
            return ApplicationReturnType(status: .notFound, dockItemElement: hoveredDockItem)
        }
    }

    static func getMousePosition() -> NSPoint {
        guard let event = CGEvent(source: nil) else {
            fatalError("Unable to get mouse event")
        }

        let mouseLocation = event.location

        let mousePosition = NSPoint(x: mouseLocation.x, y: mouseLocation.y)
        return mousePosition
    }

    private static func computeOffsets(for screen: NSScreen, primaryScreen: NSScreen) -> (CGFloat, CGFloat) {
        var offsetLeft = screen.frame.origin.x
        var offsetTop = primaryScreen.frame.size.height - (screen.frame.origin.y + screen.frame.size.height)

        if screen == primaryScreen {
            offsetTop = 0
            offsetLeft = 0
        }

        return (offsetLeft, offsetTop)
    }

    static func nsPointFromCGPoint(_ point: CGPoint, forScreen: NSScreen?) -> NSPoint {
        guard let screen = forScreen,
              let primaryScreen = NSScreen.screens.first
        else {
            return NSPoint(x: point.x, y: point.y)
        }

        let (_, offsetTop) = computeOffsets(for: screen, primaryScreen: primaryScreen)

        let y: CGFloat
        if screen == primaryScreen {
            y = screen.frame.size.height - point.y
        } else {
            let screenBottomOffset = primaryScreen.frame.size.height - (screen.frame.size.height + offsetTop)
            y = screen.frame.size.height + screenBottomOffset - (point.y - offsetTop)
        }

        return NSPoint(x: point.x, y: y)
    }

    static func cgPointFromNSPoint(_ point: CGPoint, forScreen: NSScreen?) -> CGPoint {
        guard let screen = forScreen,
              let primaryScreen = NSScreen.screens.first
        else {
            return CGPoint(x: point.x, y: point.y)
        }

        let (_, offsetTop) = computeOffsets(for: screen, primaryScreen: primaryScreen)
        let menuScreenHeight = screen.frame.maxY

        return CGPoint(x: point.x, y: menuScreenHeight - point.y + offsetTop)
    }

    // Enable dock click detection
    func enableDockClickDetection() {
        setupEventTap()
    }

    private func removeEventTap() {
        if let eventTap {
            let context = eventTapContext
            EventTapThread.shared.remove(eventTap, source: eventTapRunLoopSource) {
                withExtendedLifetime(context) {}
            }
        }
        eventTap = nil
        eventTapRunLoopSource = nil
        eventTapContext = nil
    }

    private static let dockProximityBand: CGFloat = 220

    private func isPointNearDock(_ point: CGPoint) -> Bool {
        let position = DockUtils.getDockPosition()
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetActiveDisplayList(16, &displays, &displayCount) == .success else { return true }
        for display in displays.prefix(Int(displayCount)) {
            let bounds = CGDisplayBounds(display)
            guard bounds.contains(point) else { continue }
            switch position {
            case .left: return point.x - bounds.minX <= Self.dockProximityBand
            case .right: return bounds.maxX - point.x <= Self.dockProximityBand
            case .bottom: return bounds.maxY - point.y <= Self.dockProximityBand
            case .top: return point.y - bounds.minY <= Self.dockProximityBand
            default: return true
            }
        }
        return false
    }

    private func setupEventTap() {
        guard eventTap == nil, DockObserver.canPostEvents else { return }
        let cycleClicks = windowCyclingEnabled ? CycleClickTracker() : nil
        let context = EventTapContext(observer: self, cycleClicks: cycleClicks)
        var eventMask: CGEventMask = (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue)

        if cycleClicks != nil {
            eventMask |= (1 << CGEventType.leftMouseUp.rawValue) |
                (1 << CGEventType.leftMouseDragged.rawValue)
        }

        if Defaults[.enableDockScrollGesture] || Defaults[.enableTitleBarScrollGesture] {
            eventMask |= (1 << CGEventType.scrollWheel.rawValue)
        }

        guard let eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let context = Unmanaged<EventTapContext>.fromOpaque(refcon).takeUnretainedValue()
                guard let observer = context.observer else { return Unmanaged.passUnretained(event) }
                return observer.eventTapCallback(proxy: proxy, type: type, event: event, cycleClicks: context.cycleClicks)
            },
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else {
            print("Failed to create event tap")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)!
        EventTapThread.shared.add(runLoopSource)

        self.eventTap = eventTap
        eventTapContext = context
        eventTapRunLoopSource = runLoopSource
        eventTapHandlesWindowCycling = cycleClicks != nil
    }

    private var windowCyclingEnabled: Bool {
        Defaults[.shouldHideOnDockItemClick] && Defaults[.dockClickAction] == .cycleWindows
    }

    private func eventTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, cycleClicks: CycleClickTracker?) -> Unmanaged<CGEvent>? {
        if let passthrough = reEnableIfNeeded(tap: eventTap, type: type, event: event) {
            cycleClicks?.press = nil
            return passthrough
        }

        if type == .leftMouseDragged {
            // Restore the withheld press before the first drag, without re-entering this tap.
            cycleClicks?.takePress()?.event.tapPostEvent(proxy)
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseUp {
            guard let press = cycleClicks?.takePress() else { return Unmanaged.passUnretained(event) }
            if windowCyclingEnabled,
               !previewCoordinator.containsQuartzPoint(event.location),
               isPointNearDock(event.location),
               case let .success(app) = getDockItemAppStatusUnderMouse().status,
               app.processIdentifier == press.processIdentifier
            {
                currentClickedAppPID = app.processIdentifier
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    cancelDockClickAction(for: app.processIdentifier)
                    prepareForWindowCycle(of: app)
                    cycleThroughWindows(of: app)
                }
                return nil
            }
            press.event.tapPostEvent(proxy)
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown {
            cycleClicks?.press = nil
            let snapshot = previewCoordinator.tapSnapshot
            if snapshot.hasCheckedWindows, !snapshot.isWindowSwitcherActive {
                let clickLocation = NSEvent.mouseLocation
                if snapshot.shouldDismissForOutsideClick(at: clickLocation) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        let current = previewCoordinator.tapSnapshot
                        guard current.hasCheckedWindows, !current.isWindowSwitcherActive,
                              current.shouldDismissForOutsideClick(at: clickLocation) else { return }
                        if current.isCmdTabPreview { teardownCmdTabObserver() }
                        previewCoordinator.hideWindow()
                    }
                }
            }
        }

        if previewCoordinator.containsQuartzPoint(event.location) {
            return Unmanaged.passUnretained(event)
        }

        if type == .scrollWheel {
            if Defaults[.enableTitleBarScrollGesture], handleTitleBarScroll(event) {
                return nil
            }

            guard Defaults[.enableDockScrollGesture], isPointNearDock(event.location) else {
                return Unmanaged.passUnretained(event)
            }

            let appUnderMouse = getDockItemAppStatusUnderMouse()
            if case let .success(app) = appUnderMouse.status {
                let handled = handleDockScroll(app: app, event: event)
                if handled {
                    return nil
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard isPointNearDock(event.location) else {
            return Unmanaged.passUnretained(event)
        }

        let appUnderMouse = getDockItemAppStatusUnderMouse()

        if handleDockPreviewActivation(type: type, event: event, appUnderMouse: appUnderMouse) {
            return nil
        }

        if type == .leftMouseDown, appUnderMouse.dockItemElement != nil {
            DispatchQueue.main.async { [weak self] in
                self?.previewCoordinator.cancelPendingShow()
                self?.previewCoordinator.restoreDockAutoHideState()
            }
        }

        if case let .success(app) = appUnderMouse.status {
            if type == .rightMouseDown, event.flags.contains(.maskCommand), Defaults[.enableCmdRightClickQuit] {
                handleCmdRightClickQuit(app: app, event: event)
                return nil
            }

            if type == .leftMouseDown, event.flags.contains(.maskShift),
               app.bundleIdentifier != Bundle.main.bundleIdentifier
            {
                handleShiftClickNewWindow(app: app)
                return nil
            }

            if type == .leftMouseDown {
                if windowCyclingEnabled,
                   app.bundleIdentifier != Bundle.main.bundleIdentifier,
                   cycleClicks?.begin(app: app, event: event) == true
                {
                    return nil
                }
                let shouldIntercept = handleDockClick(app: app)
                if shouldIntercept {
                    return nil
                }
            }
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleDockPreviewActivation(type: CGEventType, event: CGEvent, appUnderMouse: ApplicationReturnType) -> Bool {
        guard Defaults[.enableDockPreviews],
              !previewCoordinator.tapSnapshot.isWindowSwitcherActive
        else {
            return false
        }

        let shouldActivate = switch Defaults[.dockPreviewActivationMode] {
        case .hover:
            false
        case .middleClick:
            type == .otherMouseDown &&
                event.getIntegerValueField(.mouseEventButtonNumber) == Int64(CGMouseButton.center.rawValue)
        case .modifierClick:
            type == .leftMouseDown && modifierFlagsExactlyMatch(event.flags, Defaults[.dockPreviewActivationModifier].eventFlag)
        }

        guard shouldActivate else { return false }

        let mouseLocation = DockObserver.getMousePosition()

        if let folderItem = getHoveredFolderDockItem() {
            guard Defaults[.enableFolderWidget],
                  FolderWidgetAuthorization.accessibleURL(for: folderItem.url) != nil
            else {
                return false
            }

            Task { @MainActor [weak self] in
                self?.showHoveredFolderDockItemPreviewIfPossible(mouseLocation: mouseLocation)
            }
            return true
        }

        guard appUnderMouse.dockItemElement != nil else {
            return false
        }

        switch appUnderMouse.status {
        case .success:
            break
        case let .notRunning(bundleIdentifier):
            guard canShowSpecialPreview(forNotRunningBundleIdentifier: bundleIdentifier) else {
                return false
            }
        case .notFound:
            return false
        }

        Task { @MainActor [weak self] in
            self?.showPreviewForHoveredDockApp(
                mouseLocation: mouseLocation,
                overrideDelay: true,
                refreshLogContext: "dock preview trigger"
            )
        }
        return true
    }

    private func canShowSpecialPreview(forNotRunningBundleIdentifier bundleIdentifier: String) -> Bool {
        guard Defaults[.showSpecialAppControls] else { return false }

        let isCalendar = bundleIdentifier == calendarAppIdentifier && Defaults[.enableCalendarWidget]
        let mr = MediaRemoteService.shared
        let mediaSourceMatches = mr.matchesMediaSource(bundleIdentifier: bundleIdentifier)
        let isActiveMedia = mediaSourceMatches
            && Defaults[.enableMediaWidget]
            && (!mr.isUniversalSource || Defaults[.mediaDetectionMode] == .universal)

        return isCalendar || isActiveMedia
    }

    private func modifierFlagsExactlyMatch(_ flags: CGEventFlags, _ expectedModifier: CGEventFlags) -> Bool {
        let activeModifiers = flags.intersection([.maskShift, .maskControl, .maskAlternate, .maskCommand])
        return activeModifiers == expectedModifier
    }

    private func handleDockClick(app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        let appName = app.localizedName ?? "Unknown"

        // Skip DockDoor itself to prevent crashes when clicking own dock icon
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return false
        }

        currentClickedAppPID = pid

        let isFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        let wasHiddenAtClickTime = app.isHidden
        let hoverState = dockClickStateSnapshot()
        let hasValidHoverState = hoverState.lastHoveredPID == pid
        let wasFrontmostOnHover = hasValidHoverState ? hoverState.lastHoveredAppWasFrontmost : isFrontmost
        let action = Defaults[.dockClickAction]

        guard Defaults[.shouldHideOnDockItemClick] else { return false }

        switch action {
        case .cycleWindows:
            return false
        case .minimize, .hide:
            break
        }

        let cachedWindows = WindowUtil.readCachedWindows(for: pid).filter { !$0.isWindowlessApp }
        let cachedMinimizableWindows = cachedWindows.filter { $0.isFullscreen != true }
        let allCachedWindowsMinimized = !cachedMinimizableWindows.isEmpty &&
            cachedMinimizableWindows.allSatisfy(\.isMinimized)
        let shouldUseNativeActivation = !wasFrontmostOnHover &&
            !wasHiddenAtClickTime &&
            (action == .hide || !allCachedWindowsMinimized)
        if shouldUseNativeActivation {
            clearLastHoveredDockApp()
            return false
        }

        if action == .minimize,
           hasValidHoverState,
           !hoverState.lastHoveredAppHadWindows,
           !wasHiddenAtClickTime
        {
            clearLastHoveredDockApp()
            return false
        }

        clearLastHoveredDockApp()
        Task { @MainActor [weak self] in
            self?.scheduleDockClickAction(
                app: app,
                appName: appName,
                action: action,
                wasHiddenAtClickTime: wasHiddenAtClickTime
            )
        }

        return true
    }

    @MainActor
    private func prepareForWindowCycle(of app: NSRunningApplication) {
        clearLastHoveredDockApp()
        previewCoordinator.cancelPendingShow()
        if !previewCoordinator.canPreserveDockPreviewsForWindowCycle(of: app.processIdentifier) {
            previewCoordinator.hideWindow()
        }
    }

    @MainActor
    private func cancelDockClickAction(for pid: pid_t) {
        dockClickActionTasks.removeValue(forKey: pid)?.task.cancel()
    }

    @MainActor
    private func scheduleDockClickAction(
        app: NSRunningApplication,
        appName: String,
        action: DockClickAction,
        wasHiddenAtClickTime: Bool
    ) {
        let pid = app.processIdentifier
        cancelDockClickAction(for: pid)
        previewCoordinator.cancelPendingShow()
        previewCoordinator.hideWindow()
        let token = UUID()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if dockClickActionTasks[pid]?.token == token {
                    dockClickActionTasks.removeValue(forKey: pid)
                }
            }

            switch action {
            case .hide:
                let targetHiddenState = !wasHiddenAtClickTime
                if await WindowUtil.setHiddenStateConfirmed(for: app, isHidden: targetHiddenState) {
                    DebugLogger.log("DockClick", details: "\(appName): hidden=\(targetHiddenState)")
                    if !targetHiddenState {
                        app.activate(options: [.activateIgnoringOtherApps])
                    }
                } else {
                    DebugLogger.log("DockClick", details: "\(appName): hidden=\(targetHiddenState) was not confirmed")
                }

            case .minimize:
                let result = await WindowUtil.toggleAllMinimizableWindows(
                    for: app,
                    restoreHiddenAppIfNeeded: wasHiddenAtClickTime
                )
                guard !Task.isCancelled else { return }
                DebugLogger.log(
                    "DockClick",
                    details: "\(appName): minimize-all outcome=\(result.outcome), confirmed=\(result.confirmedCount)/\(result.eligibleCount)"
                )
                if result.shouldActivateApp {
                    app.activate(options: [.activateIgnoringOtherApps])
                }

            case .cycleWindows:
                break
            }
        }
        dockClickActionTasks[pid] = PendingDockClickAction(token: token, task: task)
    }

    private func updateDockClickHoverState(pid: pid_t, wasFrontmost: Bool, hadWindows: Bool) {
        dockClickStateLock.lock()
        dockClickState.lastHoveredPID = pid
        dockClickState.lastHoveredAppWasFrontmost = wasFrontmost
        dockClickState.lastHoveredAppHadWindows = hadWindows
        dockClickStateLock.unlock()
    }

    private func dockClickStateSnapshot() -> DockClickState {
        dockClickStateLock.lock()
        defer { dockClickStateLock.unlock() }
        return dockClickState
    }

    private func clearLastHoveredDockApp() {
        dockClickStateLock.lock()
        dockClickState.lastHoveredPID = nil
        dockClickStateLock.unlock()
    }

    @MainActor
    private func updateWindowCycleHover(for processIdentifier: pid_t) -> Int {
        guard cycleHoverProcessIdentifier != processIdentifier else { return cycleHoverGeneration }
        resetWindowCycleHover()
        cycleHoverProcessIdentifier = processIdentifier
        return cycleHoverGeneration
    }

    @MainActor
    private func resetWindowCycleHover() {
        cycleHoverGeneration &+= 1
        windowCycleState = nil
        cycleHoverProcessIdentifier = nil
    }

    @MainActor
    private func cycleThroughWindows(of app: NSRunningApplication) {
        let hoverGeneration = updateWindowCycleHover(for: app.processIdentifier)
        let cachedWindows = WindowUtil.readCachedWindows(for: app.processIdentifier)
            .filter { !$0.isWindowlessApp }

        if cachedWindows.isEmpty {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let windows = await (try? WindowUtil.getActiveWindows(of: app, ignoreSingleWindowFilter: true)) ?? []
                activateNextWindow(of: app, from: windows, hoverGeneration: hoverGeneration)
            }
        } else {
            activateNextWindow(of: app, from: cachedWindows, hoverGeneration: hoverGeneration)
        }
    }

    @MainActor
    private func activateNextWindow(of app: NSRunningApplication, from windows: [WindowInfo], hoverGeneration: Int) {
        guard cycleHoverProcessIdentifier == app.processIdentifier,
              cycleHoverGeneration == hoverGeneration
        else {
            return
        }

        let windowsByRecentUse = windows
            .filter { !$0.isWindowlessApp }
            .sorted { $0.lastAccessedTime > $1.lastAccessedTime }

        guard !windowsByRecentUse.isEmpty else {
            windowCycleState = nil
            WindowUtil.activateWindowlessApp(app: app)
            return
        }

        let windowIDs = windowsByRecentUse.map(\.id)
        let processIdentifier = app.processIdentifier
        let focusedWindow = (try? AXUIElementCreateApplication(processIdentifier).focusedWindow()) ?? nil
        let focusedWindowID = focusedWindow.flatMap { try? $0.cgWindowId() }

        let nextIndex: Int
        if var state = windowCycleState,
           Set(state.orderedWindowIDs) == Set(windowIDs)
        {
            state.nextIndex %= state.orderedWindowIDs.count
            nextIndex = state.nextIndex
            state.nextIndex = (nextIndex + 1) % state.orderedWindowIDs.count
            windowCycleState = state
        } else {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier,
               let focusedWindowID,
               let focusedIndex = windowIDs.firstIndex(of: focusedWindowID)
            {
                nextIndex = (focusedIndex + 1) % windowIDs.count
            } else {
                nextIndex = 0
            }
            windowCycleState = WindowCycleState(
                orderedWindowIDs: windowIDs,
                nextIndex: (nextIndex + 1) % windowIDs.count
            )
        }

        let targetWindowID = windowCycleState?.orderedWindowIDs[nextIndex] ?? windowIDs[nextIndex]
        guard let targetWindow = windowsByRecentUse.first(where: { $0.id == targetWindowID }) else {
            windowCycleState = nil
            return
        }

        DebugLogger.log("DockCycle", details: "PID: \(processIdentifier), target: \(targetWindowID), focused: \(String(describing: focusedWindowID)), hover generation: \(hoverGeneration)")

        if targetWindow.isMinimized || app.isHidden {
            scheduleCycledWindowActivation(
                targetWindow,
                app: app,
                hoverGeneration: hoverGeneration
            )
        } else {
            cancelDockClickAction(for: app.processIdentifier)
            let keptPreviewsOpen = previewCoordinator.preserveDockPreviewsForWindowCycle(to: targetWindow)
            targetWindow.bringToFront()
            if keptPreviewsOpen {
                previewCoordinator.windowSwitcherCoordinator.scheduleActiveFocusedWindowRefresh()
            }
        }
    }

    @MainActor
    private func scheduleCycledWindowActivation(
        _ targetWindow: WindowInfo,
        app: NSRunningApplication,
        hoverGeneration: Int
    ) {
        let pid = app.processIdentifier
        cancelDockClickAction(for: pid)
        let token = UUID()

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if dockClickActionTasks[pid]?.token == token {
                    dockClickActionTasks.removeValue(forKey: pid)
                }
            }

            previewCoordinator.preserveDockPreviewsForWindowCycle(to: targetWindow)
            if app.isHidden {
                guard await WindowUtil.setHiddenStateConfirmed(for: app, isHidden: false) else {
                    return
                }
            }
            guard !Task.isCancelled else { return }

            if targetWindow.isMinimized {
                guard await WindowUtil.setMinimizedStateConfirmed([targetWindow], isMinimized: false) > 0 else {
                    return
                }
            }
            guard !Task.isCancelled,
                  cycleHoverProcessIdentifier == pid,
                  cycleHoverGeneration == hoverGeneration
            else { return }

            let keptPreviewsOpen = previewCoordinator.preserveDockPreviewsForWindowCycle(to: targetWindow)
            app.activate(options: [.activateIgnoringOtherApps])
            targetWindow.bringToFront()
            if keptPreviewsOpen {
                previewCoordinator.windowSwitcherCoordinator.scheduleActiveFocusedWindowRefresh()
            }
        }
        dockClickActionTasks[pid] = PendingDockClickAction(token: token, task: task)
    }

    private func handleShiftClickNewWindow(app: NSRunningApplication) {
        DispatchQueue.main.async { [weak self] in
            self?.previewCoordinator.cancelPendingShow()
            WindowUtil.activateAndOpenNewWindow(app: app)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.previewCoordinator.hideWindow()
        }
    }

    private func showPreviewForFocusedApp(app: NSRunningApplication) {
        if WindowUtil.isAppFiltered(app) {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }

            let currentMouseLocation = DockObserver.getMousePosition()
            let appUnderMouseElement = getDockItemAppStatusUnderMouse()

            guard case let .success(currentApp) = appUnderMouseElement.status,
                  currentApp.processIdentifier == app.processIdentifier,
                  let dockItemElement = appUnderMouseElement.dockItemElement
            else {
                return
            }

            do {
                let windows = try await WindowUtil.getActiveWindows(of: app)
                let mouseScreen = NSScreen.screenFromQuartzPoint(currentMouseLocation)
                let convertedMouseLocation = DockObserver.nsPointFromCGPoint(currentMouseLocation, forScreen: mouseScreen)

                previewCoordinator.showWindow(
                    appName: app.localizedName ?? "Unknown",
                    windows: windows,
                    mouseLocation: convertedMouseLocation,
                    mouseScreen: mouseScreen,
                    dockItemElement: dockItemElement,
                    overrideDelay: true,
                    onWindowTap: { [weak self] in
                        self?.hideWindowAndResetLastApp()
                    },
                    bundleIdentifier: app.bundleIdentifier
                )
            } catch {
                // If we can't get windows, still show the preview for special apps if enabled
                if Self.isSpecialControlsApp(app.bundleIdentifier), Defaults[.showSpecialAppControls] {
                    let mouseScreen = NSScreen.screenFromQuartzPoint(currentMouseLocation)
                    let convertedMouseLocation = DockObserver.nsPointFromCGPoint(currentMouseLocation, forScreen: mouseScreen)

                    previewCoordinator.showWindow(
                        appName: app.localizedName ?? "Unknown",
                        windows: [],
                        mouseLocation: convertedMouseLocation,
                        mouseScreen: mouseScreen,
                        dockItemElement: dockItemElement,
                        overrideDelay: true,
                        onWindowTap: { [weak self] in
                            self?.hideWindowAndResetLastApp()
                        },
                        bundleIdentifier: app.bundleIdentifier
                    )
                }
            }
        }
    }

    private func handleCmdRightClickQuit(app: NSRunningApplication, event: CGEvent) {
        Task { @MainActor in
            if event.flags.contains(.maskAlternate) {
                app.forceTerminate()
            } else {
                app.terminate()
            }
        }
    }

    private func handleDockScroll(app: NSRunningApplication, event: CGEvent) -> Bool {
        let deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)

        // Ignore noise (very small scroll amounts)
        guard abs(deltaY) > 0.1 else { return false }

        let nsEvent = NSEvent(cgEvent: event)
        let isNaturalScrolling = nsEvent?.isDirectionInvertedFromDevice ?? false
        let normalizedDeltaY = isNaturalScrolling ? -deltaY : deltaY

        if Defaults[.dockIconScrollBehavior] == .bringAppWindowsToCurrentSpace {
            let now = Date()
            guard now.timeIntervalSince(lastDockScrollActionTime) >= dockScrollActionDebounceInterval else {
                return true
            }
            lastDockScrollActionTime = now

            WindowUtil.moveAppWindowsToCurrentManagedSpace(for: app)
            Task { @MainActor in
                previewCoordinator.hideWindow()
            }
            return true
        }

        if app.bundleIdentifier == spotifyAppIdentifier || app.bundleIdentifier == appleMusicAppIdentifier {
            if Defaults[.dockIconMediaScrollBehavior] == .adjustVolume {
                handleVolumeScroll(deltaY: normalizedDeltaY)
                return true
            }
        }

        let now = Date()
        guard now.timeIntervalSince(lastDockScrollActionTime) >= dockScrollActionDebounceInterval else {
            return true // Still consume the event during debounce
        }
        lastDockScrollActionTime = now

        if normalizedDeltaY > 0 {
            activateApp(app)
        } else {
            hideApp(app)
        }

        return true
    }

    private func handleVolumeScroll(deltaY: Double) {
        let sensitivity: Float = 0.015
        let current = AudioDeviceManager.getSystemVolume()
        let newVolume = max(0, min(1, current + Float(deltaY) * sensitivity))
        AudioDeviceManager.setSystemVolume(newVolume)
    }

    private func activateApp(_ app: NSRunningApplication) {
        Task { @MainActor in
            if app.isHidden {
                app.unhide()
            }
            app.activate(options: [.activateIgnoringOtherApps])
            previewCoordinator.hideWindow()
        }
    }

    private func hideApp(_ app: NSRunningApplication) {
        Task { @MainActor in
            app.hide()
            previewCoordinator.hideWindow()
        }
    }

    private func scheduleTitleBarCacheRefresh() {
        titleBarCacheLock.lock()
        guard !titleBarRefreshScheduled else {
            titleBarCacheLock.unlock()
            return
        }
        titleBarRefreshScheduled = true
        titleBarCacheLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            refreshTitleBarCache()
        }
    }

    private func refreshTitleBarCache() {
        guard let focusedWindow = WindowUtil.getFocusedWindowForFrontmostApp(),
              let windowFrame = focusedWindow.currentWindowFrame()
        else {
            replaceTitleBarCache(with: nil)
            return
        }

        let titleBarHeight = resolvedTitleBarHeight(for: focusedWindow, windowFrame: windowFrame)
        let titleBarRect = CGRect(
            x: windowFrame.minX,
            y: windowFrame.maxY - titleBarHeight,
            width: windowFrame.width,
            height: titleBarHeight
        )

        let updatedInfo = CachedTitleBarInfo(
            window: focusedWindow,
            windowFrame: windowFrame,
            titleBarRect: titleBarRect,
            timestamp: Date()
        )
        replaceTitleBarCache(with: updatedInfo)
    }

    private func replaceTitleBarCache(with info: CachedTitleBarInfo?) {
        titleBarCacheLock.lock()
        cachedTitleBarInfo = info
        titleBarRefreshScheduled = false
        titleBarCacheLock.unlock()
    }

    private func titleBarCacheSnapshot() -> CachedTitleBarInfo? {
        titleBarCacheLock.lock()
        defer { titleBarCacheLock.unlock() }
        return cachedTitleBarInfo
    }

    private func handleTitleBarScroll(_ event: CGEvent) -> Bool {
        let deltaX = event.getDoubleValueField(.scrollWheelEventDeltaAxis2)
        let deltaY = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)

        guard abs(deltaX) > minimumTitleBarScrollDelta || abs(deltaY) > minimumTitleBarScrollDelta else {
            return false
        }

        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 {
            return false
        }

        guard let cached = titleBarCacheSnapshot(),
              Date().timeIntervalSince(cached.timestamp) <= titleBarCacheMaxAge
        else {
            scheduleTitleBarCacheRefresh()
            return false
        }

        guard cached.titleBarRect.contains(NSEvent.mouseLocation) else {
            return false
        }

        let nsEvent = NSEvent(cgEvent: event)
        let isNaturalScrolling = nsEvent?.isDirectionInvertedFromDevice ?? false
        let normalizedDeltaX = isNaturalScrolling ? -deltaX : deltaX
        let normalizedDeltaY = isNaturalScrolling ? -deltaY : deltaY

        let now = Date()
        guard now.timeIntervalSince(lastTitleBarScrollActionTime) >= titleBarScrollActionDebounceInterval else {
            return true
        }
        lastTitleBarScrollActionTime = now

        let window = cached.window

        if abs(normalizedDeltaX) > abs(normalizedDeltaY) {
            DispatchQueue.main.async { [weak self] in
                if normalizedDeltaX > 0 {
                    self?.switchToNextSpace()
                } else {
                    self?.switchToPreviousSpace()
                }
            }
            return true
        }

        DispatchQueue.main.async { [weak self] in
            if normalizedDeltaY > 0 {
                self?.handleTitleBarVerticalScroll(.maximize, for: window, now: now)
            } else {
                self?.handleTitleBarVerticalScroll(.center, for: window, now: now)
            }
        }

        return true
    }

    private func handleTitleBarVerticalScroll(_ action: VerticalScrollAction, for window: WindowInfo, now: Date) {
        if let pendingTitleBarRestoreState,
           pendingTitleBarRestoreState.windowId == window.id,
           pendingTitleBarRestoreState.processIdentifier == window.app.processIdentifier,
           pendingTitleBarRestoreState.action == action,
           pendingTitleBarRestoreState.expirationDate > now
        {
            window.setWindowFrame(pendingTitleBarRestoreState.originalFrame)
            self.pendingTitleBarRestoreState = nil
            return
        }

        guard let originalFrame = window.currentWindowFrame() else {
            performTitleBarVerticalScrollAction(action, on: window)
            pendingTitleBarRestoreState = nil
            return
        }

        performTitleBarVerticalScrollAction(action, on: window)
        pendingTitleBarRestoreState = PendingRestoreState(
            windowId: window.id,
            processIdentifier: window.app.processIdentifier,
            action: action,
            originalFrame: originalFrame,
            expirationDate: now.addingTimeInterval(Double(Defaults[.titleBarScrollRestoreWindowInterval]))
        )
    }

    private func performTitleBarVerticalScrollAction(_ action: VerticalScrollAction, on window: WindowInfo) {
        switch action {
        case .maximize:
            window.zoom()
        case .center:
            switch centeredWindowSizingMode {
            case .uniform:
                window.centerWindow(scale: centeredWindowScale)
            case .separate:
                window.centerWindow(
                    widthScale: centeredWindowWidthScale,
                    heightScale: centeredWindowHeightScale,
                    lockAspectRatio: centeredWindowLockAspectRatio
                )
            }
        }
    }

    private func resolvedTitleBarHeight(for window: WindowInfo, windowFrame: CGRect) -> CGFloat {
        let closeButton = window.closeButton ?? window.axElement.resolvedCloseButton()
        guard let closeButton,
              let closeButtonFrame = WindowInfo.currentWindowFrame(for: closeButton)
        else {
            return fallbackTitleBarHeight
        }

        let inferredHeight = windowFrame.maxY - closeButtonFrame.minY + 12
        return min(max(inferredHeight, fallbackTitleBarHeight), maximumTitleBarHeight)
    }

    private func switchToPreviousSpace() {
        postControlArrowKey(CGKeyCode(kVK_LeftArrow))
    }

    private func switchToNextSpace() {
        postControlArrowKey(CGKeyCode(kVK_RightArrow))
    }

    private func postControlArrowKey(_ keyCode: CGKeyCode) {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        let controlDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Control), keyDown: true)
        controlDown?.flags = .maskControl

        let arrowDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        arrowDown?.flags = .maskControl

        let arrowUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        arrowUp?.flags = .maskControl

        let controlUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Control), keyDown: false)

        controlDown?.post(tap: .cghidEventTap)
        arrowDown?.post(tap: .cghidEventTap)
        arrowUp?.post(tap: .cghidEventTap)
        controlUp?.post(tap: .cghidEventTap)
    }
}
