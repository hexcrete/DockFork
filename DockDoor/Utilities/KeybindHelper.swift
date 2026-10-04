import AppKit
import Carbon
import Carbon.HIToolbox.Events
import Defaults

private class KeybindHelperUserInfo {
    let instance: KeybindHelper
    init(instance: KeybindHelper) {
        self.instance = instance
    }
}

struct UserKeyBind: Codable, Defaults.Serializable, Equatable, Hashable {
    var keyCode: UInt16
    var modifierFlags: Int
    var modifierSide: ModifierKeySide

    init(keyCode: UInt16, modifierFlags: Int, modifierSide: ModifierKeySide = .either) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.modifierSide = modifierSide
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifierFlags
        case modifierSide
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        modifierFlags = try container.decode(Int.self, forKey: .modifierFlags)
        modifierSide = try container.decodeIfPresent(ModifierKeySide.self, forKey: .modifierSide) ?? .either
    }
}

private enum WindowSwitcherLaunchSource: Equatable {
    case keyboard
    case persistent

    var dismissesOnModifierRelease: Bool {
        self == .keyboard
    }

    var startsOnSecondWindow: Bool {
        Defaults[.useClassicWindowOrdering]
    }

    var startsUnfocused: Bool {
        self == .persistent && Defaults[.persistentSwitcherStartsUnfocused]
    }

    var showsInstantly: Bool {
        switch self {
        case .keyboard: Defaults[.instantWindowSwitcher]
        case .persistent: true
        }
    }

    var focusesSearchOnOpen: Bool {
        switch self {
        case .keyboard: Defaults[.focusSearchOnWindowSwitcherOpen]
        case .persistent: true
        }
    }
}

private class WindowSwitchingCoordinator {
    private var isProcessingSwitcher = false
    private var uiRenderingTask: Task<Void, Never>?
    private var windowRefreshTask: Task<Void, Never>?
    private var currentSessionId = UUID()
    private var activeLaunchSource: WindowSwitcherLaunchSource?
    /// When true, initialization should complete but immediately select the window instead of showing UI
    private var shouldSelectImmediately = false

    private static var lastUpdateAllWindowsTime: Date?
    private static let updateAllWindowsThrottleInterval: TimeInterval = 5.0

    @MainActor
    @discardableResult
    func handleWindowSwitching(
        previewCoordinator: SharedPreviewWindowCoordinator,
        isModifierPressed: Bool,
        isBackwardPressed: Bool,
        mode: SwitcherInvocationMode = .allWindows
    ) async -> Bool {
        guard !isProcessingSwitcher else { return false }
        isProcessingSwitcher = true
        defer { isProcessingSwitcher = false }

        let coordinator = previewCoordinator.windowSwitcherCoordinator

        if coordinator.isKeybindSessionActive {
            coordinator.hasMovedSinceOpen = false
            coordinator.initialHoverLocation = nil

            if isBackwardPressed {
                coordinator.cycleBackward()
            } else {
                coordinator.cycleForward()
            }
            return true
        } else if isModifierPressed {
            return await initializeWindowSwitching(
                previewCoordinator: previewCoordinator,
                mode: mode,
                launchSource: .keyboard
            )
        }
        return false
    }

    @MainActor
    func switchScope(
        previewCoordinator: SharedPreviewWindowCoordinator,
        mode: SwitcherInvocationMode,
        launchSourceOverride: WindowSwitcherLaunchSource? = nil
    ) async -> Bool {
        guard !isProcessingSwitcher else { return false }
        let coordinator = previewCoordinator.windowSwitcherCoordinator
        guard coordinator.isKeybindSessionActive else { return false }

        isProcessingSwitcher = true
        defer { isProcessingSwitcher = false }

        currentSessionId = UUID()
        let sessionId = currentSessionId
        windowRefreshTask?.cancel()
        uiRenderingTask?.cancel()
        let needsRender = !previewCoordinator.isVisible || !coordinator.windowSwitcherActive
        let launchSource = launchSourceOverride ?? activeLaunchSource ?? .keyboard
        activeLaunchSource = launchSource

        let windows = buildSwitcherWindows(mode: mode)

        let dockPosition = DockUtils.getDockPosition()
        let targetScreen = getTargetScreenForSwitcher()
        applyRefreshedSwitcherWindows(
            windows,
            coordinator: coordinator,
            dockPosition: dockPosition,
            bestGuessMonitor: targetScreen,
            fallbackToFirst: !launchSource.startsUnfocused
        )
        if launchSource.startsUnfocused {
            coordinator.setIndex(to: -1, shouldScroll: false, source: .programmatic)
        }
        coordinator.onFrameRefreshNeeded?()

        if needsRender {
            let currentMouseLocation = DockObserver.getMousePosition()
            uiRenderingTask = Task { @MainActor in
                if !launchSource.showsInstantly {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                await renderWindowSwitcherUI(
                    previewCoordinator: previewCoordinator,
                    mode: mode,
                    dockPosition: dockPosition,
                    currentMouseLocation: currentMouseLocation,
                    targetScreen: targetScreen,
                    sessionId: sessionId,
                    launchSource: launchSource
                )
            }
        }

        if windows.isEmpty {
            startBackgroundRefresh(
                previewCoordinator: previewCoordinator,
                mode: mode,
                dockPosition: dockPosition,
                targetScreen: targetScreen,
                sessionId: sessionId,
                priority: .userInitiated,
                selectFirstWindow: !launchSource.startsUnfocused
            )
        } else if !needsRender {
            scheduleWindowRefresh(
                previewCoordinator: previewCoordinator,
                mode: mode,
                dockPosition: dockPosition,
                targetScreen: targetScreen,
                sessionId: sessionId
            )
        }
        return true
    }

    @MainActor
    func openPersistent(
        previewCoordinator: SharedPreviewWindowCoordinator,
        mode: SwitcherInvocationMode
    ) async {
        guard !isProcessingSwitcher,
              !previewCoordinator.windowSwitcherCoordinator.isKeybindSessionActive
        else { return }

        isProcessingSwitcher = true
        defer { isProcessingSwitcher = false }
        _ = await initializeWindowSwitching(
            previewCoordinator: previewCoordinator,
            mode: mode,
            launchSource: .persistent
        )
    }

    @MainActor
    func eligibleRealWindows(mode: SwitcherInvocationMode) -> [WindowInfo] {
        buildSwitcherWindows(mode: mode, forceRecencyOrder: true).filter { !$0.isWindowlessApp }
    }

    @MainActor
    private func initializeWindowSwitching(
        previewCoordinator: SharedPreviewWindowCoordinator,
        mode: SwitcherInvocationMode = .allWindows,
        launchSource: WindowSwitcherLaunchSource
    ) async -> Bool {
        HangDiagnostics.record("switcher initialization started mode=\(mode.rawValue)")
        activeLaunchSource = nil
        // Reset the immediate-select flag at start of initialization
        shouldSelectImmediately = false
        windowRefreshTask?.cancel()

        currentSessionId = UUID()
        let sessionId = currentSessionId
        let targetScreen = getTargetScreenForSwitcher()
        let currentMouseLocation = DockObserver.getMousePosition()
        let dockPosition = DockUtils.getDockPosition()

        let windows = buildSwitcherWindows(mode: mode)

        HangDiagnostics.record("switcher cache ready mode=\(mode.rawValue) windows=\(windows.count)")

        let coordinator = previewCoordinator.windowSwitcherCoordinator
        coordinator.initializeForWindowSwitcher(
            with: windows,
            dockPosition: dockPosition,
            bestGuessMonitor: targetScreen,
            startOnSecondWindow: launchSource.startsOnSecondWindow,
            startUnfocused: launchSource.startsUnfocused
        )
        activeLaunchSource = launchSource
        coordinator.activateKeybindSession()

        // If modifier was released during initialization, immediately select and exit
        if launchSource == .keyboard, shouldSelectImmediately {
            if let selectedWindow = coordinator.getCurrentWindow() {
                selectedWindow.bringToFront()
                selectedWindow.warpMouseToCenterIfNeeded()
            }
            coordinator.deactivateKeybindSession()
            activeLaunchSource = nil
            previewCoordinator.hideWindow()
            shouldSelectImmediately = false
            return true
        }

        uiRenderingTask?.cancel()
        uiRenderingTask = Task { @MainActor in
            if !launchSource.showsInstantly {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            await renderWindowSwitcherUI(
                previewCoordinator: previewCoordinator,
                mode: mode,
                dockPosition: dockPosition,
                currentMouseLocation: currentMouseLocation,
                targetScreen: targetScreen,
                sessionId: sessionId,
                launchSource: launchSource
            )
        }
        if windows.isEmpty {
            startBackgroundRefresh(
                previewCoordinator: previewCoordinator,
                mode: mode,
                dockPosition: dockPosition,
                targetScreen: targetScreen,
                sessionId: sessionId,
                priority: .userInitiated,
                selectFirstWindow: !launchSource.startsUnfocused
            )
        }
        return true
    }

    @MainActor
    private func buildSwitcherWindows(
        mode: SwitcherInvocationMode,
        forceRecencyOrder: Bool = false
    ) -> [WindowInfo] {
        var windows: [WindowInfo]
        if mode == .allWindows {
            windows = WindowUtil.getAllWindowsOfAllApps()
        } else {
            windows = WindowUtil.collapseNativeTabsIfNeeded(WindowUtil.getAllWindowsIgnoringSwitcherFilters())
            if !Defaults[.includeHiddenWindowsInSwitcher] {
                windows = windows.filter { !$0.isEffectivelyHiddenForUI && !$0.isMinimized }
            }
        }
        let windowsForWindowlessDetection = windows

        let filterBySpace = (mode == .currentSpaceOnly || mode == .currentMonitorCurrentSpace || mode == .activeAppCurrentSpace)
            || (mode == .allWindows && Defaults[.showWindowsFromCurrentSpaceOnlyInSwitcher])
        if filterBySpace {
            windows = WindowUtil.filterWindowsByCurrentSpace(windows)
        }

        let filterByMonitor = mode == .currentMonitorOnly || mode == .currentMonitorCurrentSpace
            || (mode == .allWindows && Defaults[.showWindowsFromCurrentMonitorOnlyInSwitcher])
        if filterByMonitor {
            windows = WindowUtil.filterWindowsByCurrentMonitor(windows)
        }

        let filterByApp = isActiveAppMode(mode)
        if filterByApp {
            windows = WindowUtil.getWindowsForFrontmostApp(from: windows)
        }

        if !Defaults[.includeHiddenWindowsInSwitcher] {
            windows = windows.filter { !$0.isHidden && !$0.isMinimized }
        }

        windows = forceRecencyOrder
            ? WindowUtil.sortWindowsForSwitcherByRecency(windows)
            : WindowUtil.sortWindowsForSwitcher(windows)

        if !filterByApp {
            windows = WindowUtil.groupWindowsByApp(windows)
        }

        let excludesWindowlessApps = (Defaults[.excludeWindowlessAppsFromCurrentMonitorSwitcherScopes]
            && (mode == .currentMonitorOnly || mode == .currentMonitorCurrentSpace))
            || (Defaults[.excludeWindowlessAppsFromCurrentSpaceSwitcherScopes]
                && (mode == .currentSpaceOnly || mode == .currentMonitorCurrentSpace))
        if !filterByApp, Defaults[.showWindowlessAppsInSwitcher], !excludesWindowlessApps {
            windows.append(contentsOf: WindowUtil.getWindowlessRunningApps(existingWindows: windowsForWindowlessDetection))
        }

        return windows
    }

    private func isActiveAppMode(_ mode: SwitcherInvocationMode) -> Bool {
        (mode == .activeAppOnly || mode == .activeAppCurrentSpace)
            || (mode == .allWindows && Defaults[.limitSwitcherToFrontmostApp])
    }

    @MainActor
    private func scheduleWindowRefresh(
        previewCoordinator: SharedPreviewWindowCoordinator,
        mode: SwitcherInvocationMode,
        dockPosition: DockPosition,
        targetScreen: NSScreen,
        sessionId: UUID
    ) {
        let now = Date()
        if let lastUpdate = WindowSwitchingCoordinator.lastUpdateAllWindowsTime,
           now.timeIntervalSince(lastUpdate) < WindowSwitchingCoordinator.updateAllWindowsThrottleInterval
        {
            return
        }
        startBackgroundRefresh(
            previewCoordinator: previewCoordinator,
            mode: mode,
            dockPosition: dockPosition,
            targetScreen: targetScreen,
            sessionId: sessionId,
            priority: .low
        )
    }

    @MainActor
    private func startBackgroundRefresh(
        previewCoordinator: SharedPreviewWindowCoordinator,
        mode: SwitcherInvocationMode,
        dockPosition: DockPosition,
        targetScreen: NSScreen,
        sessionId: UUID,
        priority: TaskPriority,
        selectFirstWindow: Bool = false
    ) {
        WindowSwitchingCoordinator.lastUpdateAllWindowsTime = Date()

        windowRefreshTask?.cancel()
        windowRefreshTask = Task.detached(priority: priority) { [weak self, weak previewCoordinator, mode, dockPosition, targetScreen, sessionId] in
            await WindowUtil.updateAllWindowsInCurrentSpace()
            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self, weak previewCoordinator] in
                guard let self, let previewCoordinator else { return }
                guard sessionId == currentSessionId else { return }

                let coordinator = previewCoordinator.windowSwitcherCoordinator
                guard coordinator.isKeybindSessionActive else { return }

                let freshWindows = buildSwitcherWindows(mode: mode)
                guard !freshWindows.isEmpty else { return }

                applyRefreshedSwitcherWindows(
                    freshWindows,
                    coordinator: coordinator,
                    dockPosition: dockPosition,
                    bestGuessMonitor: targetScreen,
                    fallbackToFirst: selectFirstWindow
                )
            }
        }
    }

