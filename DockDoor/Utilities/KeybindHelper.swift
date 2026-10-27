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

enum WindowSwitcherLaunchSource: Equatable {
    case keyboard
    case persistent
    case trackpad

    func allowsTrackpadTakeover(enabled: Bool, initializerHeld: Bool) -> Bool {
        enabled && (self != .keyboard || !initializerHeld)
    }

    func takingKeyboardOwnership(isSwitcherInvocation: Bool) -> Self {
        if isSwitcherInvocation { return .keyboard }
        return self == .trackpad ? .persistent : self
    }

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
        case .keyboard, .trackpad: Defaults[.instantWindowSwitcher]
        case .persistent: true
        }
    }

    var focusesSearchOnOpen: Bool {
        switch self {
        case .keyboard, .trackpad: Defaults[.focusSearchOnWindowSwitcherOpen]
        case .persistent: true
        }
    }
}

enum TrackpadSwipeReleasePolicy {
    static func shouldSelect(
        tookOverKeepOpenSession: Bool,
        keepOpen: Bool,
        focusesSearchOnOpen: Bool,
        searchEnabled: Bool,
        searchFocused: Bool
    ) -> Bool {
        !searchFocused && (tookOverKeepOpenSession || (!keepOpen && !(focusesSearchOnOpen && searchEnabled)))
    }
}

struct SwitcherFilterCandidates {
    struct Entry: Hashable {
        let identity: PreviewWindowIdentity
        let axElement: AXUIElement

        init(_ window: WindowInfo) {
            identity = PreviewWindowIdentity(window)
            axElement = window.axElement
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.identity == rhs.identity && lhs.axElement == rhs.axElement
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(identity)
        }
    }

    private(set) var invocation: [Entry]?
    let spaces: [Entry]
    private var windowlessApps: [NSRunningApplication] = []
    let groupByApp: Bool
    private var filteredOrders: [Set<PreviewWindowIdentity>: [Entry]] = [:]

    init(spaces: [WindowInfo], groupByApp: Bool) {
        self.spaces = spaces.map(Entry.init)
        self.groupByApp = groupByApp
    }

    mutating func prepareInvocation(_ windows: [WindowInfo]) {
        invocation = windows.map(Entry.init)
        windowlessApps = windows.filter(\.isWindowlessApp).map(\.app)
    }

    mutating func resolve(members: Set<PreviewWindowIdentity>?, windows: [WindowInfo]) -> [WindowInfo] {
        let current = Dictionary(windows.map { (Entry($0), $0) }, uniquingKeysWith: { first, _ in first })
        if let members {
            if filteredOrders[members] == nil {
                let eligible = spaces.filter { members.contains($0.identity) }.compactMap { current[$0] }
                filteredOrders[members] = (groupByApp ? WindowUtil.groupWindowsByApp(eligible) : eligible).map(Entry.init)
            }
            return filteredOrders[members, default: []].compactMap { current[$0] }
        }
        let placeholders = Dictionary(windowlessApps.filter { !$0.isTerminated }.map {
            (PreviewWindowIdentity(pid: $0.processIdentifier, windowID: 0), $0)
        }, uniquingKeysWith: { first, _ in first })
        return (invocation ?? []).compactMap { id in
            current[id] ?? placeholders[id.identity].map { WindowInfo.windowlessEntry(for: $0) }
        }
    }
}

private class WindowSwitchingCoordinator {
    private struct FilterPreparationKey: Equatable {
        let revision: UInt
        let sortOrder: WindowPreviewSortOrder
        let groupedApps: [String]
        let appFilters: [String]
        let policy: [Bool]
        let frontmostPID: pid_t?
        let monitor: String?
        let runningApps: Set<pid_t>
    }

    private var isProcessingSwitcher = false
    private var uiRenderingTask: Task<Void, Never>?
    private var windowRefreshTask: Task<Void, Never>?
    private(set) var currentSessionId = UUID()
    private var activeLaunchSource: WindowSwitcherLaunchSource?
    /// When true, initialization should complete but immediately select the window instead of showing UI
    private var shouldSelectImmediately = false
    private var trackpadSessionId: UUID?
    private(set) var trackpadTookOverKeepOpenSession = false

    var trackpadOpenedCurrentSession: Bool {
        trackpadSessionId == currentSessionId && activeLaunchSource == .trackpad
    }

    func relinquishTrackpadSession() {
        trackpadSessionId = nil
        trackpadTookOverKeepOpenSession = false
    }

    func takeKeyboardOwnership(isSwitcherInvocation: Bool = false) {
        guard let activeLaunchSource else { return }
        self.activeLaunchSource = activeLaunchSource.takingKeyboardOwnership(isSwitcherInvocation: isSwitcherInvocation)
        relinquishTrackpadSession()
    }

    private static var lastUpdateAllWindowsTime: Date?
    private static let updateAllWindowsThrottleInterval: TimeInterval = 5.0