    @MainActor
    private func applyRefreshedSwitcherWindows(
        _ freshWindows: [WindowInfo],
        coordinator: PreviewStateCoordinator,
        dockPosition: DockPosition,
        bestGuessMonitor: NSScreen,
        fallbackToFirst: Bool = false
    ) {
        let selectedWindow = coordinator.getCurrentWindow()
        let previousSelectionSource = coordinator.selectionInputSource
        let previousWindowCount = coordinator.windows.count

        // Replace the global switcher list rather than using the single-app merge path.
        // Windowless entries can share window ID 0, so preserving the full rebuilt list is safer.
        coordinator.setWindows(freshWindows, dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor)

        if let selectedWindow,
           let newIndex = coordinator.windows.firstIndex(where: { isSameSwitcherWindow($0, selectedWindow) })
        {
            coordinator.setIndex(to: newIndex, source: previousSelectionSource)
        } else if fallbackToFirst, !coordinator.windows.isEmpty {
            coordinator.setIndex(to: 0, source: .keyboard)
        }

        if coordinator.windows.count != previousWindowCount {
            coordinator.onFrameRefreshNeeded?()
        }
    }

    private func isSameSwitcherWindow(_ first: WindowInfo, _ second: WindowInfo) -> Bool {
        // Window ID alone is not enough here because placeholder/windowless entries use 0.
        first.id == second.id &&
            first.app.processIdentifier == second.app.processIdentifier
    }

    @MainActor
    private func renderWindowSwitcherUI(
        previewCoordinator: SharedPreviewWindowCoordinator,
        mode: SwitcherInvocationMode,
        dockPosition: DockPosition,
        currentMouseLocation: CGPoint,
        targetScreen: NSScreen,
        sessionId: UUID,
        launchSource: WindowSwitcherLaunchSource
    ) async {
        guard sessionId == currentSessionId else { return }
        let coordinator = previewCoordinator.windowSwitcherCoordinator
        guard coordinator.isKeybindSessionActive else { return }

        if previewCoordinator.isVisible, coordinator.windowSwitcherActive {
            return
        }
        let showWindowLambda = { (mouseLocation: NSPoint?, mouseScreen: NSScreen?) in
            let windows = coordinator.windows
            previewCoordinator.showWindow(
                appName: "Window Switcher",
                windows: windows,
                mouseLocation: mouseLocation,
                mouseScreen: mouseScreen,
                dockItemElement: nil,
                overrideDelay: true,
                centeredHoverWindowState: .windowSwitcher,
                onWindowTap: {
                    self.cancelSwitching(previewCoordinator: previewCoordinator)
                    Task { @MainActor in
                        previewCoordinator.hideWindow()
                    }
                },
                initialIndex: coordinator.currIndex
            )
        }

        switch Defaults[.windowSwitcherPlacementStrategy] {
        case .pinnedToScreen:
            let screenCenter = NSPoint(x: targetScreen.frame.midX, y: targetScreen.frame.midY)
            showWindowLambda(screenCenter, targetScreen)
        case .screenWithLastActiveWindow:
            showWindowLambda(nil, nil)
        case .screenWithMouse:
            let mouseScreen = NSScreen.screenFromQuartzPoint(currentMouseLocation)
            let convertedMouseLocation = DockObserver.nsPointFromCGPoint(currentMouseLocation, forScreen: mouseScreen)
            showWindowLambda(convertedMouseLocation, mouseScreen)
        }

        if launchSource.focusesSearchOnOpen, Defaults[.enableWindowSwitcherSearch] {
            previewCoordinator.focusSearchWindow()
        }

        // Refresh only once the switcher is actually on screen, so quick press-release
        // invocations that never render skip the discovery pass entirely.
        scheduleWindowRefresh(
            previewCoordinator: previewCoordinator,
            mode: mode,
            dockPosition: dockPosition,
            targetScreen: targetScreen,
            sessionId: sessionId
        )
    }

    private func getTargetScreenForSwitcher() -> NSScreen {
        if Defaults[.windowSwitcherPlacementStrategy] == .pinnedToScreen,
           let pinnedScreen = NSScreen.findScreen(byIdentifier: Defaults[.pinnedScreenIdentifier])
        {
            return pinnedScreen
        }
        let mouseLocation = DockObserver.getMousePosition()
        return NSScreen.screenFromQuartzPoint(mouseLocation)
    }

    @MainActor
    func selectCurrentWindow(previewCoordinator: SharedPreviewWindowCoordinator) -> WindowInfo? {
        let coordinator = previewCoordinator.windowSwitcherCoordinator
        guard coordinator.isKeybindSessionActive else { return nil }

        let selectedWindow = coordinator.getCurrentWindow()
        currentSessionId = UUID()
        windowRefreshTask?.cancel()
        coordinator.deactivateKeybindSession()
        activeLaunchSource = nil
        uiRenderingTask?.cancel()
        return selectedWindow
    }

    func isActive(previewCoordinator: SharedPreviewWindowCoordinator) -> Bool {
        previewCoordinator.windowSwitcherCoordinator.isKeybindSessionActive
    }

    var dismissesOnModifierRelease: Bool {
        activeLaunchSource?.dismissesOnModifierRelease == true
    }

    @MainActor
    func cancelSwitching(previewCoordinator: SharedPreviewWindowCoordinator) {
        currentSessionId = UUID()
        shouldSelectImmediately = false
        windowRefreshTask?.cancel()
        previewCoordinator.windowSwitcherCoordinator.deactivateKeybindSession()
        activeLaunchSource = nil
        uiRenderingTask?.cancel()
    }