    @MainActor
    @discardableResult
    func handleWindowSwitching(
        previewCoordinator: SharedPreviewWindowCoordinator,
        isModifierPressed: Bool,
        isBackwardPressed: Bool,
        mode: SwitcherInvocationMode = .allWindows,
        launchSource: WindowSwitcherLaunchSource = .keyboard,
        initializerHeld: Bool = false,
        spaceNavigation: PreviewStateCoordinator.SpaceNavigationRequest? = nil
    ) async -> Bool {
        guard !isProcessingSwitcher else { return false }
        isProcessingSwitcher = true
        defer { isProcessingSwitcher = false }

        let coordinator = previewCoordinator.windowSwitcherCoordinator

        if coordinator.isKeybindSessionActive {
            if launchSource == .trackpad, isModifierPressed,
               activeLaunchSource?.allowsTrackpadTakeover(
                   enabled: Defaults[.selectWindowOnPersistentSwitcherSwipe],
                   initializerHeld: initializerHeld
               ) == true
            {
                coordinator.clearCheckedWindows(resetOwnership: true)
                activeLaunchSource = .trackpad
                trackpadSessionId = currentSessionId
                trackpadTookOverKeepOpenSession = true
                previewCoordinator.unfocusSearchWindow()
            }
            // Navigation cancels swipe release without creating a held-modifier session.
            if launchSource == .keyboard { takeKeyboardOwnership() }
            coordinator.hasMovedSinceOpen = false
            coordinator.initialHoverLocation = nil

            if let spaceNavigation {
                navigateSpaces(previewCoordinator: previewCoordinator, request: spaceNavigation)
            } else if isBackwardPressed {
                coordinator.cycleBackward()
            } else {
                coordinator.cycleForward()
            }
            return true
        } else if isModifierPressed {
            if launchSource == .trackpad { coordinator.clearCheckedWindows(resetOwnership: true) }
            return await initializeWindowSwitching(
                previewCoordinator: previewCoordinator,
                mode: mode,
                launchSource: launchSource,
                spaceNavigation: spaceNavigation
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
        relinquishTrackpadSession()
        let sessionId = currentSessionId
        windowRefreshTask?.cancel()
        uiRenderingTask?.cancel()
        let needsRender = !previewCoordinator.isVisible || !coordinator.windowSwitcherActive
        let launchSource = launchSourceOverride ?? activeLaunchSource ?? .keyboard
        activeLaunchSource = launchSource

        installSpaceFilter(previewCoordinator: previewCoordinator, mode: mode, screen: getTargetScreenForSwitcher(), dockPosition: DockUtils.getDockPosition())
        let windows = buildSwitcherWindows(mode: mode, spaceMembers: coordinator.activeSpaceMembers)

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
    func navigateSpaces(previewCoordinator: SharedPreviewWindowCoordinator, request: PreviewStateCoordinator.SpaceNavigationRequest) {
        let coordinator = previewCoordinator.windowSwitcherCoordinator
        if previewCoordinator.isVisible, coordinator.windowSwitcherActive {
            coordinator.pendingSpaceNavigation = nil
            previewCoordinator.navigateSpaces(request)
        } else {
            coordinator.pendingSpaceNavigation = (request, getTargetScreenForSwitcher())
        }
    }

    @MainActor
    func openPersistent(
        previewCoordinator: SharedPreviewWindowCoordinator,
        mode: SwitcherInvocationMode,
        spacesFocused: Bool = false
    ) async {
        guard !isProcessingSwitcher,
              !previewCoordinator.windowSwitcherCoordinator.isKeybindSessionActive
        else { return }

        isProcessingSwitcher = true
        defer { isProcessingSwitcher = false }
        _ = await initializeWindowSwitching(
            previewCoordinator: previewCoordinator,
            mode: mode,
            launchSource: .persistent,
            spaceNavigation: spacesFocused ? .current : nil
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
        launchSource: WindowSwitcherLaunchSource,
        spaceNavigation: PreviewStateCoordinator.SpaceNavigationRequest? = nil
    ) async -> Bool {
        guard previewCoordinator.canPresentPreviews else { return false }
        previewCoordinator.cancelPendingShow()
        if previewCoordinator.isVisible, !previewCoordinator.windowSwitcherCoordinator.windowSwitcherActive {
            previewCoordinator.hideWindow()
        }
        HangDiagnostics.record("switcher initialization started mode=\(mode.rawValue)")
        activeLaunchSource = nil
        // Reset the immediate-select flag at start of initialization
        shouldSelectImmediately = false
        windowRefreshTask?.cancel()

        currentSessionId = UUID()
        trackpadTookOverKeepOpenSession = false
        trackpadSessionId = launchSource == .trackpad ? currentSessionId : nil
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
        coordinator.pendingSpaceNavigation = spaceNavigation.map { ($0, targetScreen) }
        installSpaceFilter(previewCoordinator: previewCoordinator, mode: mode, screen: targetScreen, dockPosition: dockPosition)

        // If modifier was released during initialization, immediately select and exit
        if launchSource == .keyboard, shouldSelectImmediately {
            if previewCoordinator.activatePendingSpaceNavigation() { return true }
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
        forceRecencyOrder: Bool = false,
        spaceMembers: Set<PreviewWindowIdentity>? = nil,
        sourceWindows: [WindowInfo]? = nil,
        groupByApp: Bool = true
    ) -> [WindowInfo] {
        var windows: [WindowInfo]
        if spaceMembers != nil {
            // The shared Space model has already resolved native-tab representatives.
            windows = sourceWindows ?? WindowUtil.getAllWindowsIgnoringSwitcherFilters()
            if !Defaults[.includeHiddenWindowsInSwitcher] {
                windows = windows.filter { !$0.isEffectivelyHiddenForUI && !$0.isMinimized }
            }
        } else if mode == .allWindows {
            windows = sourceWindows.map { WindowUtil.switcherWindows(from: $0) } ?? WindowUtil.getAllWindowsOfAllApps()
        } else {
            windows = WindowUtil.collapseNativeTabsIfNeeded(sourceWindows ?? WindowUtil.getAllWindowsIgnoringSwitcherFilters())
            if !Defaults[.includeHiddenWindowsInSwitcher] {
                windows = windows.filter { !$0.isEffectivelyHiddenForUI && !$0.isMinimized }
            }
        }
        let windowsForWindowlessDetection = windows

        let filterBySpace = (mode == .currentSpaceOnly || mode == .currentMonitorCurrentSpace || mode == .activeAppCurrentSpace)
            || (mode == .allWindows && Defaults[.showWindowsFromCurrentSpaceOnlyInSwitcher])
        if filterBySpace, spaceMembers == nil {
            windows = WindowUtil.filterWindowsByCurrentSpace(windows)
        }

        let filterByMonitor = mode == .currentMonitorOnly || mode == .currentMonitorCurrentSpace
            || (mode == .allWindows && Defaults[.showWindowsFromCurrentMonitorOnlyInSwitcher])
        if filterByMonitor, spaceMembers == nil {
            windows = WindowUtil.filterWindowsByCurrentMonitor(windows)
        }

        let filterByApp = isActiveAppMode(mode)
        if filterByApp {
            windows = WindowUtil.getWindowsForFrontmostApp(from: windows)
        }

        if !Defaults[.includeHiddenWindowsInSwitcher] {
            windows = windows.filter { !$0.isHidden && !$0.isMinimized }
        }

        if let spaceMembers { windows = windows.filter { !$0.isWindowlessApp && spaceMembers.contains(PreviewWindowIdentity($0)) } }

        windows = forceRecencyOrder
            ? WindowUtil.sortWindowsForSwitcherByRecency(windows)
            : WindowUtil.sortWindowsForSwitcher(windows)

        if !filterByApp, groupByApp {
            windows = WindowUtil.groupWindowsByApp(windows)
        }

        let excludesWindowlessApps = (Defaults[.excludeWindowlessAppsFromCurrentMonitorSwitcherScopes]
            && (mode == .currentMonitorOnly || mode == .currentMonitorCurrentSpace))
            || (Defaults[.excludeWindowlessAppsFromCurrentSpaceSwitcherScopes]
                && (mode == .currentSpaceOnly || mode == .currentMonitorCurrentSpace))
        if spaceMembers == nil, !filterByApp, Defaults[.showWindowlessAppsInSwitcher], !excludesWindowlessApps {
            windows.append(contentsOf: WindowUtil.getWindowlessRunningApps(existingWindows: windowsForWindowlessDetection))
        }

        return windows
    }

    @MainActor
    private func installSpaceFilter(previewCoordinator: SharedPreviewWindowCoordinator, mode: SwitcherInvocationMode, screen: NSScreen, dockPosition: DockPosition) {
        let coordinator = previewCoordinator.windowSwitcherCoordinator
        guard Defaults[.enableSpacesBar] else { coordinator.onSpaceFilterChanged = nil; return }
        let session = currentSessionId
        var preparedKey: FilterPreparationKey?
        coordinator.onSpaceFilterChanged = { [weak self, weak previewCoordinator] in
            guard let self, currentSessionId == session,
                  let previewCoordinator, previewCoordinator.isVisible, Defaults[.enableSpacesBar]
            else { return }
            let coordinator = previewCoordinator.windowSwitcherCoordinator
            guard coordinator.windowSwitcherActive else { return }
            let snapshot = WindowUtil.readSwitcherCacheSnapshot()
            let policy = [
                Defaults[.includeHiddenWindowsInSwitcher], Defaults[.limitSwitcherToFrontmostApp],
                Defaults[.showWindowsFromCurrentSpaceOnlyInSwitcher], Defaults[.showWindowsFromCurrentMonitorOnlyInSwitcher],
                Defaults[.showWindowlessAppsInSwitcher], Defaults[.excludeWindowlessAppsFromCurrentMonitorSwitcherScopes],
                Defaults[.excludeWindowlessAppsFromCurrentSpaceSwitcherScopes], Defaults[.collapseNativeTabsIntoSingleWindow],
                Defaults[.sortMinimizedToEnd],
            ]
            let usesMonitor = mode == .currentMonitorOnly || mode == .currentMonitorCurrentSpace ||
                (mode == .allWindows && Defaults[.showWindowsFromCurrentMonitorOnlyInSwitcher])
            let key = FilterPreparationKey(
                revision: snapshot.revision,
                sortOrder: Defaults[.windowSwitcherSortOrder], groupedApps: Defaults[.groupedAppsInSwitcher],
                appFilters: Defaults[.appNameFilters], policy: policy,
                frontmostPID: isActiveAppMode(mode) ? NSWorkspace.shared.frontmostApplication?.processIdentifier : nil,
                monitor: usesMonitor ? NSScreen.screenFromQuartzPoint(DockObserver.getMousePosition()).uniqueIdentifier() : nil,
                runningApps: Defaults[.showWindowlessAppsInSwitcher] ? Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier)) : []
            )
            if preparedKey != key || coordinator.preparedSpaceFilterCandidates == nil {
                let source = snapshot.windows.sorted { $0.lastAccessedTime > $1.lastAccessedTime }
                let spaces = buildSwitcherWindows(
                    mode: mode, spaceMembers: Set(source.map(PreviewWindowIdentity.init)),
                    sourceWindows: source, groupByApp: false
                )
                coordinator.preparedSpaceFilterCandidates = SwitcherFilterCandidates(spaces: spaces, groupByApp: !isActiveAppMode(mode))
                preparedKey = key
            }
            if coordinator.activeSpaceMembers == nil, coordinator.preparedSpaceFilterCandidates?.invocation == nil {
                let source = snapshot.windows.sorted { $0.lastAccessedTime > $1.lastAccessedTime }
                coordinator.preparedSpaceFilterCandidates?.prepareInvocation(buildSwitcherWindows(mode: mode, sourceWindows: source))
            }
            let windows = coordinator.preparedSpaceFilterCandidates?.resolve(members: coordinator.activeSpaceMembers, windows: snapshot.windows) ?? []
            applyRefreshedSwitcherWindows(windows, coordinator: coordinator, dockPosition: dockPosition, bestGuessMonitor: previewCoordinator.screen ?? screen)
            coordinator.onFrameRefreshNeeded?()
        }
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

                let freshWindows = buildSwitcherWindows(mode: mode, spaceMembers: coordinator.activeSpaceMembers)
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
            coordinator.updateSelectionIndex(newIndex, source: previousSelectionSource)
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

        if coordinator.pendingSpaceNavigation == nil, launchSource.focusesSearchOnOpen, Defaults[.enableWindowSwitcherSearch] {
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
        relinquishTrackpadSession()
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

    var isPersistentSession: Bool {
        activeLaunchSource == .persistent
    }

    @MainActor
    func cancelSwitching(previewCoordinator: SharedPreviewWindowCoordinator) {
        currentSessionId = UUID()
        relinquishTrackpadSession()
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

private final class PreviewActionKeyPressState {
    private let lock = NSLock()
    private var heldKeys: [Int64: UInt64] = [:]

    func consumeRepeat(keyCode: Int64, isRepeat: Bool) -> Bool {
        lock.withLock {
            if !isRepeat {
                heldKeys.removeValue(forKey: keyCode)
                return false
            }
            return heldKeys[keyCode] != nil
        }
    }

    func begin(keyCode: Int64, isRepeat: Bool, timestamp: UInt64 = 0) -> Bool {
        lock.withLock { heldKeys[keyCode] = timestamp }
        return !isRepeat
    }

    @discardableResult
    func release(keyCode: Int64) -> UInt64? {
        lock.withLock { heldKeys.removeValue(forKey: keyCode) }
    }

    func isHeld(keyCode: Int64, timestamp: UInt64) -> Bool {
        lock.withLock { heldKeys[keyCode] == timestamp }
    }

    func reset() {
        lock.withLock { heldKeys.removeAll(keepingCapacity: true) }
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

    private var heldKeyRepeatTask: Task<Void, Never>?
    private var modifierDoubleTapState = ModifierDoubleTapState()
    private var pressedModifierKeyCodes: Set<UInt16> = []
    private let actionKeyPressState = PreviewActionKeyPressState()

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
    private var trackpadSwipeTrigger: TrackpadSwipeTrigger?
    private var lastFocusedActivationTask: Task<Void, Never>?

    init(previewCoordinator: SharedPreviewWindowCoordinator) {
        self.previewCoordinator = previewCoordinator
        previewCoordinator.onSwitcherSessionDismissal = { @MainActor [weak self] in
            self?.cancelWindowSwitcherSession()
        }
        previewCoordinator.windowSwitcherCoordinator.onSelectionPinned = { [weak self] in
            self?.windowSwitchingCoordinator.takeKeyboardOwnership()
        }
        setupEventTap()
        startMonitoring()
        if Defaults[.enableWindowSwitcher], Defaults[.enableTrackpadSwitcherSwipe] {
            trackpadSwipeTrigger = TrackpadSwipeTrigger { [weak self] event in
                self?.handleTrackpadSwipe(event)
            }
        }
    }

    func reset() {
        cleanup()
        resetState()
        setupEventTap()
        startMonitoring()
        trackpadSwipeTrigger?.reset()
    }

    @MainActor
    func recover() {
        if DockObserver.canPostEvents, AXIsProcessTrusted(), let eventTap,
           CFMachPortIsValid(eventTap), runLoopSource.map(CFRunLoopSourceIsValid) == true,
           CGEvent.tapIsEnabled(tap: eventTap)
        {
            DebugLogger.log("Wake recovery", details: "keyboard tap healthy; active switcher preserved=\(windowSwitchingCoordinator.isActive(previewCoordinator: previewCoordinator))")
            return
        }
        DebugLogger.log("Wake recovery", details: "keyboard tap unavailable; rebuilding, dismiss active switcher=\(windowSwitchingCoordinator.isActive(previewCoordinator: previewCoordinator))")
        reset()
        switcherSessionActive = false
        hasProcessedModifierRelease = true
        isCommandKeyCurrentlyDown = false
        lastCmdTabObservedActive = false
        cmdTabActionPerformed = false
        if windowSwitchingCoordinator.isActive(previewCoordinator: previewCoordinator) {
            windowSwitchingCoordinator.cancelSwitching(previewCoordinator: previewCoordinator)
            previewCoordinator.hideWindow()
        }
    }

    func toggleWindowSwitcherFromMenuBar() {
        Task { @MainActor [weak self] in
            await self?.presentPersistentWindowSwitcher(mode: .allWindows)
        }
    }

    @MainActor
    func showWindowSwitcherFromAppleScript(spacesFocused: Bool = false) async {
        await presentPersistentWindowSwitcher(mode: .allWindows, togglesCurrentScope: false, spacesFocused: spacesFocused)
    }

    @MainActor
    private func presentPersistentWindowSwitcher(
        mode: SwitcherInvocationMode,
        togglesCurrentScope: Bool = true,
        spacesFocused: Bool = false
    ) async {
        guard Defaults[.enableWindowSwitcher], !spacesFocused || Defaults[.enableSpacesBar], previewCoordinator.canPresentPreviews else { return }
        lastFocusedActivationTask?.cancel()
        lastFocusedActivationTask = nil
        windowSwitchingCoordinator.relinquishTrackpadSession()

        let coordinator = previewCoordinator.windowSwitcherCoordinator
        coordinator.clearCheckedWindows(resetOwnership: true)
        if coordinator.isKeybindSessionActive {
            if currentInvocationMode == mode, togglesCurrentScope {
                switcherSessionActive = false
                windowSwitchingCoordinator.cancelSwitching(previewCoordinator: previewCoordinator)
                previewCoordinator.hideWindow()
                return
            }

            if currentInvocationMode == mode,
               windowSwitchingCoordinator.isPersistentSession
            {
                if spacesFocused { windowSwitchingCoordinator.navigateSpaces(previewCoordinator: previewCoordinator, request: .current) }
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
            if spacesFocused { windowSwitchingCoordinator.navigateSpaces(previewCoordinator: previewCoordinator, request: .current) }
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
            mode: mode,
            spacesFocused: spacesFocused
        )
    }

    @MainActor
    func dismissPreviews() {
        cancelWindowSwitcherSession()
        previewCoordinator.hideWindow()
    }

    @MainActor
    private func cancelWindowSwitcherSession() {
        switcherSessionActive = false
        cancelHeldKeyRepeatTask()
        windowSwitchingCoordinator.cancelSwitching(previewCoordinator: previewCoordinator)
        preventSwitcherHideOnRelease = false
        hasProcessedModifierRelease = true
    }

    private func cleanup() {
        lastFocusedActivationTask?.cancel()
        lastFocusedActivationTask = nil
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
        guard eventTap == nil, DockObserver.canPostEvents else { return }

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
            let userInfo = unmanagedEventTapUserInfo
            EventTapThread.shared.remove(eventTap, source: runLoopSource) { userInfo?.release() }
        }
        unmanagedEventTapUserInfo = nil
        eventTap = nil
        runLoopSource = nil
        actionKeyPressState.reset()
        if Defaults[.enableMultiWindowSelection] {
            Task { @MainActor [weak self] in self?.previewCoordinator.windowSwitcherCoordinator.endKeyboardSelectionRange() }
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if let passthrough = reEnableIfNeeded(tap: eventTap, type: type, event: event) {
            actionKeyPressState.reset()
            if Defaults[.enableMultiWindowSelection] {
                Task { @MainActor [weak self] in self?.previewCoordinator.windowSwitcherCoordinator.endKeyboardSelectionRange() }
            }
            return passthrough
        }

        // Keep consumed action keys suppressed through preview dismissal until physical release.
        var releasedActionPress: UInt64?
        if type == .keyUp {
            releasedActionPress = actionKeyPressState.release(keyCode: event.getIntegerValueField(.keyboardEventKeycode))
        } else if type == .keyDown,
                  actionKeyPressState.consumeRepeat(
                      keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                      isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                  )
        {
            return nil
        }

        if previewCoordinator.tapSnapshot.isPresentationSuspended {
            if type == .flagsChanged {
                updatePressedModifierKeyCodes(event: event)
            }
            modifierDoubleTapState = ModifierDoubleTapState()
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown || type == .keyUp || type == .flagsChanged,
           previewCoordinator.tapSnapshot.isPreviewFocusFadeMonitoring
        {
            Task { @MainActor [weak self] in
                self?.previewCoordinator.registerPreviewFocusActivity()
            }
        }

        switch type {
        case .flagsChanged:
            updatePressedModifierKeyCodes(event: event)
            if let action = handleModifierDoubleTap(event: event) {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch action {
                    case let .openPersistentSwitcher(mode):
                        await presentPersistentWindowSwitcher(mode: mode)
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
            let isModifierPress = pressedModifierKeyCodes.contains(UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
            let selectionModifiersHeld = !Defaults[.enableMultiWindowSelection] || modifierFlagsMatch(effectivePreviewShortcutKeybind(), flags: event.flags)
            let modifierTimestamp = event.timestamp
            Task { @MainActor [weak self] in
                if !selectionModifiersHeld { self?.previewCoordinator.windowSwitcherCoordinator.endKeyboardSelectionRange(releasedBefore: modifierTimestamp) }
                self?.handleModifierEvent(
                    currentSwitcherModifierIsPressed: effectiveSwitcherModifierIsPressed,
                    currentBackwardState: currentBackwardState,
                    shouldTakeOverActiveCmdTab: shouldTakeOverActiveCmdTab,
                    isModifierPress: isModifierPress
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
                guard actionKeyPressState.begin(keyCode: keyCode, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0),
                      modifierSideMatches(routing.keybind)
                else { return nil }
                Task { @MainActor in
                    self.windowSwitchingCoordinator.takeKeyboardOwnership()
                    PreviewContextMenuController.shared.performShortcut(action, token: routing.token)
                }
                return nil
            }

            if let spaceNumber = numberedSpaceShortcut(event: event),
               tapSnapshot.isVisible
            {
                guard actionKeyPressState.begin(keyCode: keyCode, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0) else { return nil }
                Task { @MainActor [weak self] in
                    self?.handleNumberedSpaceShortcut(spaceNumber)
                }
                return nil
            }

            if Defaults[.enableSpacesBar], Defaults[.enableWindowSwitcher],
               (tapSnapshot.isVisible && tapSnapshot.isWindowSwitcherActive) || Defaults[.spacesBarCycleOpensSwitcher],
               keyCode == Int64(Defaults[.spacesBarCycleKey]) || keyCode == Int64(Defaults[.spacesBarBackwardCycleKey])
            {
                let spaceCycleKeybind = tapSnapshot.isWindowSwitcherActive ? effectivePreviewShortcutKeybind() :
                    WindowSwitcherShortcutResolver.dependentShortcutKeybind(Defaults[.UserKeybind])
                let backward = keyCode != Int64(Defaults[.spacesBarCycleKey])
                if modifierFlagsMatch(spaceCycleKeybind, flags: flags),
                   WindowSwitcherShortcutResolver.spaceCycleConflict(backward: backward,
                                                                     previewKeybind: spaceCycleKeybind, mainKeybind: Defaults[.UserKeybind]) == nil
                {
                    if tapSnapshot.isVisible, tapSnapshot.isWindowSwitcherActive {
                        Task { @MainActor [weak self] in self?.previewCoordinator.cycleSpaces(backward: backward) }
                    } else {
                        guard !WindowUtil.shouldIgnoreKeybindForFrontmostApp() else { return Unmanaged.passUnretained(event) }
                        let previousKeybind = activeSessionKeybind
                        let previousActive = switcherSessionActive
                        beginSwitcherSession(with: spaceCycleKeybind)
                        Task { @MainActor [weak self] in
                            await self?.handleKeybindActivation(mode: .allWindows, isModifierPressed: true, isBackwardPressed: false,
                                                                rollbackKeybind: previousKeybind, rollbackSessionActive: previousActive,
                                                                spaceNavigation: .cycle(backward: backward))
                        }
                    }
                    return nil
                }
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
                                self.navigatePreviewSelectionArrow(direction)
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
                            let supportsHighlightedAppAction = action == .close || action == .minimize || action.isQuitAction
                            let highlightedApps = hasSelection ? [] : DockObserver.activeInstance?.selectedCmdTabApplications() ?? []
                            let canTileCheckedWindows = action == .autoTileSelectedWindows && tapSnapshot.hasCheckedWindows

                            if hasSelection || action == .selectAllWindows || canTileCheckedWindows || (supportsHighlightedAppAction && !highlightedApps.isEmpty) {
                                let pressTimestamp = event.timestamp
                                guard actionKeyPressState.begin(keyCode: keyCode, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, timestamp: pressTimestamp) else { return nil }
                                cmdTabActionPerformed = true
                                Task { @MainActor in
                                    if hasSelection || action == .selectAllWindows || canTileCheckedWindows {
                                        _ = self.performPreviewShortcut(
                                            action, keyCode: keyCode, timestamp: pressTimestamp,
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
            if snapshot.isNativeMenuTracking {
                return Unmanaged.passUnretained(event)
            }
            let isWindowSwitcherActive = snapshot.isWindowSwitcherActive
            if snapshot.isVisible, isWindowSwitcherActive || isCmdTabActive || snapshot.hasCheckedWindows {
                let clickLocation = NSEvent.mouseLocation
                if !snapshot.shouldDismissForOutsideClick(at: clickLocation) {
                    let flags = event.flags
                    if flags.contains(.maskControl), isWindowSwitcherActive || isCmdTabActive {
                        var newFlags = flags
                        newFlags.remove(.maskControl)
                        event.flags = newFlags
                    }
                } else {
                    DispatchQueue.main.async {
                        guard self.previewCoordinator.tapSnapshot.shouldDismissForOutsideClick(at: clickLocation) else { return }
                        if (NSApp.delegate as? AppDelegate)?.isWindowSwitcherMenuBarClick(at: clickLocation) == true { return }
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
            if releasedActionPress != nil, Defaults[.enableMultiWindowSelection] {
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                let timestamp = event.timestamp
                Task { @MainActor [weak self] in
                    self?.previewCoordinator.windowSwitcherCoordinator.endKeyboardSelectionRange(keyCode: code, releasedBefore: timestamp)
                }
            }
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
        lastFocusedActivationTask?.cancel()
        lastFocusedActivationTask = nil
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

        lastFocusedActivationTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }
            let targetWindow = target
            let revealed = await WindowUtil.revealWindowConfirmed(targetWindow)
            guard !Task.isCancelled else { return }
            let activated = revealed ? await targetWindow.bringToFrontConfirmed() : false
            guard !Task.isCancelled else { return }
            lastFocusedActivationTask = nil
            if activated {
                targetWindow.warpMouseToCenterIfNeeded()
            } else {
                NSSound.beep()
            }
        }
    }

    private func sessionKeybind() -> UserKeyBind {
        switcherSessionActive ? activeSessionKeybind : Defaults[.UserKeybind]
    }

    private func effectivePreviewShortcutKeybind() -> UserKeyBind {
        previewCoordinator.effectivePreviewShortcutKeybind()
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
        shouldTakeOverActiveCmdTab: Bool = false,
        isModifierPress: Bool = false
    ) {
        // If system Cmd+Tab switcher is active, do not engage DockDoor's own switcher logic
        if DockObserver.isCmdTabSwitcherActive {
            guard shouldTakeOverActiveCmdTab else { return }
            DockObserver.activeInstance?.teardownCmdTabObserver()
        }
        if isModifierPress { windowSwitchingCoordinator.takeKeyboardOwnership() }
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
                selectOnSwitcherRelease()
            }
        }
    }

    @MainActor
    private func selectOnSwitcherRelease() {
        guard !previewCoordinator.windowSwitcherCoordinator.selectionSuppressesRelease else { return }
        windowSwitchingCoordinator.cancelPendingRender()
        let sessionId = windowSwitchingCoordinator.currentSessionId

        Task { @MainActor in
            guard self.windowSwitchingCoordinator.currentSessionId == sessionId,
                  !self.previewCoordinator.windowSwitcherCoordinator.selectionSuppressesRelease
            else { return }
            if self.previewCoordinator.activatePendingSpaceNavigation() { return }
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

    @MainActor
    func handleGestureSwitcher(_ event: TrackpadSwipeEvent) {
        handleTrackpadSwipe(event, requiresSwipeSetting: false)
    }

    @MainActor
    private func handleTrackpadSwipe(_ event: TrackpadSwipeEvent, requiresSwipeSetting: Bool = true) {
        Task { @MainActor [weak self] in
            guard let self, previewCoordinator.canPresentPreviews else { return }
            let event = event.reversingSelection(if: Defaults[.reverseTrackpadSwipeSelectionDirection])
            switch event {
            case .open, .cycleForward, .cycleBackward, .openSpaces, .cycleSpaceForward, .cycleSpaceBackward:
                guard Defaults[.enableWindowSwitcher], !requiresSwipeSetting || Defaults[.enableTrackpadSwitcherSwipe] else { return }
                var openingBackward: Bool?
                if case let .openSpaces(backward) = event { openingBackward = backward }
                let opens = event == .open || openingBackward != nil
                let spaces = openingBackward != nil || event == .cycleSpaceForward || event == .cycleSpaceBackward
                let backward = openingBackward ?? (event == .cycleBackward || event == .cycleSpaceBackward)
                guard !spaces || (Defaults[.enableSpacesBar] && Defaults[.trackpadSwitcherSwipeSpaces]) else { return }
                if opens {
                    guard !WindowUtil.shouldIgnoreKeybindForFrontmostApp() else { return }
                    if !windowSwitchingCoordinator.isActive(previewCoordinator: previewCoordinator) {
                        lastFocusedActivationTask?.cancel()
                        lastFocusedActivationTask = nil
                        currentInvocationMode = .allWindows
                        switcherSessionActive = false
                    }
                }
                await windowSwitchingCoordinator.handleWindowSwitching(
                    previewCoordinator: previewCoordinator,
                    isModifierPressed: opens,
                    isBackwardPressed: backward,
                    mode: currentInvocationMode,
                    launchSource: .trackpad,
                    initializerHeld: isSwitcherModifierKeyPressed,
                    spaceNavigation: spaces ? .cycle(backward: backward) : nil
                )
            case .release:
                guard windowSwitchingCoordinator.trackpadOpenedCurrentSession else { return }
                let tookOverKeepOpenSession = windowSwitchingCoordinator.trackpadTookOverKeepOpenSession
                windowSwitchingCoordinator.relinquishTrackpadSession()
                // Typed search filters the swipe's selection; focused search explicitly keeps it open.
                guard TrackpadSwipeReleasePolicy.shouldSelect(
                    tookOverKeepOpenSession: tookOverKeepOpenSession,
                    keepOpen: Defaults[.preventSwitcherHide],
                    focusesSearchOnOpen: Defaults[.focusSearchOnWindowSwitcherOpen],
                    searchEnabled: Defaults[.enableWindowSwitcherSearch],
                    searchFocused: previewCoordinator.isSearchWindowFocused
                )
                else { return }
                selectOnSwitcherRelease()
            case .cancel:
                guard windowSwitchingCoordinator.trackpadOpenedCurrentSession else { return }
                windowSwitchingCoordinator.relinquishTrackpadSession()
                windowSwitchingCoordinator.cancelSwitching(previewCoordinator: previewCoordinator)
                previewCoordinator.hideWindow()
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
           !snapshot.isNativeMenuTracking,
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
                await self.presentPersistentWindowSwitcher(mode: matchingPersistentShortcut.mode)
            })
        }

        if let matchingLastFocusedShortcut {
            return (true, { @MainActor in
                self.switchToLastFocusedWindow(mode: matchingLastFocusedShortcut.mode)
            })
        }

        if previewIsCurrentlyVisible {
            if modifierFlagsMatch(effectivePreviewShortcutKeybind(), flags: flags) {
                if let action = getActionForPreviewShortcut(keyCode: keyCode),
                   snapshot.hasSelection || action == .selectAllWindows || (action == .autoTileSelectedWindows && snapshot.hasCheckedWindows)
                {
                    let pressTimestamp = event.timestamp
                    guard actionKeyPressState.begin(keyCode: keyCode, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0, timestamp: pressTimestamp) else { return (true, nil) }
                    preventSwitcherHideOnRelease = true
                    return (true, { @MainActor in
                        if ![.toggleWindowSelection, .selectAllWindows].contains(action) || Defaults[.keepWindowSwitcherOpenWhenSelected] {
                            self.windowSwitchingCoordinator.takeKeyboardOwnership()
                        }
                        let didClosePreviews = self.performPreviewShortcut(action, keyCode: keyCode, timestamp: pressTimestamp)
                        if didClosePreviews || (self.previewCoordinator.windowSwitcherCoordinator.windows.isEmpty && !self.previewCoordinator.hasVisibleSpacesBar) {
                            self.switcherSessionActive = false
                            self.windowSwitchingCoordinator.cancelSwitching(previewCoordinator: self.previewCoordinator)
                            self.preventSwitcherHideOnRelease = false
                            self.hasProcessedModifierRelease = true
                        } else {
                            self.preventSwitcherHideOnRelease = false

                            if self.windowSwitchingCoordinator.dismissesOnModifierRelease,
                               !Defaults[.preventSwitcherHide],
                               !self.previewCoordinator.windowSwitcherCoordinator.selectionSuppressesRelease,
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
                        self.previewCoordinator.windowSwitcherCoordinator.navigationTarget = .windows
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
                    self.navigatePreviewSelectionArrow(dir)
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
           WindowSwitcherShortcutResolver.searchTriggerConflict(previewKeybind: effectivePreviewShortcutKeybind(), mainKeybind: keyBoardShortcutSaved) == nil,
           WindowSwitcherShortcutResolver.normalizedModifiers(Int(flags.rawValue)) == 0 || modifierFlagsMatch(effectivePreviewShortcutKeybind(), flags: flags),
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
        rollbackSessionActive: Bool? = nil,
        spaceNavigation: PreviewStateCoordinator.SpaceNavigationRequest? = nil
    ) async {
        guard Defaults[.enableWindowSwitcher], previewCoordinator.canPresentPreviews else { return }
        lastFocusedActivationTask?.cancel()
        lastFocusedActivationTask = nil
        hasProcessedModifierRelease = false
        let previousMode = currentInvocationMode
        let isExistingSession = windowSwitchingCoordinator.isActive(previewCoordinator: previewCoordinator)
        let shouldSwitchScope = isExistingSession && previousMode != mode
        currentInvocationMode = mode
        let modifierPressedForActivation = isModifierPressed ?? isSwitcherModifierKeyPressed
        let takesOverPersistentSession = modifierPressedForActivation &&
            (windowSwitchingCoordinator.isPersistentSession || windowSwitchingCoordinator.trackpadOpenedCurrentSession)
        if !isExistingSession || shouldSwitchScope || takesOverPersistentSession ||
            (rollbackKeybind != nil && rollbackKeybind != activeSessionKeybind)
        {
            previewCoordinator.windowSwitcherCoordinator.clearCheckedWindows(resetOwnership: true)
        }
        if takesOverPersistentSession {
            previewCoordinator.unfocusSearchWindow()
            preventSwitcherHideOnRelease = false
        }
        windowSwitchingCoordinator.takeKeyboardOwnership(isSwitcherInvocation: modifierPressedForActivation)
        let backwardPressedForActivation = isBackwardPressed ?? isBackwardModifierPressed
        if modifierPressedForActivation {
            isSwitcherModifierKeyPressed = true
        }
        isBackwardModifierPressed = backwardPressedForActivation
        if spaceNavigation == nil, !isExistingSession, Defaults[.focusSearchOnWindowSwitcherOpen], Defaults[.enableWindowSwitcherSearch] {
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
            mode: mode,
            spaceNavigation: spaceNavigation
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

    @MainActor
    private func performPreviewShortcut(_ action: WindowAction, keyCode: Int64, timestamp: UInt64, preservePreviews: Bool = false) -> Bool {
        let coordinator = previewCoordinator.windowSwitcherCoordinator
        if let spaceID = previewCoordinator.highlightedSpaceID {
            coordinator.endSelectionRange()
            return previewCoordinator.performSpaceWindowAction(action, spaceID: spaceID, keyboard: true)
        }
        if action == .toggleWindowSelection, let window = coordinator.getCurrentWindow() {
            let press = actionKeyPressState.isHeld(keyCode: keyCode, timestamp: timestamp)
                ? PreviewSelectionKeyPress(keyCode: keyCode, timestamp: timestamp) : nil
            coordinator.toggleCheckedWindow(window, keyboardPress: press)
            return false
        }
        coordinator.navigationTarget = .windows
        coordinator.endSelectionRange()
        return previewCoordinator.performActionOnCurrentWindow(action: action, preservePreviews: preservePreviews)
    }

    @MainActor
    private func navigatePreviewSelectionArrow(_ direction: ArrowDirection) {
        let coordinator = previewCoordinator.windowSwitcherCoordinator
        if let press = coordinator.keyboardSelectionPress,
           !actionKeyPressState.isHeld(keyCode: press.keyCode, timestamp: press.timestamp)
        { coordinator.endKeyboardSelectionRange() }
        previewCoordinator.navigateWithArrowKey(direction: direction, extendingSelection: coordinator.keyboardSelectionPress != nil)
    }

    private func numberedSpaceShortcut(event: CGEvent) -> Int? {
        guard Defaults[.enableSpacesShortcuts],
              let spaceNumber = WindowSwitcherShortcutResolver.spaceNumber(
                  forPhysicalKeyCode: event.getIntegerValueField(.keyboardEventKeycode)
              )
        else { return nil }

        let mainKeybind = previewCoordinator.effectivePreviewShortcutKeybind(forSpaces: true)
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
        windowSwitchingCoordinator.takeKeyboardOwnership()
        WindowUtil.cancelPendingManagedSpaceSwitch()

        func unavailable() {
            let feedback = ActionFeedbackController.space(spaceNumber, window: previewCoordinator.windowSwitcherCoordinator.getCurrentWindow(), keyboard: true)
            feedback?.finishRemaining(.failed)
            NSSound.beep()
        }
        let displays = WindowSpaces.managedDisplays()
        guard let destination = WindowSpaces.destination(forSpaceNumber: spaceNumber, in: displays) else {
            unavailable()
            return
        }

        let coordinator = previewCoordinator.windowSwitcherCoordinator
        if let selectedWindow = coordinator.getCurrentWindow() {
            guard destination.space.kind == .desktop else {
                unavailable()
                return
            }
            if DockObserver.isCmdTabSwitcherActive {
                cmdTabActionPerformed = true
            }
            if previewCoordinator.performCheckedSpaceMove(selectedWindow, to: destination,
                                                          dismissPreviews: { [weak self] in self?.dismissPreviews() }, keyboard: true)
            { return }
            preventSwitcherHideOnRelease = true
            let feedback = ActionFeedbackController.space(spaceNumber, window: selectedWindow, keyboard: true)
            WindowUtil.performConfirmedSpaceMove(
                selectedWindow,
                to: destination,
                dismissPreviews: { [weak self] in
                    self?.dismissPreviews()
                },
                feedback: feedback,
                completion: { [weak self] success in
                    feedback?.finishRemaining(success ? .completed : .failed)
                    if !success {
                        NSSound.beep()
                    }
                    self?.finishNumberedWindowMove()
                }
            )
            return
        }

        guard coordinator.windowSwitcherActive, !DockObserver.isCmdTabSwitcherActive else {
            unavailable()
            return
        }

        guard destination.space.kind == .desktop || destination.space.kind == .fullscreen else {
            unavailable()
            return
        }

        let isCurrentDestination = displays.contains { display in
            display.identifier == destination.display.identifier && display.currentSpaceID == destination.space.id
        }
        guard !isCurrentDestination else {
            unavailable()
            return
        }

        let feedback = ActionFeedbackController.space(spaceNumber, keyboard: true)
        dismissPreviews()
        WindowUtil.switchToManagedSpace(destination, feedback: feedback) { success in
            feedback?.finishRemaining(success ? .completed : .failed)
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
              !previewCoordinator.windowSwitcherCoordinator.selectionSuppressesRelease,
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
        let mainKeybind = previewCoordinator.effectivePreviewShortcutKeybind(forSpaces: true)
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