    /// Signals that the modifier was released during initialization.
    /// If initialization is still in progress, it will complete but immediately select the window.
    /// If initialization already completed, this just cancels the UI rendering task.
    @MainActor
    func cancelPendingRender() {
        currentSessionId = UUID()
        shouldSelectImmediately = true
        windowRefreshTask?.cancel()
        uiRenderingTask?.cancel()
    }
}

class KeybindHelper {
    private enum ModifierDoubleTapAction {
        case openPersistentSwitcher(SwitcherInvocationMode)
        case switchToLastFocusedWindow(SwitcherInvocationMode)
    }

    private struct ModifierDoubleTapState {
        var pressedKeyCodes: Set<UInt16> = []
        var completedFirstTapKeyCodes: Set<UInt16> = []
        var firstPressTimestampByKeyCode: [UInt16: CGEventTimestamp] = [:]

        mutating func resetSequence() {
            completedFirstTapKeyCodes.removeAll()
            firstPressTimestampByKeyCode.removeAll()
        }
    }

    private let previewCoordinator: SharedPreviewWindowCoordinator
    private let windowSwitchingCoordinator = WindowSwitchingCoordinator()

    private var isSwitcherModifierKeyPressed = false
    private var isBackwardModifierPressed = false
    private var hasProcessedModifierRelease = false
    private var preventSwitcherHideOnRelease = false

    private var menuBarWindowSwitcherMouseDownTimestamp: CGEventTimestamp?
    private var heldKeyRepeatTask: Task<Void, Never>?
    private var modifierDoubleTapState = ModifierDoubleTapState()
    private var pressedModifierKeyCodes: Set<UInt16> = []

    /// Track the invocation mode for alternate keybinds
    private var currentInvocationMode: SwitcherInvocationMode = .allWindows

    // Track Command key state to detect key-up fallback for lingering previews
    private var isCommandKeyCurrentlyDown = false
    private var lastCmdTabObservedActive = false
    private var cmdTabActionPerformed = false

    /// Set on event tap thread when switcher keybind fires, so other keyDown handlers
    /// can detect the switcher is active without reading MainActor-only state.
    private var switcherSessionActive = false {
        didSet {
            previewCoordinator.setActivePreviewShortcutKeybind(
                switcherSessionActive ? activeSessionKeybind : nil
            )
        }
    }

    private var activeSessionKeybind = Defaults[.UserKeybind] {
        didSet {
            guard switcherSessionActive else { return }
            previewCoordinator.setActivePreviewShortcutKeybind(activeSessionKeybind)
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var monitorTimer: Timer?
    private var unmanagedEventTapUserInfo: Unmanaged<KeybindHelperUserInfo>?

    init(previewCoordinator: SharedPreviewWindowCoordinator) {
        self.previewCoordinator = previewCoordinator
        setupEventTap()
        startMonitoring()
    }

    func reset() {
        cleanup()
        resetState()
        setupEventTap()
        startMonitoring()
    }

    func recover() {
        reset()
        switcherSessionActive = false
        hasProcessedModifierRelease = true
        isCommandKeyCurrentlyDown = false
        lastCmdTabObservedActive = false
        cmdTabActionPerformed = false
        Task { @MainActor in
            if self.windowSwitchingCoordinator.isActive(previewCoordinator: self.previewCoordinator) {
                self.windowSwitchingCoordinator.cancelSwitching(previewCoordinator: self.previewCoordinator)
                self.previewCoordinator.hideWindow()
            }
        }
    }

    func toggleWindowSwitcherFromMenuBar(mouseDownTimestamp: CGEventTimestamp? = nil) {
        if let mouseDownTimestamp {
            menuBarWindowSwitcherMouseDownTimestamp = mouseDownTimestamp
        }
        Task { @MainActor [weak self] in
            await self?.togglePersistentWindowSwitcher(mode: .allWindows)
        }
    }

    @MainActor
    private func togglePersistentWindowSwitcher(mode: SwitcherInvocationMode) async {
        guard Defaults[.enableWindowSwitcher] else { return }

        let coordinator = previewCoordinator.windowSwitcherCoordinator
        if coordinator.isKeybindSessionActive {
            if currentInvocationMode == mode {
                switcherSessionActive = false
                windowSwitchingCoordinator.cancelSwitching(previewCoordinator: previewCoordinator)
                previewCoordinator.hideWindow()
                return
            }

            currentInvocationMode = mode
            switcherSessionActive = false
            isSwitcherModifierKeyPressed = false
            isBackwardModifierPressed = false
            hasProcessedModifierRelease = true
            preventSwitcherHideOnRelease = Defaults[.enableWindowSwitcherSearch]
            _ = await windowSwitchingCoordinator.switchScope(
                previewCoordinator: previewCoordinator,
                mode: mode,
                launchSourceOverride: .persistent
            )
            return
        }

        currentInvocationMode = mode
        isSwitcherModifierKeyPressed = false
        isBackwardModifierPressed = false
        hasProcessedModifierRelease = true
        preventSwitcherHideOnRelease = Defaults[.enableWindowSwitcherSearch]
        switcherSessionActive = false

        await windowSwitchingCoordinator.openPersistent(
            previewCoordinator: previewCoordinator,
            mode: mode
        )
    }

    @MainActor
    func dismissPreviewsForSpaceChange() {
        switcherSessionActive = false
        cancelHeldKeyRepeatTask()
        windowSwitchingCoordinator.cancelSwitching(previewCoordinator: previewCoordinator)
        preventSwitcherHideOnRelease = false
        hasProcessedModifierRelease = true
        previewCoordinator.hideWindow()
    }

    private func cleanup() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        heldKeyRepeatTask?.cancel()
        heldKeyRepeatTask = nil
        removeEventTap()
    }

    /// Cancels any running held-key repeat task to prevent main thread blocking
    func cancelHeldKeyRepeatTask() {
        heldKeyRepeatTask?.cancel()
        heldKeyRepeatTask = nil
    }

    private func resetState() {
        isSwitcherModifierKeyPressed = false
        isBackwardModifierPressed = false
        preventSwitcherHideOnRelease = false
        currentInvocationMode = .allWindows
        modifierDoubleTapState = ModifierDoubleTapState()
        pressedModifierKeyCodes.removeAll()
        cancelHeldKeyRepeatTask()
    }

    private func startMonitoring() {
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            self?.checkEventTapStatus()
        }
    }

    private func checkEventTapStatus() {
        guard let eventTap, CGEvent.tapIsEnabled(tap: eventTap) else {
            reset()
            return
        }
    }

    private static let eventCallback: CGEventTapCallBack = { proxy, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        return Unmanaged<KeybindHelperUserInfo>.fromOpaque(refcon).takeUnretainedValue().instance.handleEvent(proxy: proxy, type: type, event: event)
    }

    private func setupEventTap() {
        guard eventTap == nil else { return }

        let eventMask = (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue)

        let userInfo = KeybindHelperUserInfo(instance: self)
        let retainedUserInfo = Unmanaged.passRetained(userInfo)

        guard let newEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: KeybindHelper.eventCallback,
            userInfo: retainedUserInfo.toOpaque()
        ) else {
            retainedUserInfo.release()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                print("Retrying KeybindHelper event tap setup...")
                self?.setupEventTap()
            }
            return
        }

        unmanagedEventTapUserInfo = retainedUserInfo
        eventTap = newEventTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newEventTap, 0)

        if let runLoopSource {
            EventTapThread.shared.add(runLoopSource)
            CGEvent.tapEnable(tap: newEventTap, enable: true)
        }
    }

    private func removeEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            if let runLoopSource {
                EventTapThread.shared.remove(runLoopSource)
            }
            CFMachPortInvalidate(eventTap)
        }
        unmanagedEventTapUserInfo?.release()
        unmanagedEventTapUserInfo = nil
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if let passthrough = reEnableIfNeeded(tap: eventTap, type: type, event: event) {
            return passthrough
        }

        switch type {
        case .flagsChanged:
            updatePressedModifierKeyCodes(event: event)
            if let action = handleModifierDoubleTap(event: event) {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch action {
                    case let .openPersistentSwitcher(mode):
                        await togglePersistentWindowSwitcher(mode: mode)
                    case let .switchToLastFocusedWindow(mode):
                        switchToLastFocusedWindow(mode: mode)
                    }
                }
            }
            let keyBoardShortcutSaved = sessionKeybind()
            let (currentSwitcherModifierIsPressed, currentBackwardState) = updateModifierStatesFromFlags(event: event, keyBoardShortcutSaved: keyBoardShortcutSaved)

            // Track Command up/down explicitly for Cmd+Tab fallback behavior
            let cmdNowDown = event.flags.contains(.maskCommand)
            if isCommandKeyCurrentlyDown, !cmdNowDown {
                DispatchQueue.main.async { DockObserver.activeInstance?.teardownCmdTabObserver() }

                if Defaults[.enableCmdTabEnhancements], lastCmdTabObservedActive {
                    let actionAlreadyHandled = cmdTabActionPerformed
                    let wasVisible = previewCoordinator.tapSnapshot.isVisible
                    Task { @MainActor in
                        if actionAlreadyHandled {
                            self.previewCoordinator.hideWindow()
                        } else if wasVisible, self.previewCoordinator.windowSwitcherCoordinator.currIndex >= 0 {
                            self.previewCoordinator.selectAndBringToFrontCurrentWindow()
                        } else {
                            self.previewCoordinator.hideWindow()
                        }
                        self.windowSwitchingCoordinator.cancelSwitching(previewCoordinator: self.previewCoordinator)
                    }
                }
                lastCmdTabObservedActive = false
                cmdTabActionPerformed = false
            }
            isCommandKeyCurrentlyDown = cmdNowDown

            var effectiveSwitcherModifierIsPressed = currentSwitcherModifierIsPressed
            if switcherSessionActive {
                let requiredModifiersHeld = modifierFlagsMatch(keyBoardShortcutSaved, flags: event.flags)
                if requiredModifiersHeld {
                    effectiveSwitcherModifierIsPressed = true
                } else {
                    switcherSessionActive = false
                }
            }

            let shouldTakeOverActiveCmdTab = cmdTabKeybinds().contains {
                modifierFlagsMatch($0, flags: event.flags)
            }
            Task { @MainActor [weak self] in
                self?.handleModifierEvent(
                    currentSwitcherModifierIsPressed: effectiveSwitcherModifierIsPressed,
                    currentBackwardState: currentBackwardState,
                    shouldTakeOverActiveCmdTab: shouldTakeOverActiveCmdTab
                )
            }

        case .keyDown:
            modifierDoubleTapState.resetSequence()
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let tapSnapshot = previewCoordinator.tapSnapshot
            let shouldRouteCmdTabToWindowSwitcher = isCmdTabWindowSwitcherKeybind(keyCode: keyCode, flags: flags)

            if let routing = previewCoordinator.contextMenuShortcutRoutingSnapshot(),
               let action = routing.actionsByKeyCode[UInt16(keyCode)],
               WindowSwitcherShortcutResolver.normalizedModifiers(Int(flags.rawValue)) ==
               WindowSwitcherShortcutResolver.normalizedModifiers(routing.keybind.modifierFlags)
            {
                guard modifierSideMatches(routing.keybind) else { return nil }
                guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return nil }
                Task { @MainActor in
                    PreviewContextMenuController.shared.performShortcut(action, token: routing.token)
                }
                return nil
            }

            if let spaceNumber = numberedSpaceShortcut(event: event),
               tapSnapshot.isVisible
            {
                Task { @MainActor [weak self] in
                    self?.handleNumberedSpaceShortcut(spaceNumber)
                }
                return nil
            }

            // Consume bare spacebar for a visible media preview so it doesn't also reach the focused app and double-toggle playback.
            if keyCode == Int64(kVK_Space),
               event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
               !flags.hasSuperfluousModifiers(),
               MediaKeyboardShortcutCoordinator.shared.handleSpaceKeyDown()
            {
                return nil
            }

            let backwardKeyCode = Defaults[.switcherBackwardKeyCode]
            if Self.eventFlagForKeyCode(backwardKeyCode) == nil,
               keyCode == Int64(backwardKeyCode),
               tapSnapshot.isVisible
            {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    handleModifierEvent(
                        currentSwitcherModifierIsPressed: isSwitcherModifierKeyPressed,
                        currentBackwardState: true
                    )
                }
                return nil
            }

            // Detect Cmd+Tab press to start on-demand polling for the switcher
            if Defaults[.enableCmdTabEnhancements],
               keyCode == Int64(kVK_Tab),
               flags.contains(.maskCommand)
            {
                if !shouldRouteCmdTabToWindowSwitcher {
                    DispatchQueue.main.async { DockObserver.activeInstance?.startCmdTabPolling() }
                }
            }

            // If system Cmd+Tab switcher is active, optionally handle arrows when enhancements are enabled
            if DockObserver.isCmdTabSwitcherActive, shouldRouteCmdTabToWindowSwitcher {
                DispatchQueue.main.async { DockObserver.activeInstance?.teardownCmdTabObserver() }
                lastCmdTabObservedActive = false
                cmdTabActionPerformed = false
            } else if DockObserver.isCmdTabSwitcherActive {
                lastCmdTabObservedActive = true
                if Defaults[.enableCmdTabEnhancements],
                   tapSnapshot.isVisible
                {
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                    let hasSelection = tapSnapshot.hasSelection
                    let flags = event.flags
                    switch keyCode {
                    case Int64(kVK_Escape):
                        Task { @MainActor in
                            self.previewCoordinator.hideWindow()
                        }
                        // Pass Escape through so the Dock can dismiss the system switcher too
                        return Unmanaged.passUnretained(event)
                    case Int64(kVK_LeftArrow), Int64(kVK_RightArrow), Int64(kVK_UpArrow), Int64(kVK_DownArrow):
                        if hasSelection {
                            let direction: ArrowDirection = switch keyCode {
                            case Int64(kVK_LeftArrow): .left
                            case Int64(kVK_RightArrow): .right
                            case Int64(kVK_UpArrow): .up
                            default: .down
                            }
                            Task { @MainActor in
                                self.previewCoordinator.navigateWithArrowKey(direction: direction)
                            }
                            // Consume arrows only while a DockDoor preview is focused.
                            return nil
                        } else {
                            // Preserve native Cmd+Tab arrow behavior before entering previews.
                            return Unmanaged.passUnretained(event)
                        }
                    case Int64(kVK_ANSI_H), Int64(kVK_ANSI_L):
                        if Defaults[.enableVimMotions], hasSelection {
                            let dir: ArrowDirection = keyCode == Int64(kVK_ANSI_H) ? .left : .right
                            Task { @MainActor in
                                self.previewCoordinator.navigateWithArrowKey(direction: dir)
                            }
                            return nil
                        } else {
                            return Unmanaged.passUnretained(event)
                        }
                    case Int64(kVK_ANSI_J):
                        if Defaults[.enableVimMotions], hasSelection {
                            Task { @MainActor in
                                self.previewCoordinator.windowSwitcherCoordinator.setIndex(to: -1, source: .keyboard)
                            }
                            return nil
                        } else {
                            return Unmanaged.passUnretained(event)
                        }
                    default:
                        // Allow activation via customizable Cmd+key (when not yet focused) and
                        // Command-based actions when a preview is focused
                        if flags.contains(.maskCommand) {
                            // Backward cycle key (default: `)
                            if hasSelection, keyCode == Int64(Defaults[.cmdTabBackwardCycleKey]) {
                                Task { @MainActor in
                                    let currentIndex = self.previewCoordinator.windowSwitcherCoordinator.currIndex
                                    let windowCount = self.previewCoordinator.windowSwitcherCoordinator.windows.count
                                    let newIndex = currentIndex > 0 ? currentIndex - 1 : windowCount - 1
                                    self.previewCoordinator.windowSwitcherCoordinator.setIndex(to: newIndex, source: .keyboard)
                                }
                                return nil
                            }

                            // Forward cycle key (default: A)
                            if keyCode == Int64(Defaults[.cmdTabCycleKey]) {
                                Task { @MainActor in
                                    let currentIndex = self.previewCoordinator.windowSwitcherCoordinator.currIndex
                                    let windowCount = self.previewCoordinator.windowSwitcherCoordinator.windows.count
                                    let isShift = flags.contains(.maskShift)

                                    if !hasSelection {
                                        // First activation: select first preview
                                        self.previewCoordinator.windowSwitcherCoordinator.setIndex(to: 0, source: .keyboard)
                                        Defaults[.hasSeenCmdTabFocusHint] = true
                                    } else if isShift {
                                        // Cmd+Shift+A: cycle backward
                                        let newIndex = currentIndex > 0 ? currentIndex - 1 : windowCount - 1
                                        self.previewCoordinator.windowSwitcherCoordinator.setIndex(to: newIndex, source: .keyboard)
                                    } else {
                                        // Cmd+A: cycle forward
                                        let newIndex = (currentIndex + 1) % windowCount
                                        self.previewCoordinator.windowSwitcherCoordinator.setIndex(to: newIndex, source: .keyboard)
                                    }
                                }
                                return nil
                            }
                        }

                        if flags.contains(.maskCommand),
                           let action = getActionForPreviewShortcut(keyCode: keyCode)
                        {
                            let supportsHighlightedAppAction = action == .close || action == .quit
                            let highlightedApps = hasSelection ? [] : DockObserver.activeInstance?.selectedCmdTabApplications() ?? []

                            if hasSelection || (supportsHighlightedAppAction && !highlightedApps.isEmpty) {
                                cmdTabActionPerformed = true
                                Task { @MainActor in
                                    if hasSelection {
                                        self.previewCoordinator.performActionOnCurrentWindow(
                                            action: action,
                                            preservePreviews: true
                                        )
                                    } else {
                                        self.previewCoordinator.performActionOnCmdTabHighlightedApps(
                                            action: action,
                                            apps: highlightedApps,
                                            preservePreviews: true
                                        )
                                    }
                                }
                                return nil
                            }
                        }
                    }
                }
                // Not enhancing or not in our cmdTab context — let the system handle it.
                return Unmanaged.passUnretained(event)
            }
            let (shouldConsume, actionTask) = determineActionForKeyDown(event: event)
            if let task = actionTask {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    heldKeyRepeatTask?.cancel()
                    heldKeyRepeatTask = Task { @MainActor in
                        await task()
                    }
                }
            }
            if shouldConsume { return nil }

        case .leftMouseDown:
            let isCmdTabActive = DockObserver.isCmdTabSwitcherActive

            let snapshot = previewCoordinator.tapSnapshot
            let isWindowSwitcherActive = snapshot.isWindowSwitcherActive
            if snapshot.isVisible, isWindowSwitcherActive || isCmdTabActive {
                let clickLocation = NSEvent.mouseLocation
                let interactiveWindowFrame = snapshot.frame.insetBy(
                    dx: HoverContainerPadding.container,
                    dy: HoverContainerPadding.container
                )
                let isInSearchWindow = snapshot.searchFrame?.contains(clickLocation) ?? false
                if interactiveWindowFrame.contains(clickLocation) || isInSearchWindow {
                    let flags = event.flags
                    if flags.contains(.maskControl) {
                        var newFlags = flags
                        newFlags.remove(.maskControl)
                        event.flags = newFlags
                    }
                } else {
                    let clickTimestamp = event.timestamp
                    let waitsForMenuBarToggle = Defaults[.openWindowSwitcherFromMenuBarIcon] &&
                        Defaults[.menuBarIconWindowSwitcherClick] == .leftClick
                    let dismissalDelay = waitsForMenuBarToggle ? 0.05 : 0
                    DispatchQueue.main.asyncAfter(deadline: .now() + dismissalDelay) {
                        if waitsForMenuBarToggle,
                           self.menuBarWindowSwitcherMouseDownTimestamp == clickTimestamp
                        {
                            self.menuBarWindowSwitcherMouseDownTimestamp = nil
                            return
                        }
                        self.switcherSessionActive = false
                        if isWindowSwitcherActive {
                            self.windowSwitchingCoordinator.cancelSwitching(previewCoordinator: self.previewCoordinator)
                            self.preventSwitcherHideOnRelease = false
                            self.hasProcessedModifierRelease = true
                        }
                        if isCmdTabActive {
                            DockObserver.activeInstance?.teardownCmdTabObserver()
                        }
                        self.previewCoordinator.hideWindow()
                    }
                }
            }

        case .keyUp:
            let backwardKeyCode = Defaults[.switcherBackwardKeyCode]
            if Self.eventFlagForKeyCode(backwardKeyCode) == nil,
               event.getIntegerValueField(.keyboardEventKeycode) == Int64(backwardKeyCode)
            {
                Task { @MainActor [weak self] in
                    self?.isBackwardModifierPressed = false
                    self?.cancelHeldKeyRepeatTask()
                }
            }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private static func eventFlagForKeyCode(_ keyCode: UInt16) -> CGEventFlags? {
        switch Int(keyCode) {
        case kVK_Shift, kVK_RightShift: .maskShift
        case kVK_Control, kVK_RightControl: .maskControl
        case kVK_Option, kVK_RightOption: .maskAlternate
        case kVK_Command, kVK_RightCommand: .maskCommand
        default: nil
        }
    }

    private func alternateShortcuts() -> [ResolvedAlternateSwitcherShortcut] {
        WindowSwitcherShortcutResolver.resolvedAlternateShortcuts(
            Defaults[.alternateSwitcherShortcuts],
            mainKeybind: Defaults[.UserKeybind],
            previewShortcuts: Defaults[.cmdShortcuts]
        )
    }

    private func persistentShortcuts() -> [ResolvedPersistentSwitcherShortcut] {
        WindowSwitcherShortcutResolver.resolvedPersistentShortcuts(
            Defaults[.persistentSwitcherShortcuts],
            mainKeybind: Defaults[.UserKeybind],
            alternateShortcuts: Defaults[.alternateSwitcherShortcuts],
            previewShortcuts: Defaults[.cmdShortcuts]
        )
    }

    private func lastFocusedShortcuts() -> [ResolvedPersistentSwitcherShortcut] {
        WindowSwitcherShortcutResolver.resolvedLastFocusedShortcuts(
            Defaults[.lastFocusedWindowShortcuts],
            mainKeybind: Defaults[.UserKeybind],
            alternateShortcuts: Defaults[.alternateSwitcherShortcuts],
            persistentShortcuts: Defaults[.persistentSwitcherShortcuts],
            previewShortcuts: Defaults[.cmdShortcuts]
        )
    }

    private func handleModifierDoubleTap(event: CGEvent) -> ModifierDoubleTapAction? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let shortcuts = persistentShortcuts().filter { $0.doubleTapKey != nil }.map {
            ($0, ModifierDoubleTapAction.openPersistentSwitcher($0.mode))
        } + lastFocusedShortcuts().filter { $0.doubleTapKey != nil }.map {
            ($0, ModifierDoubleTapAction.switchToLastFocusedWindow($0.mode))
        }
        guard !shortcuts.isEmpty,
              let matchingShortcut = shortcuts.first(where: { shortcut, _ in
                  guard let modifier = shortcut.doubleTapKey,
                        let side = shortcut.doubleTapSide
                  else { return false }
                  let keyCodes = modifier.keyCodes
                  return switch side {
                  case .either: keyCode == keyCodes.left || keyCode == keyCodes.right
                  case .left: keyCode == keyCodes.left
                  case .right: keyCode == keyCodes.right
                  }
              })
        else {
            modifierDoubleTapState.resetSequence()
            return nil
        }

        if !modifierDoubleTapState.firstPressTimestampByKeyCode.isEmpty,
           modifierDoubleTapState.firstPressTimestampByKeyCode[keyCode] == nil
        {
            modifierDoubleTapState.resetSequence()
        }

        if modifierDoubleTapState.pressedKeyCodes.contains(keyCode) {
            modifierDoubleTapState.pressedKeyCodes.remove(keyCode)
            if let firstPress = modifierDoubleTapState.firstPressTimestampByKeyCode[keyCode] {
                if isWithinModifierDoubleTapInterval(event.timestamp, after: firstPress) {
                    modifierDoubleTapState.completedFirstTapKeyCodes.insert(keyCode)
                } else {
                    modifierDoubleTapState.resetSequence()
                }
            }
            return nil
        }

        if !modifierDoubleTapState.pressedKeyCodes.isEmpty {
            modifierDoubleTapState.resetSequence()
            modifierDoubleTapState.pressedKeyCodes.insert(keyCode)
            return nil
        }

        modifierDoubleTapState.pressedKeyCodes.insert(keyCode)
        if modifierDoubleTapState.completedFirstTapKeyCodes.contains(keyCode),
           let firstPress = modifierDoubleTapState.firstPressTimestampByKeyCode[keyCode]
        {
            let isWithinInterval = isWithinModifierDoubleTapInterval(event.timestamp, after: firstPress)
            modifierDoubleTapState.resetSequence()
            if isWithinInterval {
                return matchingShortcut.1
            }
        }

        modifierDoubleTapState.firstPressTimestampByKeyCode[keyCode] = event.timestamp
        return nil
    }

    private func isWithinModifierDoubleTapInterval(
        _ timestamp: CGEventTimestamp,
        after firstPressTimestamp: CGEventTimestamp
    ) -> Bool {
        guard timestamp >= firstPressTimestamp else { return false }
        let elapsed = Double(timestamp - firstPressTimestamp) / 1_000_000_000
        return elapsed <= NSEvent.doubleClickInterval
    }

    @MainActor
    private func switchToLastFocusedWindow(mode: SwitcherInvocationMode) {
        let windows = windowSwitchingCoordinator.eligibleRealWindows(mode: mode)
            .filter { !$0.app.isTerminated }

        guard windows.count >= 2 else {
            NSSound.beep()
            return
        }
        let target = windows[1]

        switcherSessionActive = false
        windowSwitchingCoordinator.cancelSwitching(previewCoordinator: previewCoordinator)
        previewCoordinator.hideWindow()

        var targetWindow = target
        let activated: Bool = if targetWindow.isMinimized {
            targetWindow.toggleMinimize() == false
        } else if targetWindow.isEffectivelyHiddenForUI {
            targetWindow.toggleHidden() == false
        } else {
            targetWindow.bringToFront()
        }

        if !activated {
            NSSound.beep()
        }
    }

    private func sessionKeybind() -> UserKeyBind {
        switcherSessionActive ? activeSessionKeybind : Defaults[.UserKeybind]
    }

    private func previewShortcutKeybind() -> UserKeyBind {
        WindowSwitcherShortcutResolver.dependentShortcutKeybind(sessionKeybind())
    }

    private func effectivePreviewShortcutKeybind() -> UserKeyBind {
        if DockObserver.isCmdTabSwitcherActive {
            return UserKeyBind(
                keyCode: UInt16(kVK_Tab),
                modifierFlags: Int(CGEventFlags.maskCommand.rawValue),
                modifierSide: .either
            )
        }
        return previewShortcutKeybind()
    }

    private func beginSwitcherSession(with keybind: UserKeyBind) {
        activeSessionKeybind = keybind
        switcherSessionActive = true
    }

    private func isCmdTabWindowSwitcherKeybind(keyCode: Int64, flags: CGEventFlags) -> Bool {
        guard keyCode == Int64(kVK_Tab), flags.contains(.maskCommand) else { return false }
        return cmdTabKeybinds().contains { modifierFlagsMatch($0, flags: flags) }
    }

    private func cmdTabKeybinds() -> [UserKeyBind] {
        guard Defaults[.enableWindowSwitcher] else { return [] }
        let keybinds = [Defaults[.UserKeybind]] + alternateShortcuts().map(\.keybind)
        return keybinds.filter {
            $0.keyCode == UInt16(kVK_Tab) && ($0.modifierFlags & Int(CGEventFlags.maskCommand.rawValue)) != 0
        }
    }

    private func modifierFlagsMatch(_ keybind: UserKeyBind, flags: CGEventFlags) -> Bool {
        let saved = keybind.modifierFlags
        let wantsShift = (saved & Int(CGEventFlags.maskShift.rawValue)) != 0
        let wantsAlt = (saved & Int(CGEventFlags.maskAlternate.rawValue)) != 0
        let wantsCtrl = (saved & Int(CGEventFlags.maskControl.rawValue)) != 0
        let wantsCmd = (saved & Int(CGEventFlags.maskCommand.rawValue)) != 0
        let backwardKeyCode = Defaults[.switcherBackwardKeyCode]

        return modifierFlagMatches(.maskShift, required: wantsShift, flags: flags, backwardKeyCode: backwardKeyCode) &&
            modifierFlagMatches(.maskAlternate, required: wantsAlt, flags: flags, backwardKeyCode: backwardKeyCode) &&
            modifierFlagMatches(.maskControl, required: wantsCtrl, flags: flags, backwardKeyCode: backwardKeyCode) &&
            modifierFlagMatches(.maskCommand, required: wantsCmd, flags: flags, backwardKeyCode: backwardKeyCode) &&
            modifierSideMatches(keybind)
    }

    private func modifierFlagMatches(
        _ flag: CGEventFlags,
        required: Bool,
        flags: CGEventFlags,
        backwardKeyCode: UInt16
    ) -> Bool {
        if required { return flags.contains(flag) }
        guard Self.eventFlagForKeyCode(backwardKeyCode) == flag,
              let keyCodes = Self.modifierKeyCodes(for: Int(flag.rawValue))
        else { return !flags.contains(flag) }

        let familyKeyCodes = Set([UInt16(keyCodes.left), UInt16(keyCodes.right)])
        let pressedFamilyKeyCodes = pressedModifierKeyCodes.intersection(familyKeyCodes)
        return pressedFamilyKeyCodes.isEmpty ? !flags.contains(flag) : pressedFamilyKeyCodes == Set([backwardKeyCode])
    }

    private func modifierSideMatches(_ keybind: UserKeyBind) -> Bool {
        guard keybind.modifierSide != .either,
              let keyCodes = Self.modifierKeyCodes(for: keybind.modifierFlags)
        else { return true }

        let keyCode = UInt16(keybind.modifierSide == .left ? keyCodes.left : keyCodes.right)
        return pressedModifierKeyCodes.contains(keyCode)
    }

    private func updatePressedModifierKeyCodes(event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard let flag = Self.eventFlagForKeyCode(keyCode) else { return }

        if pressedModifierKeyCodes.contains(keyCode) {
            pressedModifierKeyCodes.remove(keyCode)
        } else if event.flags.contains(flag) {
            pressedModifierKeyCodes.insert(keyCode)
        }

        if !event.flags.contains(flag), let keyCodes = Self.modifierKeyCodes(for: Int(flag.rawValue)) {
            pressedModifierKeyCodes.remove(UInt16(keyCodes.left))
            pressedModifierKeyCodes.remove(UInt16(keyCodes.right))
        }
    }

    private static func modifierKeyCodes(for modifierFlags: Int) -> (left: CGKeyCode, right: CGKeyCode)? {
        let normalized = WindowSwitcherShortcutResolver.normalizedModifiers(modifierFlags)
        switch UInt64(normalized) {
        case CGEventFlags.maskShift.rawValue:
            return (CGKeyCode(kVK_Shift), CGKeyCode(kVK_RightShift))
        case CGEventFlags.maskControl.rawValue:
            return (CGKeyCode(kVK_Control), CGKeyCode(kVK_RightControl))
        case CGEventFlags.maskAlternate.rawValue:
            return (CGKeyCode(kVK_Option), CGKeyCode(kVK_RightOption))
        case CGEventFlags.maskCommand.rawValue:
            return (CGKeyCode(kVK_Command), CGKeyCode(kVK_RightCommand))
        default:
            return nil
        }
    }

    private func updateModifierStatesFromFlags(event: CGEvent, keyBoardShortcutSaved: UserKeyBind) -> (currentSwitcherModifierIsPressed: Bool, currentBackwardState: Bool) {
        let flags = event.flags
        let backwardFlag = Self.eventFlagForKeyCode(Defaults[.switcherBackwardKeyCode])
        let currentSwitcherModifierIsPressed = modifierFlagsMatch(keyBoardShortcutSaved, flags: flags)

        let backwardKeyCode = Defaults[.switcherBackwardKeyCode]
        let currentBackwardState: Bool = if let flag = backwardFlag,
                                            canUseBackwardModifier(flag, with: keyBoardShortcutSaved)
        {
            pressedModifierKeyCodes.contains(backwardKeyCode)
        } else {
            isBackwardModifierPressed
        }

        return (currentSwitcherModifierIsPressed, currentBackwardState)
    }

    private func backwardModifierIsPressed(flags: CGEventFlags, initializer: UserKeyBind) -> Bool {
        let backwardKeyCode = Defaults[.switcherBackwardKeyCode]
        guard let backwardFlag = Self.eventFlagForKeyCode(backwardKeyCode) else {
            return isBackwardModifierPressed
        }
        guard canUseBackwardModifier(backwardFlag, with: initializer) else { return false }
        return flags.contains(backwardFlag) && pressedModifierKeyCodes.contains(backwardKeyCode)
    }

    private func canUseBackwardModifier(_ flag: CGEventFlags, with initializer: UserKeyBind) -> Bool {
        guard (initializer.modifierFlags & Int(flag.rawValue)) != 0 else { return true }
        guard initializer.modifierSide != .either,
              let keyCodes = Self.modifierKeyCodes(for: Int(flag.rawValue))
        else { return false }

        let initializerKeyCode = UInt16(initializer.modifierSide == .left ? keyCodes.left : keyCodes.right)
        return Defaults[.switcherBackwardKeyCode] != initializerKeyCode
    }

    private func activeBackwardModifierFlag() -> CGEventFlags? {
        let backwardKeyCode = Defaults[.switcherBackwardKeyCode]
        guard let flag = Self.eventFlagForKeyCode(backwardKeyCode),
              let keyCodes = Self.modifierKeyCodes(for: Int(flag.rawValue))
        else { return nil }

        let familyKeyCodes = Set([UInt16(keyCodes.left), UInt16(keyCodes.right)])
        return pressedModifierKeyCodes.intersection(familyKeyCodes) == Set([backwardKeyCode]) ? flag : nil
    }

    private func backwardNavigationIgnoredFlags() -> CGEventFlags {
        var flags: CGEventFlags = [.maskAlphaShift, .maskNumericPad]
        if let backwardFlag = activeBackwardModifierFlag() {
            flags.insert(backwardFlag)
        }
        return flags
    }

    @MainActor
    private func handleModifierEvent(
        currentSwitcherModifierIsPressed: Bool,
        currentBackwardState: Bool,
        shouldTakeOverActiveCmdTab: Bool = false
    ) {
        // If system Cmd+Tab switcher is active, do not engage DockDoor's own switcher logic
        if DockObserver.isCmdTabSwitcherActive {
            guard shouldTakeOverActiveCmdTab else { return }
            DockObserver.activeInstance?.teardownCmdTabObserver()
        }
        let oldSwitcherModifierState = isSwitcherModifierKeyPressed
        let oldBackwardState = isBackwardModifierPressed

        isSwitcherModifierKeyPressed = currentSwitcherModifierIsPressed
        isBackwardModifierPressed = currentBackwardState

        if preventSwitcherHideOnRelease, !previewCoordinator.isVisible {
            preventSwitcherHideOnRelease = false
        }

        if !oldSwitcherModifierState && currentSwitcherModifierIsPressed {
            hasProcessedModifierRelease = false
        }

        let isWindowSwitcherActive = previewCoordinator.windowSwitcherCoordinator.windowSwitcherActive
        let shouldSkipBackwardWithoutTab = Defaults[.requireShiftTabToGoBack] && isWindowSwitcherActive
        let isDockLikePreviewActive = previewCoordinator.isVisible && !isWindowSwitcherActive
        let canNavigateBackward = isDockLikePreviewActive || currentSwitcherModifierIsPressed || Defaults[.preventSwitcherHide]

        if !oldBackwardState, currentBackwardState,
           previewCoordinator.isVisible,
           canNavigateBackward
        {
            if !shouldSkipBackwardWithoutTab {
                Task { @MainActor in
                    if isWindowSwitcherActive {
                        await self.windowSwitchingCoordinator.handleWindowSwitching(
                            previewCoordinator: self.previewCoordinator,
                            isModifierPressed: currentSwitcherModifierIsPressed,
                            isBackwardPressed: true,
                            mode: self.currentInvocationMode
                        )
                    } else {
                        self.previewCoordinator.navigateWithArrowKey(direction: .left)
                    }
                }

                if isWindowSwitcherActive || isDockLikePreviewActive {
                    heldKeyRepeatTask?.cancel()
                    heldKeyRepeatTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 400_000_000)

                        while !Task.isCancelled,
                              self.isBackwardModifierPressed,
                              self.previewCoordinator.isVisible
                        {
                            if self.previewCoordinator.windowSwitcherCoordinator.windowSwitcherActive {
                                await self.windowSwitchingCoordinator.handleWindowSwitching(
                                    previewCoordinator: self.previewCoordinator,
                                    isModifierPressed: self.isSwitcherModifierKeyPressed,
                                    isBackwardPressed: true,
                                    mode: self.currentInvocationMode
                                )
                            } else {
                                self.previewCoordinator.navigateWithArrowKey(direction: .left)
                            }
                            try? await Task.sleep(nanoseconds: 80_000_000)
                        }
                    }
                }
            }
        }

        if oldBackwardState, !currentBackwardState {
            cancelHeldKeyRepeatTask()
        }

        if windowSwitchingCoordinator.dismissesOnModifierRelease,
           !Defaults[.preventSwitcherHide],
           !preventSwitcherHideOnRelease,
           !previewCoordinator.isSearchWindowFocused
        {
            if oldSwitcherModifierState, !isSwitcherModifierKeyPressed, !hasProcessedModifierRelease {
                hasProcessedModifierRelease = true
                preventSwitcherHideOnRelease = false

                windowSwitchingCoordinator.cancelPendingRender()

                Task { @MainActor in
                    if self.previewCoordinator.isVisible, self.previewCoordinator.windowSwitcherCoordinator.windowSwitcherActive {
                        self.previewCoordinator.selectAndBringToFrontCurrentWindow()
                        self.windowSwitchingCoordinator.cancelSwitching(previewCoordinator: self.previewCoordinator)
                    } else if let selectedWindow = self.windowSwitchingCoordinator.selectCurrentWindow(previewCoordinator: self.previewCoordinator) {
                        selectedWindow.bringToFront()
                        selectedWindow.warpMouseToCenterIfNeeded()
                        self.previewCoordinator.hideWindow()
                    }
                }
            }
        }
    }

    private func determineActionForKeyDown(event: CGEvent) -> (shouldConsume: Bool, actionTask: (() async -> Void)?) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let keyBoardShortcutSaved: UserKeyBind = Defaults[.UserKeybind]
        let alternateShortcuts = alternateShortcuts()
        let persistentShortcuts = persistentShortcuts()
        let lastFocusedShortcuts = lastFocusedShortcuts()
        let snapshot = previewCoordinator.tapSnapshot
        let previewIsCurrentlyVisible = snapshot.isVisible || switcherSessionActive

        let isDesiredModifierPressedNow = modifierFlagsMatch(keyBoardShortcutSaved, flags: flags)
        let isExactSwitcherShortcutPressed = keyCode == keyBoardShortcutSaved.keyCode &&
            (isDesiredModifierPressedNow || keyBoardShortcutSaved.modifierFlags == 0)
        let matchingAlternateShortcut = alternateShortcuts.first {
            keyCode == $0.keybind.keyCode && modifierFlagsMatch($0.keybind, flags: flags)
        }
        let isAlternateShortcutPressed = matchingAlternateShortcut != nil
        let normalizedEventModifiers = WindowSwitcherShortcutResolver.normalizedModifiers(Int(flags.rawValue))
        let matchingPersistentShortcut = event.getIntegerValueField(.keyboardEventAutorepeat) == 0 ? persistentShortcuts.first {
            $0.doubleTapKey == nil &&
                keyCode == Int64($0.keyCode) &&
                normalizedEventModifiers == $0.modifierFlags
        } : nil
        let matchingLastFocusedShortcut = event.getIntegerValueField(.keyboardEventAutorepeat) == 0 ? lastFocusedShortcuts.first {
            $0.doubleTapKey == nil &&
                keyCode == Int64($0.keyCode) &&
                normalizedEventModifiers == $0.modifierFlags
        } : nil

        if previewIsCurrentlyVisible || snapshot.fullPreviewFrame != nil,
           keyCode == kVK_Escape,
           !isExactSwitcherShortcutPressed,
           !isAlternateShortcutPressed,
           matchingPersistentShortcut == nil,
           matchingLastFocusedShortcut == nil
        {
            switcherSessionActive = false
            return (true, { @MainActor in
                self.windowSwitchingCoordinator.cancelSwitching(previewCoordinator: self.previewCoordinator)
                self.previewCoordinator.hideWindow()
                self.preventSwitcherHideOnRelease = false
                self.hasProcessedModifierRelease = true
            })
        }

        if isExactSwitcherShortcutPressed {
            guard Defaults[.enableWindowSwitcher] else { return (false, nil) }
            if WindowUtil.shouldIgnoreKeybindForFrontmostApp() { return (false, nil) }
            let previousSessionKeybind = activeSessionKeybind
            let previousSessionWasActive = switcherSessionActive
            beginSwitcherSession(with: keyBoardShortcutSaved)
            return (true, {
                await self.handleKeybindActivation(
                    mode: .allWindows,
                    isModifierPressed: true,
                    isBackwardPressed: self.backwardModifierIsPressed(flags: flags, initializer: keyBoardShortcutSaved),
                    rollbackKeybind: previousSessionKeybind,
                    rollbackSessionActive: previousSessionWasActive
                )
            })
        }

        if let matchingAlternateShortcut {
            guard Defaults[.enableWindowSwitcher] else { return (false, nil) }
            if WindowUtil.shouldIgnoreKeybindForFrontmostApp() { return (false, nil) }
            let previousSessionKeybind = activeSessionKeybind
            let previousSessionWasActive = switcherSessionActive
            beginSwitcherSession(with: matchingAlternateShortcut.keybind)
            return (true, {
                await self.handleKeybindActivation(
                    mode: matchingAlternateShortcut.mode,
                    isModifierPressed: true,
                    isBackwardPressed: self.backwardModifierIsPressed(flags: flags, initializer: matchingAlternateShortcut.keybind),
                    rollbackKeybind: previousSessionKeybind,
                    rollbackSessionActive: previousSessionWasActive
                )
            })
        }

        if let matchingPersistentShortcut {
            guard Defaults[.enableWindowSwitcher] else { return (false, nil) }
            if WindowUtil.shouldIgnoreKeybindForFrontmostApp() { return (false, nil) }
            return (true, {
                await self.togglePersistentWindowSwitcher(mode: matchingPersistentShortcut.mode)
            })
        }

        if let matchingLastFocusedShortcut {
            return (true, { @MainActor in
                self.switchToLastFocusedWindow(mode: matchingLastFocusedShortcut.mode)
            })
        }

        if previewIsCurrentlyVisible {
            if modifierFlagsMatch(previewShortcutKeybind(), flags: flags),
               snapshot.hasSelection
            {
                if let action = getActionForPreviewShortcut(keyCode: keyCode) {
                    preventSwitcherHideOnRelease = true
                    return (true, { @MainActor in
                        let didClosePreviews = self.previewCoordinator.performActionOnCurrentWindow(action: action)
                        if didClosePreviews || self.previewCoordinator.windowSwitcherCoordinator.windows.isEmpty {
                            self.switcherSessionActive = false
                            self.windowSwitchingCoordinator.cancelSwitching(previewCoordinator: self.previewCoordinator)
                            self.preventSwitcherHideOnRelease = false
                            self.hasProcessedModifierRelease = true
                        } else {
                            self.preventSwitcherHideOnRelease = false

                            if self.windowSwitchingCoordinator.dismissesOnModifierRelease,
                               !Defaults[.preventSwitcherHide],
                               !self.isSwitcherModifierKeyPressed
                            {
                                self.switcherSessionActive = false
                                self.windowSwitchingCoordinator.cancelSwitching(previewCoordinator: self.previewCoordinator)
                                self.hasProcessedModifierRelease = true
                                self.previewCoordinator.hideWindow()
                            }
                        }
                    })
                }
            }
        }

        if previewIsCurrentlyVisible {
            if keyCode == kVK_Tab {
                let isBackwardPressed = isBackwardModifierPressed

                return (true, { @MainActor in
                    if self.previewCoordinator.windowSwitcherCoordinator.windowSwitcherActive {
                        if !self.previewCoordinator.windowSwitcherCoordinator.hasActiveSearch {
                            let shouldGoBackward = isBackwardPressed &&
                                (!Defaults[.requireShiftTabToGoBack] ||
                                    self.isSwitcherModifierKeyPressed ||
                                    Defaults[.preventSwitcherHide])

                            await self.windowSwitchingCoordinator.handleWindowSwitching(
                                previewCoordinator: self.previewCoordinator,
                                isModifierPressed: self.isSwitcherModifierKeyPressed,
                                isBackwardPressed: shouldGoBackward,
                                mode: self.currentInvocationMode
                            )
                        }
                    } else {
                        self.previewCoordinator.navigateWithArrowKey(direction: isBackwardPressed ? .left : .right)
                    }
                })
            }

            switch keyCode {
            case Int64(kVK_LeftArrow), Int64(kVK_RightArrow), Int64(kVK_UpArrow), Int64(kVK_DownArrow):
                if Defaults[.passArrowsThroughToSystem], flags.contains(.maskControl) {
                    return (false, nil)
                }
                let dir: ArrowDirection = switch keyCode {
                case Int64(kVK_LeftArrow):
                    .left
                case Int64(kVK_RightArrow):
                    .right
                case Int64(kVK_UpArrow):
                    .up
                default:
                    .down
                }
                return (true, { @MainActor in
                    self.previewCoordinator.navigateWithArrowKey(direction: dir)
                })
            case Int64(kVK_ANSI_H), Int64(kVK_ANSI_J), Int64(kVK_ANSI_K), Int64(kVK_ANSI_L):
                if Defaults[.enableVimMotions],
                   !snapshot.isSearchFocused,
                   allowsVimMotionNavigation(flags: flags, keyBoardShortcutSaved: sessionKeybind())
                {
                    let dir: ArrowDirection = switch keyCode {
                    case Int64(kVK_ANSI_H): .left
                    case Int64(kVK_ANSI_L): .right
                    case Int64(kVK_ANSI_K): .up
                    default: .down
                    }
                    return (true, { @MainActor in
                        self.previewCoordinator.navigateWithArrowKey(direction: dir)
                    })
                }
            case Int64(Defaults[.windowSwitcherSelectionKeyCode]), Int64(kVK_Return), Int64(kVK_ANSI_KeypadEnter):
                if snapshot.hasSelection {
                    return (true, makeEnterSelectionTask())
                }
            default:
                break
            }
        }

        if previewIsCurrentlyVisible,
           snapshot.isWindowSwitcherActive,
           Defaults[.enableWindowSwitcherSearch],
           keyCode == Int64(Defaults[.searchTriggerKey]),
           !snapshot.isSearchFocused
        {
            return (true, { @MainActor in
                self.previewCoordinator.focusSearchWindow()
                self.preventSwitcherHideOnRelease = true
            })
        }
        if previewIsCurrentlyVisible,
           snapshot.isWindowSwitcherActive,
           Defaults[.enableWindowSwitcherSearch],
           !snapshot.isSearchFocused
        {
            if keyCode == Int64(kVK_Delete) {
                return (true, { @MainActor in
                    var query = self.previewCoordinator.windowSwitcherCoordinator.searchQuery
                    if !query.isEmpty {
                        query.removeLast()
                        self.previewCoordinator.windowSwitcherCoordinator.searchQuery = query
                        SharedPreviewWindowCoordinator.activeInstance?.updateSearchWindow(with: query)

                        if query.isEmpty {
                            self.preventSwitcherHideOnRelease = false
                        }
                    }
                })
            }

            if !flags.contains(.maskCommand) {
                var length = 0
                var buffer = [UniChar](repeating: 0, count: 4)
                event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
                let characters = String(utf16CodeUnits: buffer, count: length)
                let filteredChars = characters.filter { char in
                    char.isLetter || char.isNumber || char.isWhitespace ||
                        ".,!?-_()[]{}@#$%^&*+=|\\:;\"'<>/~`".contains(char)
                }
                if !filteredChars.isEmpty {
                    return (true, { @MainActor in
                        self.previewCoordinator.windowSwitcherCoordinator.searchQuery.append(contentsOf: filteredChars)
                        let newQuery = self.previewCoordinator.windowSwitcherCoordinator.searchQuery
                        SharedPreviewWindowCoordinator.activeInstance?.updateSearchWindow(with: newQuery)

                        if !newQuery.isEmpty {
                            self.preventSwitcherHideOnRelease = true
                        }
                    })
                }
            }
        }

        if previewIsCurrentlyVisible,
           snapshot.isWindowSwitcherActive,
           !isSwitcherModifierKeyPressed,
           !flags.hasSuperfluousModifiers(ignoring: backwardNavigationIgnoredFlags())
        {
            let matchingAlternateMode = alternateShortcuts.first(where: { Int64($0.keybind.keyCode) == keyCode })?.mode
            let retriggerMode: SwitcherInvocationMode? = if keyCode == keyBoardShortcutSaved.keyCode, keyBoardShortcutSaved.modifierFlags != 0 {
                .allWindows
            } else if let matchingAlternateMode {
                matchingAlternateMode
            } else {
                nil
            }
            if let retriggerMode {
                if WindowUtil.shouldIgnoreKeybindForFrontmostApp() { return (false, nil) }
                return (true, { await self.handleKeybindActivation(mode: retriggerMode) })
            }
        }

        return (false, nil)
    }

    private func allowsVimMotionNavigation(flags: CGEventFlags, keyBoardShortcutSaved: UserKeyBind) -> Bool {
        var allowedModifiers: CGEventFlags = [.maskAlphaShift, .maskNumericPad]
        let saved = keyBoardShortcutSaved.modifierFlags

        if (saved & Int(CGEventFlags.maskShift.rawValue)) != 0 {
            allowedModifiers.insert(.maskShift)
        }
        if (saved & Int(CGEventFlags.maskAlternate.rawValue)) != 0 {
            allowedModifiers.insert(.maskAlternate)
        }
        if (saved & Int(CGEventFlags.maskControl.rawValue)) != 0 {
            allowedModifiers.insert(.maskControl)
        }
        if (saved & Int(CGEventFlags.maskCommand.rawValue)) != 0 {
            allowedModifiers.insert(.maskCommand)
        }
        if let backwardFlag = activeBackwardModifierFlag() {
            allowedModifiers.insert(backwardFlag)
        }

        let activeModifiers = flags.intersection([.maskControl, .maskCommand, .maskAlternate, .maskShift])
        return activeModifiers.subtracting(allowedModifiers).isEmpty
    }

    private func makeEnterSelectionTask() -> (() async -> Void) {
        { @MainActor in
            self.preventSwitcherHideOnRelease = false

            if self.previewCoordinator.isVisible, self.previewCoordinator.windowSwitcherCoordinator.windowSwitcherActive {
                self.previewCoordinator.selectAndBringToFrontCurrentWindow()
                self.windowSwitchingCoordinator.cancelSwitching(previewCoordinator: self.previewCoordinator)
                return
            }

            if let selectedWindow = self.windowSwitchingCoordinator.selectCurrentWindow(previewCoordinator: self.previewCoordinator) {
                selectedWindow.bringToFront()
                selectedWindow.warpMouseToCenterIfNeeded()
                self.previewCoordinator.hideWindow()
            } else {
                self.previewCoordinator.selectAndBringToFrontCurrentWindow()
            }
        }
    }

    @MainActor
    private func handleKeybindActivation(
        mode: SwitcherInvocationMode = .allWindows,
        isModifierPressed: Bool? = nil,
        isBackwardPressed: Bool? = nil,
        rollbackKeybind: UserKeyBind? = nil,
        rollbackSessionActive: Bool? = nil
    ) async {
        guard Defaults[.enableWindowSwitcher] else { return }
        hasProcessedModifierRelease = false
        let previousMode = currentInvocationMode
        let shouldSwitchScope = windowSwitchingCoordinator.isActive(previewCoordinator: previewCoordinator) && previousMode != mode
        currentInvocationMode = mode
        let modifierPressedForActivation = isModifierPressed ?? isSwitcherModifierKeyPressed
        let backwardPressedForActivation = isBackwardPressed ?? isBackwardModifierPressed
        if modifierPressedForActivation {
            isSwitcherModifierKeyPressed = true
        }
        isBackwardModifierPressed = backwardPressedForActivation
        if Defaults[.focusSearchOnWindowSwitcherOpen], Defaults[.enableWindowSwitcherSearch] {
            preventSwitcherHideOnRelease = true
        }
        if shouldSwitchScope {
            let switched = await windowSwitchingCoordinator.switchScope(
                previewCoordinator: previewCoordinator,
                mode: mode
            )
            if !switched {
                currentInvocationMode = previousMode
                if let rollbackKeybind {
                    activeSessionKeybind = rollbackKeybind
                }
                if let rollbackSessionActive {
                    switcherSessionActive = rollbackSessionActive
                }
            }
            return
        }

        let activated = await windowSwitchingCoordinator.handleWindowSwitching(
            previewCoordinator: previewCoordinator,
            isModifierPressed: modifierPressedForActivation,
            isBackwardPressed: backwardPressedForActivation,
            mode: mode
        )
        if !activated {
            currentInvocationMode = previousMode
            preventSwitcherHideOnRelease = false
            if let rollbackKeybind {
                activeSessionKeybind = rollbackKeybind
            }
            if let rollbackSessionActive {
                switcherSessionActive = rollbackSessionActive
            }
        }
    }

    private func numberedSpaceShortcut(event: CGEvent) -> Int? {
        guard Defaults[.enableSpacesShortcuts],
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              let spaceNumber = WindowSwitcherShortcutResolver.spaceNumber(
                  forPhysicalKeyCode: event.getIntegerValueField(.keyboardEventKeycode)
              )
        else { return nil }

        let mainKeybind = WindowSwitcherShortcutResolver.dependentShortcutKeybind(Defaults[.UserKeybind])
        let eventModifiers = WindowSwitcherShortcutResolver.normalizedModifiers(Int(event.flags.rawValue))
        let mainModifiers = WindowSwitcherShortcutResolver.normalizedModifiers(mainKeybind.modifierFlags)
        guard mainModifiers != 0,
              eventModifiers == mainModifiers,
              modifierSideMatches(mainKeybind)
        else {
            return nil
        }
        return spaceNumber
    }

    @MainActor
    private func handleNumberedSpaceShortcut(_ spaceNumber: Int) {
        WindowUtil.cancelPendingManagedSpaceSwitch()

        let displays = WindowSpaces.managedDisplays()
        guard let destination = WindowSpaces.destination(forSpaceNumber: spaceNumber, in: displays) else {
            NSSound.beep()
            return
        }

        let coordinator = previewCoordinator.windowSwitcherCoordinator
        if let selectedWindow = coordinator.getCurrentWindow() {
            guard destination.space.kind == .desktop else {
                NSSound.beep()
                return
            }
            preventSwitcherHideOnRelease = true
            if DockObserver.isCmdTabSwitcherActive {
                cmdTabActionPerformed = true
            }
            WindowUtil.performConfirmedSpaceMove(
                selectedWindow,
                to: destination,
                dismissPreviews: { [weak self] in
                    self?.dismissPreviewsForSpaceChange()
                },
                completion: { [weak self] success in
                    if !success {
                        NSSound.beep()
                    }
                    self?.finishNumberedWindowMove()
                }
            )
            return
        }

        guard coordinator.windowSwitcherActive, !DockObserver.isCmdTabSwitcherActive else {
            NSSound.beep()
            return
        }

        guard destination.space.kind == .desktop || destination.space.kind == .fullscreen else {
            NSSound.beep()
            return
        }

        let isCurrentDestination = displays.contains { display in
            display.identifier == destination.display.identifier && display.currentSpaceID == destination.space.id
        }
        guard !isCurrentDestination else {
            NSSound.beep()
            return
        }

        dismissPreviewsForSpaceChange()
        WindowUtil.switchToManagedSpace(destination) { success in
            if !success {
                NSSound.beep()
            }
        }
    }

    @MainActor
    private func finishNumberedWindowMove() {
        preventSwitcherHideOnRelease = false
        guard windowSwitchingCoordinator.dismissesOnModifierRelease,
              !Defaults[.preventSwitcherHide],
              !isSwitcherModifierKeyPressed,
              previewCoordinator.isVisible
        else { return }

        switcherSessionActive = false
        windowSwitchingCoordinator.cancelSwitching(previewCoordinator: previewCoordinator)
        hasProcessedModifierRelease = true
        previewCoordinator.hideWindow()
    }

    /// Returns the first active preview action matching the configured key.
    private func getActionForPreviewShortcut(keyCode: Int64) -> WindowAction? {
        let mainKeybind = Defaults[.UserKeybind]
        let previewKeybind = effectivePreviewShortcutKeybind()
        return WindowSwitcherShortcutResolver.resolvedPreviewShortcuts(
            Defaults[.cmdShortcuts],
            previewKeybind: previewKeybind,
            mainKeybind: mainKeybind
        ).first { Int64($0.keyCode) == keyCode }?.action
    }
}

/// Re-enables a disabled event tap and returns a passthrough result, or nil if the event type is not tap-disabled.
func reEnableIfNeeded(tap: CFMachPort?, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else { return nil }
    if let tap {
        CGEvent.tapEnable(tap: tap, enable: true)
    }
    return Unmanaged.passUnretained(event)
}

extension CGEventFlags {
    func hasSuperfluousModifiers(ignoring: CGEventFlags = []) -> Bool {
        let significantModifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
        let relevantToCheck = significantModifiers.subtracting(ignoring)
        return !intersection(relevantToCheck).isEmpty
    }
}
