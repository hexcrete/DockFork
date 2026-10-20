import Carbon
import Defaults
import Sparkle
import SwiftUI

enum ArrowDirection {
    case left, right, up, down
}

enum EmbeddedContentType: Equatable {
    case media(bundleIdentifier: String)
    case calendar(bundleIdentifier: String)
    case none
}

enum PreviewFocusFadePolicy {
    static func canFade(enabled: Bool, hoverAction: PreviewHoverAction, containerVisible: Bool,
                        fullPreviewVisible: Bool, hasSelection: Bool, menuTracking: Bool) -> Bool
    {
        enabled && hoverAction == .previewFullSize && containerVisible && fullPreviewVisible && hasSelection && !menuTracking
    }

    static func bounded(_ value: CGFloat, fallback: CGFloat, range: ClosedRange<CGFloat>) -> CGFloat {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
    }
}

final class SharedPreviewWindowCoordinator: NSPanel {
    weak static var activeInstance: SharedPreviewWindowCoordinator?

    private var isPresentationSuspended = false
    private var previewBatchTask: Task<Void, Never>?
    private var previewBatchToken: UUID?
    private var previewActionTasks: [UUID: (request: WindowActionRequest, task: Task<Void, Never>)] = [:]

    var canPresentPreviews: Bool {
        !isPresentationSuspended && NSApp.modalWindow == nil
    }

    var selectionKeepsPreviewsOpen: Bool {
        Defaults[.keepWindowSwitcherOpenWhenSelected] &&
            windowSwitcherCoordinator.checkedWindowCount > 0 &&
            windowSwitcherCoordinator.windowSwitcherActive
    }

    var permitsCommandClickSelection: Bool {
        windowSwitcherCoordinator.windowSwitcherActive &&
            (windowSwitcherCoordinator.selectionSuppressesRelease || activePreviewShortcutKeybindSnapshot() == nil) &&
            (effectivePreviewShortcutKeybind().modifierFlags & Int(CGEventFlags.maskCommand.rawValue)) == 0
    }

    func setPresentationSuspended(_ suspended: Bool) {
        isPresentationSuspended = suspended
        publishTapSnapshot()
    }

    let windowSwitcherCoordinator = PreviewStateCoordinator()
    private let dockManager = DockAutoHideManager()
    private var searchWindow: SearchWindow?

    private var appName: String = ""
    var currentlyDisplayedPID: pid_t?
    var mouseIsWithinPreviewWindow: Bool = false {
        didSet {
            if oldValue != mouseIsWithinPreviewWindow {
                publishTapSnapshot()
            }
        }
    }

    private var onWindowTap: (() -> Void)?
    private var fullPreviewWindow: NSPanel?
    private var fullPreviewSource: (identity: PreviewWindowIdentity, capturedAt: Date)?
    private var fullPreviewRefresh: (token: UUID, capturedAt: Date, task: Task<Void, Never>)?
    private var fullPreviewFadeOutToken: UUID?
    private var activeFullPreviewHoverID: UUID?
    private var focusFadeTimer: Timer?
    private var focusFadeLocalMonitor: Any?
    private var focusFadeGlobalMonitor: Any?
    private var focusFadeSettingsObserver: Defaults.Observation?
    private var focusFadeMode: PreviewFocusFadeMode?
    private var focusFadeSelection: Int?
    private var isPreviewFocusFaded = false
    private var trackingMenus = Set<ObjectIdentifier>()
    private static let focusFadeAnimationKey = "previewFocusFade"
    private var pendingShowWorkItem: DispatchWorkItem?
    private struct DeferredActionWatcher {
        let token: UUID
        let task: Task<Void, Never>
    }

    private struct DeferredRefreshTask {
        let token: UUID
        let task: Task<Void, Never>
    }

    private struct ActivationDismissalSuppression {
        let token: UUID
        let expectedProcessIdentifier: pid_t?
        let expiresAt: Date
        let preservesDockCycle: Bool
    }

    private var deferredActionWatchersByKey: [String: DeferredActionWatcher] = [:]
    private var deferredRefreshTasksByKey: [String: DeferredRefreshTask] = [:]
    private var activationDismissalSuppression: ActivationDismissalSuppression?
    private var pendingShow: (id: UUID, pid: pid_t?, dockPosition: DockPosition, freshWindows: [WindowInfo]?)?

    var windowSize: CGSize = getWindowSize()

    private var previousHoverWindowOrigin: CGPoint?
    private var currentDockPosition: DockPosition = .bottom

    private var anchoredDockItem: (element: AXUIElement, iconRect: CGRect)?
    private var panelAnchor: (screen: NSScreen, origin: (CGSize) -> CGPoint)?
    private var frameRefreshScheduled = false

    private(set) var hasScreenRecordingPermission: Bool = PermissionsChecker.hasScreenRecordingPermission()

    var pinnedWindows: [String: (window: NSWindow, info: PinnedWindowInfo)] = [:]

    struct TapSnapshot {
        var isVisible = false
        var frame: CGRect = .zero
        var interactionFrame: CGRect?
        var fullPreviewFrame: CGRect?
        var searchFrame: CGRect?
        var isSearchFocused = false
        var isWindowSwitcherActive = false
        var isCmdTabPreview = false
        var hasSelection = false
        var hasCheckedWindows = false
        var isKeybindSessionActive = false
        var mouseIsWithinPreviewWindow = false
        var isPreviewFocusFadeMonitoring = false
        var isNativeMenuTracking = false
        var isPresentationSuspended = false

        func shouldDismissForOutsideClick(at location: CGPoint) -> Bool {
            isVisible && !isNativeMenuTracking &&
                !(interactionFrame ?? frame.insetBy(dx: HoverContainerPadding.container, dy: HoverContainerPadding.container)).contains(location) &&
                !(searchFrame?.contains(location) ?? false)
        }
    }

    private let tapSnapshotLock = NSLock()
    private var currentTapSnapshot = TapSnapshot()
    private weak var previewInteractionView: NSView?
    private var externalDragTargetToken: UUID?
    var hasExternalDragTarget: Bool { externalDragTargetToken != nil }

    func beginExternalDragTarget() -> UUID? {
        guard isVisible else { return nil }
        let token = UUID()
        externalDragTargetToken = token
        return token
    }

    func endExternalDragTarget(_ token: UUID?) {
        guard let token, externalDragTargetToken == token else { return }
        externalDragTargetToken = nil
    }

    struct ContextMenuShortcutRoutingSnapshot {
        let token: UUID
        let keybind: UserKeyBind
        let actionsByKeyCode: [UInt16: WindowAction]
    }

    private let shortcutSnapshotLock = NSLock()
    private var activePreviewShortcutKeybind: UserKeyBind?
    private var contextMenuShortcutRouting: ContextMenuShortcutRoutingSnapshot?

    /// Window state for event tap callbacks, which run off the main thread.
    var tapSnapshot: TapSnapshot {
        tapSnapshotLock.lock()
        defer { tapSnapshotLock.unlock() }
        return currentTapSnapshot
    }

    func setActivePreviewShortcutKeybind(_ keybind: UserKeyBind?) {
        shortcutSnapshotLock.lock()
        activePreviewShortcutKeybind = keybind
        shortcutSnapshotLock.unlock()
    }

    func activePreviewShortcutKeybindSnapshot() -> UserKeyBind? {
        shortcutSnapshotLock.lock()
        defer { shortcutSnapshotLock.unlock() }
        return activePreviewShortcutKeybind
    }

    func effectivePreviewShortcutKeybind(forSpaces: Bool = false) -> UserKeyBind {
        let snapshot = tapSnapshot
        if DockObserver.isCmdTabSwitcherActive || (snapshot.isVisible && snapshot.isCmdTabPreview) {
            return UserKeyBind(
                keyCode: UInt16(kVK_Tab),
                modifierFlags: Int(CGEventFlags.maskCommand.rawValue),
                modifierSide: .either
            )
        }
        let keybind = forSpaces ? Defaults[.UserKeybind] : activePreviewShortcutKeybindSnapshot() ?? Defaults[.UserKeybind]
        return WindowSwitcherShortcutResolver.dependentShortcutKeybind(keybind)
    }

    @discardableResult
    func beginContextMenuShortcutRouting(
        keybind: UserKeyBind,
        actionsByKeyCode: [UInt16: WindowAction]
    ) -> UUID {
        let token = UUID()
        shortcutSnapshotLock.lock()
        contextMenuShortcutRouting = ContextMenuShortcutRoutingSnapshot(
            token: token,
            keybind: keybind,
            actionsByKeyCode: actionsByKeyCode
        )
        shortcutSnapshotLock.unlock()
        return token
    }

    func endContextMenuShortcutRouting(token: UUID? = nil) {
        shortcutSnapshotLock.lock()
        defer { shortcutSnapshotLock.unlock() }
        guard token == nil || contextMenuShortcutRouting?.token == token else { return }
        contextMenuShortcutRouting = nil
    }

    func contextMenuShortcutRoutingSnapshot() -> ContextMenuShortcutRoutingSnapshot? {
        shortcutSnapshotLock.lock()
        defer { shortcutSnapshotLock.unlock() }
        return contextMenuShortcutRouting
    }

    @objc private func publishTapSnapshot() {
        updatePreviewFocusFade()
        let snapshot = TapSnapshot(
            isVisible: isVisible,
            frame: frame,
            interactionFrame: previewInteractionView.flatMap { view in
                guard view.window === self, !view.bounds.isEmpty else { return nil }
                return convertToScreen(view.convert(view.bounds, to: nil))
            },
            fullPreviewFrame: fullPreviewWindow.flatMap { $0.isVisible ? $0.frame : nil },
            searchFrame: searchWindowFrame,
            isSearchFocused: isSearchWindowFocused,
            isWindowSwitcherActive: windowSwitcherCoordinator.windowSwitcherActive,
            isCmdTabPreview: !windowSwitcherCoordinator.windowSwitcherActive && currentDockPosition == .cmdTab,
            hasSelection: windowSwitcherCoordinator.currIndex >= 0,
            hasCheckedWindows: windowSwitcherCoordinator.checkedWindowCount > 0,
            isKeybindSessionActive: windowSwitcherCoordinator.isKeybindSessionActive,
            mouseIsWithinPreviewWindow: mouseIsWithinPreviewWindow,
            isPreviewFocusFadeMonitoring: focusFadeLocalMonitor != nil,
            isNativeMenuTracking: !trackingMenus.isEmpty,
            isPresentationSuspended: isPresentationSuspended
        )
        tapSnapshotLock.lock()
        currentTapSnapshot = snapshot
        tapSnapshotLock.unlock()
    }

    func updatePreviewInteractionView(_ view: NSView) {
        guard view.window === self, !view.bounds.isEmpty else { return }
        let interactionFrame = convertToScreen(view.convert(view.bounds, to: nil))
        guard previewInteractionView !== view || tapSnapshot.interactionFrame != interactionFrame else { return }
        previewInteractionView = view
        publishTapSnapshot()
    }

    init() {
        let styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .fullSizeContentView, .borderless]
        super.init(contentRect: .zero, styleMask: styleMask, backing: .buffered, defer: false)
        SharedPreviewWindowCoordinator.activeInstance = self
        setupWindow()
        setupSearchWindow()
        windowSwitcherCoordinator.tapStateDidChange = { [weak self] in
            self?.publishTapSnapshot()
        }
        setupFrameRefreshObserver()
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didExposeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(publishTapSnapshot), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(panelDidResize), name: NSWindow.didResizeNotification, object: self)
        NotificationCenter.default.addObserver(self, selector: #selector(focusFadeMenuOpened), name: NSMenu.didBeginTrackingNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(focusFadeMenuClosed), name: NSMenu.didEndTrackingNotification, object: nil)
        focusFadeSettingsObserver = Defaults.observe(
            keys: .enableWindowSwitcherFocusFade, .windowSwitcherFocusFadeDelay,
            .windowSwitcherFocusFadeDuration, .windowSwitcherFocusFadeOpacity, .switcherPreviewHoverAction,
            .enableDockPreviewFocusFade, .dockPreviewFocusFadeDelay, .dockPreviewFocusFadeDuration, .dockPreviewFocusFadeOpacity, .previewHoverAction,
            .enableCmdTabFocusFade, .cmdTabFocusFadeDelay, .cmdTabFocusFadeDuration, .cmdTabFocusFadeOpacity, .cmdTabPreviewHoverAction
        ) { [weak self] in
            DispatchQueue.main.async {
                self?.stopPreviewFocusFade()
                self?.publishTapSnapshot()
            }
        }
    }

    deinit {
        previewBatchTask?.cancel()
        for pending in previewActionTasks.values {
            pending.task.cancel()
        }
        fullPreviewRefresh?.task.cancel()
        focusFadeTimer?.invalidate()
        if let focusFadeLocalMonitor { NSEvent.removeMonitor(focusFadeLocalMonitor) }
        if let focusFadeGlobalMonitor { NSEvent.removeMonitor(focusFadeGlobalMonitor) }
        focusFadeSettingsObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
        if SharedPreviewWindowCoordinator.activeInstance === self {
            SharedPreviewWindowCoordinator.activeInstance = nil
        }
        dockManager.cleanup()
    }

    private var previewFocusFadeMode: PreviewFocusFadeMode {
        if windowSwitcherCoordinator.windowSwitcherActive { return .windowSwitcher }
        return currentDockPosition == .cmdTab ? .cmdTab : .dock
    }

    private var canRunPreviewFocusFade: Bool {
        guard Defaults[previewFocusFadeMode.enabledKey] else { return false }
        return PreviewFocusFadePolicy.canFade(
            enabled: true,
            hoverAction: Defaults[previewFocusFadeMode.hoverActionKey],
            containerVisible: isVisible,
            fullPreviewVisible: windowSwitcherCoordinator.fullWindowPreviewActive && fullPreviewWindow?.isVisible == true && fullPreviewFadeOutToken == nil,
            hasSelection: windowSwitcherCoordinator.currIndex >= 0,
            menuTracking: false
        )
    }

    private func updatePreviewFocusFade() {
        if focusFadeMode != previewFocusFadeMode { stopPreviewFocusFade() }
        guard canRunPreviewFocusFade else {
            stopPreviewFocusFade()
            return
        }
        if focusFadeLocalMonitor == nil {
            focusFadeMode = previewFocusFadeMode
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                                               .scrollWheel,
                                               .leftMouseDown, .rightMouseDown, .otherMouseDown]
            focusFadeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                self?.registerPreviewFocusActivity()
                return event
            }
            focusFadeGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
                self?.registerPreviewFocusActivity()
            }
            focusFadeSelection = windowSwitcherCoordinator.currIndex
            schedulePreviewFocusFade()
        } else if focusFadeSelection != windowSwitcherCoordinator.currIndex {
            focusFadeSelection = windowSwitcherCoordinator.currIndex
            registerPreviewFocusActivity()
        }
        if isPreviewFocusFaded {
            setPreviewFocusOpacity(Float(PreviewFocusFadePolicy.bounded(Defaults[previewFocusFadeMode.opacityKey], fallback: 0.2, range: 0 ... 0.5)), duration: 0, onlyNewContent: true)
        }
    }

    func registerPreviewFocusActivity() {
        restorePreviewFocusOpacity()
        guard canRunPreviewFocusFade else {
            stopPreviewFocusFade()
            return
        }
        schedulePreviewFocusFade()
    }

    private func schedulePreviewFocusFade() {
        guard trackingMenus.isEmpty else { return }
        let delay = PreviewFocusFadePolicy.bounded(Defaults[previewFocusFadeMode.delayKey], fallback: 1.5, range: 0 ... 5)
        let deadline = Date().addingTimeInterval(delay)
        if let focusFadeTimer {
            focusFadeTimer.fireDate = deadline
            return
        }
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] timer in
            guard let self, focusFadeTimer === timer else { return }
            focusFadeTimer = nil
            guard canRunPreviewFocusFade, trackingMenus.isEmpty else { return }
            isPreviewFocusFaded = true
            let opacity = PreviewFocusFadePolicy.bounded(Defaults[previewFocusFadeMode.opacityKey], fallback: 0.2, range: 0 ... 0.5)
            let duration = Defaults[.showAnimations]
                ? PreviewFocusFadePolicy.bounded(Defaults[previewFocusFadeMode.durationKey], fallback: 0.5, range: 0 ... 5)
                : 0
            setPreviewFocusOpacity(Float(opacity), duration: duration)
        }
        focusFadeTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func setPreviewFocusOpacity(_ opacity: Float, duration: TimeInterval, onlyNewContent: Bool = false) {
        // Keep the panels interactive even at 0% opacity; only their rendered contents fade.
        for view in [contentView, searchWindow?.contentView].compactMap({ $0 }) {
            view.wantsLayer = true
            guard let layer = view.layer else { continue }
            if onlyNewContent, layer.opacity == opacity { continue }
            let currentOpacity = layer.presentation()?.opacity ?? layer.opacity
            layer.removeAnimation(forKey: Self.focusFadeAnimationKey)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = opacity
            CATransaction.commit()
            if duration > 0 {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = currentOpacity
                animation.toValue = opacity
                animation.duration = duration
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                layer.add(animation, forKey: Self.focusFadeAnimationKey)
            }
        }
    }

    private func restorePreviewFocusOpacity() {
        guard isPreviewFocusFaded else { return }
        isPreviewFocusFaded = false
        setPreviewFocusOpacity(1, duration: 0)
    }

    private func stopPreviewFocusFade() {
        focusFadeTimer?.invalidate()
        focusFadeTimer = nil
        if let focusFadeLocalMonitor { NSEvent.removeMonitor(focusFadeLocalMonitor) }
        if let focusFadeGlobalMonitor { NSEvent.removeMonitor(focusFadeGlobalMonitor) }
        focusFadeLocalMonitor = nil
        focusFadeGlobalMonitor = nil
        focusFadeSelection = nil
        focusFadeMode = nil
        restorePreviewFocusOpacity()
    }

    @objc private func focusFadeMenuOpened(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        trackingMenus.insert(ObjectIdentifier(menu))
        publishTapSnapshot()
        focusFadeTimer?.invalidate()
        focusFadeTimer = nil
        restorePreviewFocusOpacity()
    }

    @objc private func focusFadeMenuClosed(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu else { return }
        trackingMenus.remove(ObjectIdentifier(menu))
        publishTapSnapshot()
        if trackingMenus.isEmpty, canRunPreviewFocusFade { registerPreviewFocusActivity() }
    }

    private func setupWindow() {
        level = Defaults[.raisedWindowLevel] ? .statusBar : .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    private func setupSearchWindow() {
        if Defaults[.enableWindowSwitcherSearch] {
            if searchWindow == nil {
                searchWindow = SearchWindow(previewCoordinator: windowSwitcherCoordinator)
            }
        } else {
            searchWindow?.hideSearch()
            searchWindow = nil
        }
    }

    private func setupFrameRefreshObserver() {
        windowSwitcherCoordinator.onFrameRefreshNeeded = { [weak self] in
            self?.schedulePanelFrameRefresh()
        }
    }

    private func schedulePanelFrameRefresh() {
        guard !frameRefreshScheduled else { return }
        frameRefreshScheduled = true
        // Let SwiftUI consume the new rows before measuring their intrinsic size.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            frameRefreshScheduled = false
            refreshPanelFrameToFitContent()
        }
    }

    func updateSearchWindow(with text: String) {
        guard Defaults[.enableWindowSwitcherSearch] else { return }
        if searchWindow == nil { setupSearchWindow() }
        if searchWindow?.isFocused != true {
            searchWindow?.updateSearchText(text)
        }
    }

    func focusSearchWindow() {
        guard Defaults[.enableWindowSwitcherSearch] else { return }
        if searchWindow == nil { setupSearchWindow() }
        guard let searchWindow else { return }
        searchWindow.showSearch(relativeTo: self)
        searchWindow.focusSearchField()
        publishTapSnapshot()
    }

    func unfocusSearchWindow() {
        searchWindow?.unfocusSearchField()
        publishTapSnapshot()
    }

    var isSearchWindowFocused: Bool {
        searchWindow?.isFocused ?? false
    }

    var searchWindowFrame: NSRect? {
        guard let searchWindow, searchWindow.isVisible else { return nil }
        return searchWindow.frame
    }

    func containsQuartzPoint(_ point: CGPoint) -> Bool {
        let snapshot = tapSnapshot
        guard snapshot.isVisible else { return false }

        let screen = NSScreen.screenFromQuartzPoint(point)
        let appKitPoint = DockObserver.nsPointFromCGPoint(point, forScreen: screen)
        let hitSlop: CGFloat = 2

        return [snapshot.frame, snapshot.fullPreviewFrame, snapshot.searchFrame]
            .compactMap { $0 }
            .contains { $0.insetBy(dx: -hitSlop, dy: -hitSlop).contains(appKitPoint) }
    }

    private func isCalendarApp(bundleIdentifier: String?) -> Bool {
        guard let bundleId = bundleIdentifier else { return false }
        return bundleId == calendarAppIdentifier
    }

    @MainActor private func getEmbeddedContentType(for bundleIdentifier: String?) -> EmbeddedContentType {
        guard let bundleId = bundleIdentifier else { return .none }

        if isMediaApp(bundleId) {
            return .media(bundleIdentifier: bundleId)
        } else if isCalendarApp(bundleIdentifier: bundleId) {
            return .calendar(bundleIdentifier: bundleId)
        }

        return .none
    }

    func cancelPendingShow() {
        pendingShowWorkItem?.cancel()
        pendingShowWorkItem = nil
        pendingShow = nil
    }

    func restoreDockAutoHideState() {
        dockManager.restoreDockState()
    }

    func hideWindow(cancelPendingShow shouldCancelPendingShow: Bool = true) {
        externalDragTargetToken = nil
        ActionFeedbackController.existing?.previewWillDisappear(self)
        windowSwitcherCoordinator.clearCheckedWindows(resetOwnership: true)
        stopPreviewFocusFade()
        AppIconBadgeStore.stopIfInitialized()
        if shouldCancelPendingShow {
            cancelPendingShow()
        }
        PreviewContextMenuController.shared.dismiss()
        endContextMenuShortcutRouting()
        SpaceMoveMenuController.shared.dismiss()
        cancelAllDeferredActionWatchers()
        activationDismissalSuppression = nil

        // Always restore dock auto-hide state, even if the preview isn't visible.
        restoreDockAutoHideState()
        hideFullPreviewWindow()
        DragPreviewCoordinator.shared.endDragging()

        guard isVisible else { return }

        searchWindow?.hideSearch()

        if let currentContent = contentView {
            currentContent.removeFromSuperview()
        }
        contentView = nil
        appName = ""
        currentlyDisplayedPID = nil
        mouseIsWithinPreviewWindow = false
        anchoredDockItem = nil
        panelAnchor = nil

        let currentDockPos = DockUtils.getDockPosition()
        let currentScreen = NSScreen.main ?? NSScreen.screens.first!
        windowSwitcherCoordinator.setWindows([], dockPosition: currentDockPos, bestGuessMonitor: currentScreen)
        windowSwitcherCoordinator.setShowing(.both, toState: false)
        orderOut(nil)
        publishTapSnapshot()
    }

    @discardableResult
    func suppressNextActionDrivenActivationDismissal(for app: NSRunningApplication, wasHidden: Bool) -> UUID? {
        let expectedProcessIdentifier: pid_t?
        if wasHidden {
            expectedProcessIdentifier = app.processIdentifier
        } else {
            guard let frontmostProcessIdentifier = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
            expectedProcessIdentifier = frontmostProcessIdentifier == app.processIdentifier
                ? nil
                : frontmostProcessIdentifier
        }

        return suppressNextActionDrivenActivationDismissal(for: expectedProcessIdentifier)
    }

    @discardableResult
    private func suppressNextActionDrivenActivationDismissal(for expectedProcessIdentifier: pid_t?, preservesDockCycle: Bool = false) -> UUID? {
        guard isVisible else { return nil }

        let token = UUID()
        activationDismissalSuppression = ActivationDismissalSuppression(
            token: token,
            expectedProcessIdentifier: expectedProcessIdentifier,
            expiresAt: Date().addingTimeInterval(1),
            preservesDockCycle: preservesDockCycle
        )
        return token
    }

    func cancelActionDrivenActivationDismissalSuppression(token: UUID?) {
        guard let token, activationDismissalSuppression?.token == token else { return }
        activationDismissalSuppression = nil
    }

    func shouldSuppressActionDrivenActivationDismissal(for processIdentifier: pid_t) -> Bool {
        guard let suppression = activationDismissalSuppression else { return false }
        guard suppression.expiresAt >= Date() else {
            activationDismissalSuppression = nil
            return false
        }

        if suppression.preservesDockCycle, !canPreserveDockPreviewsForWindowCycle(of: processIdentifier) {
            activationDismissalSuppression = nil
            return false
        }

        let matches = suppression.expectedProcessIdentifier == nil ||
            suppression.expectedProcessIdentifier == processIdentifier
        if !matches {
            activationDismissalSuppression = nil
        }
        return matches
    }

    func canPreserveDockPreviewsForWindowCycle(of processIdentifier: pid_t) -> Bool {
        Defaults[.keepDockPreviewsOpenWhenCycling] &&
            Defaults[.shouldHideOnDockItemClick] && Defaults[.dockClickAction] == .cycleWindows &&
            isVisible && !windowSwitcherCoordinator.windowSwitcherActive &&
            currentDockPosition != .cmdTab && currentlyDisplayedPID == processIdentifier
    }

    @discardableResult
    func preserveDockPreviewsForWindowCycle(to window: WindowInfo) -> Bool {
        guard canPreserveDockPreviewsForWindowCycle(of: window.app.processIdentifier) else { return false }
        guard !WindowUtil.activationMaySwitchSpaces(for: window) else {
            hideWindow()
            return false
        }
        suppressNextActionDrivenActivationDismissal(for: window.app.processIdentifier, preservesDockCycle: true)
        return true
    }

    @MainActor
    private func deferredWatcherKey(pid: pid_t, action: WindowAction, purpose: String = "dismiss") -> String {
        "\(pid)-\(action.rawValue)-\(purpose)"
    }

    @MainActor
    private func deferredRefreshKey(pid: pid_t, purpose: String) -> String {
        "\(pid)-\(purpose)"
    }

    @MainActor
    private var shouldRunDeferredWatchers: Bool {
        isVisible || windowSwitcherCoordinator.windowSwitcherActive || windowSwitcherCoordinator.fullWindowPreviewActive
    }

    @MainActor
    private func cancelAllDeferredActionWatchers() {
        for watcher in deferredActionWatchersByKey.values {
            watcher.task.cancel()
        }
        deferredActionWatchersByKey.removeAll()
    }

    @MainActor
    private func startDeferredRefreshTask(
        pid: pid_t,
        purpose: String,
        operation: @escaping () async -> Void
    ) {
        let key = deferredRefreshKey(pid: pid, purpose: purpose)
        deferredRefreshTasksByKey[key]?.task.cancel()

        let token = UUID()
        let task = Task { [weak self] in
            await operation()
            await MainActor.run {
                guard let self else { return }
                if self.deferredRefreshTasksByKey[key]?.token == token {
                    self.deferredRefreshTasksByKey.removeValue(forKey: key)
                }
            }
        }
        deferredRefreshTasksByKey[key] = DeferredRefreshTask(token: token, task: task)
    }

    @MainActor
    private func startDeferredActionWatcher(
        pid: pid_t,
        action: WindowAction,
        purpose: String = "dismiss",
        operation: @escaping @MainActor () async -> Void
    ) {
        let key = deferredWatcherKey(pid: pid, action: action, purpose: purpose)
        deferredActionWatchersByKey[key]?.task.cancel()

        let token = UUID()
        let task = Task { @MainActor [weak self] in
            await operation()
            guard let self else { return }
            if deferredActionWatchersByKey[key]?.token == token {
                deferredActionWatchersByKey.removeValue(forKey: key)
            }
        }
        deferredActionWatchersByKey[key] = DeferredActionWatcher(token: token, task: task)
    }

    /// Merges fresh windows if currently displaying the expected app and mode.
    @MainActor
    @discardableResult
    func mergeWindowsIfNeeded(_ pid: pid_t? = nil, windows: [WindowInfo], dockPosition: DockPosition, bestGuessMonitor: NSScreen) -> Bool {
        if !windowSwitcherCoordinator.windowSwitcherActive,
           let pid, pendingShow?.pid == pid, pendingShow?.dockPosition == dockPosition
        {
            pendingShow?.freshWindows = windows
            return true
        }
        guard currentlyDisplayedPID == pid, currentDockPosition == dockPosition else { return false }
        windowSwitcherCoordinator.mergeWindows(windows, dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor)
        if dockPosition == .cmdTab, let refreshedPID = windows.first?.app.processIdentifier {
            currentlyDisplayedPID = refreshedPID
        }
        return true
    }

    /// Refreshes the panel frame after content layout changes.
    @MainActor
    private func refreshPanelFrameToFitContent() {
        guard isVisible, let hostingView = contentView else { return }

        hostingView.layoutSubtreeIfNeeded()

        guard let panelAnchor else { return }
        let maximumSize = maximumPreviewSize(on: panelAnchor.screen)
        let fittingSize = hostingView.fittingSize
        // The prediction covers all windows; search must size only its filtered content.
        let expectedSize = windowSwitcherCoordinator.hasActiveSearch ? .zero : windowSwitcherCoordinator.expectedContentSize
        let newSize = CGSize(
            width: min(max(fittingSize.width, expectedSize.width), maximumSize.width),
            height: min(max(fittingSize.height, expectedSize.height), maximumSize.height)
        )
        guard let newOrigin = anchoredOrigin(for: newSize) else { return }
        let targetFrame = CGRect(origin: newOrigin, size: newSize)
        guard targetFrame != frame else { return }

        let searchFrame = searchWindow.flatMap { $0.isVisible ? $0.targetFrame(relativeTo: targetFrame, on: self.screen ?? panelAnchor.screen) : nil }
        animateWithUserPreference {
            self.animator().setFrame(targetFrame, display: true)
            if let searchFrame { self.searchWindow?.animator().setFrame(searchFrame, display: true) }
        }
    }

    private func anchoredOrigin(for size: CGSize) -> CGPoint? {
        guard let panelAnchor else { return nil }
        let screenFrame = previewPlacementFrame(on: panelAnchor.screen)
        var origin = panelAnchor.origin(size)
        origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - size.width))
        origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - size.height))
        return constrainHeaderTop(origin, windowSize: size, screen: panelAnchor.screen)
    }

    @objc private func panelDidResize() {
        guard let origin = anchoredOrigin(for: frame.size),
              abs(origin.x - frame.minX) > 0.5 || abs(origin.y - frame.minY) > 0.5
        else { return }
        setFrameOrigin(origin)
        if let searchWindow, searchWindow.isVisible {
            searchWindow.showSearch(relativeTo: self)
        }
    }

    @MainActor
    private func performShowView(_ view: some View,
                                 mouseLocation: CGPoint?,
                                 mouseScreen: NSScreen,
                                 dockItemElement: AXUIElement?,
                                 dockIconRect: CGRect?,
                                 dockPositionOverride: DockPosition? = nil,
                                 dockItemFrameOverride: CGRect? = nil)
    {
        guard canPresentPreviews else { return }
        currentDockPosition = dockPositionOverride ?? DockUtils.getDockPosition()
        let hostingView = NSHostingView(rootView: view)

        if let oldContentView = contentView {
            oldContentView.removeFromSuperview()
        }
        contentView = hostingView

        let newHoverWindowSize = hostingView.fittingSize
        let isDockIconAnchored = dockItemElement != nil && dockIconRect != nil

        let origin: (CGSize) -> CGPoint = if isDockIconAnchored, let dockIconRect {
            { [unowned self] in calculateWindowPosition(mouseLocation: mouseLocation, windowSize: $0, screen: mouseScreen, dockIconRect: dockIconRect, dockPositionOverride: dockPositionOverride) }
        } else if let dockItemFrameOverride {
            { [unowned self] in calculateWindowPositionFromFrame(mouseLocation: mouseLocation, windowSize: $0, screen: mouseScreen, dockItemFrame: dockItemFrameOverride, dockPositionOverride: dockPositionOverride) }
        } else {
            { [unowned self] in centerWindowOnScreen(size: $0, screen: mouseScreen) }
        }
        let position = origin(newHoverWindowSize)

        // Prevent rendering if position calculation failed for cmd-tab
        if isDockIconAnchored, dockPositionOverride == .cmdTab, position == .zero {
            if let oldContentView = contentView {
                oldContentView.removeFromSuperview()
            }
            contentView = nil
            return
        }

        let finalFrame = CGRect(origin: position, size: newHoverWindowSize)
        panelAnchor = nil
        applyWindowFrame(finalFrame, animated: true, dockPositionOverride: dockPositionOverride)
        previousHoverWindowOrigin = position
        panelAnchor = (mouseScreen, origin)
    }

    @MainActor
    private func updateContentViewSizeAndPosition(mouseLocation: CGPoint? = nil, mouseScreen: NSScreen, dockItemElement: AXUIElement?,
                                                  dockIconRect: CGRect? = nil,
                                                  animated: Bool, centerOnScreen: Bool = false,
                                                  centeredHoverWindowState: PreviewStateCoordinator.WindowState? = nil,
                                                  embeddedContentType: EmbeddedContentType = .none,
                                                  dockPositionOverride: DockPosition? = nil,
                                                  dockItemFrameOverride: CGRect? = nil,
                                                  renderStartTime: CFAbsoluteTime? = nil)
    {
        var elapsed = renderStartTime.map { (CFAbsoluteTimeGetCurrent() - $0) * 1000 } ?? 0
        DebugLogger.log("PreviewRender", details: "updateContentView start (+\(String(format: "%.1f", elapsed))ms)")

        windowSwitcherCoordinator.setShowing(centeredHoverWindowState, toState: centerOnScreen)

        // Defer showing the search window until after the hover window frame is applied

        let updateAvailable = (NSApp.delegate as? AppDelegate)?.updaterState.anUpdateIsAvailable ?? false

        elapsed = renderStartTime.map { (CFAbsoluteTimeGetCurrent() - $0) * 1000 } ?? 0

        let hoverView = WindowPreviewHoverContainer(appName: appName,
                                                    onWindowTap: onWindowTap,
                                                    dockPosition: dockPositionOverride ?? DockUtils.getDockPosition(),
                                                    mouseLocation: mouseLocation,
                                                    bestGuessMonitor: mouseScreen,
                                                    dockItemElement: dockItemElement,
                                                    dockItemFrameOverride: dockItemFrameOverride,
                                                    windowSwitcherCoordinator: windowSwitcherCoordinator,
                                                    mockPreviewActive: false,
                                                    updateAvailable: updateAvailable,
                                                    embeddedContentType: embeddedContentType,
                                                    hasScreenRecordingPermission: hasScreenRecordingPermission)
        let newHostingView = NSHostingView(rootView: hoverView)

        if let oldContentView = contentView {
            oldContentView.removeFromSuperview()
        }
        contentView = newHostingView

        elapsed = renderStartTime.map { (CFAbsoluteTimeGetCurrent() - $0) * 1000 } ?? 0
        DebugLogger.log("PreviewRender", details: "calculating fittingSize (+\(String(format: "%.1f", elapsed))ms)")

        let newHoverWindowSize: CGSize
        do {
            let expectedContentSize = windowSwitcherCoordinator.expectedContentSize
            let targetSize: CGSize
            if windowSwitcherCoordinator.windowSwitcherActive,
               windowSwitcherCoordinator.expectedContentSizeIsExact,
               expectedContentSize != .zero
            {
                targetSize = expectedContentSize

                elapsed = renderStartTime.map { (CFAbsoluteTimeGetCurrent() - $0) * 1000 } ?? 0
                DebugLogger.log("PreviewRender", details: "using predicted size, fittingSize skipped: \(targetSize) (+\(String(format: "%.1f", elapsed))ms)")
            } else {
                let fittingSize = newHostingView.fittingSize

                elapsed = renderStartTime.map { (CFAbsoluteTimeGetCurrent() - $0) * 1000 } ?? 0
                DebugLogger.log("PreviewRender", details: "fittingSize done: \(fittingSize) (+\(String(format: "%.1f", elapsed))ms)")

                targetSize = expectedContentSize == .zero
                    ? fittingSize
                    : CGSize(
                        width: max(fittingSize.width, expectedContentSize.width),
                        height: max(fittingSize.height, expectedContentSize.height)
                    )
            }
            let maximumSize = maximumPreviewSize(on: mouseScreen)
            newHoverWindowSize = CGSize(
                width: min(targetSize.width, maximumSize.width),
                height: min(targetSize.height, maximumSize.height)
            )
        }

        let isDockIconAnchored = !centerOnScreen && dockItemElement != nil && dockIconRect != nil

        let origin: (CGSize) -> CGPoint = if centerOnScreen {
            { [unowned self] in centerWindowOnScreen(size: $0, screen: mouseScreen) }
        } else if isDockIconAnchored, let dockIconRect {
            { [unowned self] in calculateWindowPosition(mouseLocation: mouseLocation, windowSize: $0, screen: mouseScreen, dockIconRect: dockIconRect, dockPositionOverride: dockPositionOverride) }
        } else if let dockItemFrameOverride {
            { [unowned self] in calculateWindowPositionFromFrame(mouseLocation: mouseLocation, windowSize: $0, screen: mouseScreen, dockItemFrame: dockItemFrameOverride, dockPositionOverride: dockPositionOverride) }
        } else if let mouseLocation, dockPositionOverride == .cli {
            { [unowned self] in calculateWindowPositionFromMouse(mouseLocation: mouseLocation, windowSize: $0, screen: mouseScreen) }
        } else {
            { [unowned self] in centerWindowOnScreen(size: $0, screen: mouseScreen) }
        }
        let position = origin(newHoverWindowSize)

        // Prevent rendering if position calculation failed for cmd-tab
        if isDockIconAnchored, dockPositionOverride == .cmdTab, position == .zero {
            if let oldContentView = contentView {
                oldContentView.removeFromSuperview()
            }
            contentView = nil
            return
        }

        let finalFrame = CGRect(origin: position, size: newHoverWindowSize)

        panelAnchor = nil
        setFrame(finalFrame, display: false)
        applyWindowFrame(finalFrame, animated: animated, dockPositionOverride: dockPositionOverride)
        previousHoverWindowOrigin = position
        panelAnchor = (mouseScreen, origin)

        elapsed = renderStartTime.map { (CFAbsoluteTimeGetCurrent() - $0) * 1000 } ?? 0
        DebugLogger.log("PreviewRender", details: "window frame applied, render complete (+\(String(format: "%.1f", elapsed))ms)")

        // Now that the main panel has a valid frame, position the search window (if active)
        if windowSwitcherCoordinator.windowSwitcherActive, Defaults[.enableWindowSwitcherSearch] {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if searchWindow == nil { setupSearchWindow() }
                searchWindow?.showSearch(relativeTo: self)
                publishTapSnapshot()
            }
        }
    }

    func beginFullPreviewHover() -> UUID? {
        guard isVisible else { return nil }
        hideFullPreviewWindow()
        let hoverID = UUID()
        activeFullPreviewHoverID = hoverID
        return hoverID
    }

    func cancelFullPreviewHover(_ hoverID: UUID) {
        guard activeFullPreviewHoverID == hoverID else { return }
        hideFullPreviewWindow()
    }

    func isFullPreviewHoverActive(_ hoverID: UUID?) -> Bool {
        isVisible && hoverID != nil && activeFullPreviewHoverID == hoverID
    }

    @MainActor
    private func showFullPreviewWindow(for windowInfo: WindowInfo, on screen: NSScreen, frame: CGRect? = nil) {
        guard canPresentPreviews else { return }
        fullPreviewRefresh?.task.cancel()
        fullPreviewRefresh = nil
        if frame == nil { windowSwitcherCoordinator.setShowing(.fullWindowPreview, toState: true) }

        let wasFadingOut = fullPreviewFadeOutToken != nil
        fullPreviewFadeOutToken = nil
        let isNewWindow = fullPreviewWindow == nil
        if fullPreviewWindow == nil {
            let styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .fullSizeContentView, .borderless]
            fullPreviewWindow = NSPanel(contentRect: .zero, styleMask: styleMask, backing: .buffered, defer: false)
            fullPreviewWindow?.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
            fullPreviewWindow?.isOpaque = false
            fullPreviewWindow?.backgroundColor = .clear
            fullPreviewWindow?.hasShadow = true
            fullPreviewWindow?.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
            fullPreviewWindow?.hidesOnDeactivate = false
            fullPreviewWindow?.becomesKeyOnlyIfNeeded = true
            fullPreviewWindow?.animationBehavior = .none
        }

        let flippedIconRect: CGRect
        if let frame {
            flippedIconRect = frame
        } else {
            let size = (try? windowInfo.axElement.size()) ?? screen.frame.size
            let position = (try? windowInfo.axElement.position()) ?? CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            let converted = DockObserver.cgPointFromNSPoint(position, forScreen: screen)
            flippedIconRect = CGRect(x: converted.x, y: converted.y - size.height, width: size.width, height: size.height)
        }
        let windowSize = flippedIconRect.size

        let previewView = FullSizePreviewView(windowInfo: windowInfo, windowSize: windowSize)
        if frame != nil, let hostingView = fullPreviewWindow?.contentView as? NSHostingView<FullSizePreviewView> {
            hostingView.rootView = previewView
        } else {
            fullPreviewWindow?.contentView?.removeFromSuperview()
            fullPreviewWindow?.contentView = NSHostingView(rootView: previewView)
        }

        fullPreviewWindow?.setFrame(flippedIconRect, display: true)
        guard let fullPreviewWindow else { return }
        fullPreviewSource = (PreviewWindowIdentity(windowInfo), windowInfo.imageCapturedTime)
        if frame != nil {
            // A cache refresh must not raise the panel or interrupt its existing fade-in.
            publishTapSnapshot()
            return
        }

        let fadeInDuration = Defaults[.fullSizePreviewFadeInDuration]
        let shouldFadeIn = fadeInDuration > 0 && (isNewWindow || wasFadingOut || !fullPreviewWindow.isVisible)
        if isNewWindow, shouldFadeIn {
            fullPreviewWindow.alphaValue = 0
        }
        fullPreviewWindow.makeKeyAndOrderFront(nil)
        if shouldFadeIn {
            animateWithUserPreference(
                duration: fadeInDuration,
                timingFunction: CAMediaTimingFunction(name: .easeOut)
            ) {
                fullPreviewWindow.animator().alphaValue = 1
            }
        } else {
            fullPreviewWindow.alphaValue = 1
        }
        publishTapSnapshot()
    }

    @MainActor
    func refreshDisplayedFullPreview(after updates: [WindowInfo]) {
        guard let panel = fullPreviewWindow, panel.isVisible, fullPreviewFadeOutToken == nil,
              let source = fullPreviewSource,
              let updated = updates.filter({ PreviewWindowIdentity($0) == source.identity }).max(by: { $0.imageCapturedTime < $1.imageCapturedTime }),
              updated.imageCapturedTime > source.capturedAt,
              fullPreviewRefresh.map({ updated.imageCapturedTime > $0.capturedAt }) ?? true
        else { return }
        fullPreviewRefresh?.task.cancel()
        let token = UUID()
        let task = Task { @MainActor [weak self, weak panel] in
            let frame = await updated.readWindowFrame()
            guard let self else { return }
            defer { if fullPreviewRefresh?.token == token { fullPreviewRefresh = nil } }
            guard !Task.isCancelled, fullPreviewRefresh?.token == token,
                  fullPreviewSource?.identity == source.identity,
                  let panel, fullPreviewWindow === panel, panel.isVisible, fullPreviewFadeOutToken == nil,
                  let frame, let screen = NSScreen.screen(containing: frame)
            else { return }
            fullPreviewRefresh = nil
            showFullPreviewWindow(for: updated, on: screen, frame: frame)
        }
        fullPreviewRefresh = (token, updated.imageCapturedTime, task)
    }

    @MainActor
    func hideFullPreviewWindow() {
        fullPreviewRefresh?.task.cancel()
        fullPreviewRefresh = nil
        fullPreviewSource = nil
        stopPreviewFocusFade()
        windowSwitcherCoordinator.setShowing(.fullWindowPreview, toState: false)
        activeFullPreviewHoverID = nil
        guard let fullPreviewWindow else {
            publishTapSnapshot()
            return
        }

        guard fullPreviewFadeOutToken == nil else {
            publishTapSnapshot()
            return
        }

        let fadeOutDuration = Defaults[.fullSizePreviewFadeOutDuration]
        guard fadeOutDuration > 0, fullPreviewWindow.isVisible, Defaults[.showAnimations] else {
            removeFullPreviewWindow(fullPreviewWindow)
            return
        }

        let fadeOutToken = UUID()
        fullPreviewFadeOutToken = fadeOutToken
        publishTapSnapshot()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fullPreviewWindow.animator().alphaValue = 0
        } completionHandler: { [weak self, weak fullPreviewWindow] in
            DispatchQueue.main.async {
                guard let self, let fullPreviewWindow,
                      self.fullPreviewFadeOutToken == fadeOutToken,
                      self.fullPreviewWindow === fullPreviewWindow
                else { return }
                self.removeFullPreviewWindow(fullPreviewWindow)
            }
        }
    }

    @MainActor
    private func removeFullPreviewWindow(_ window: NSPanel) {
        window.orderOut(nil)
        window.contentView?.removeFromSuperview()
        window.contentView = nil
        if fullPreviewWindow === window {
            fullPreviewWindow = nil
        }
        fullPreviewFadeOutToken = nil
        publishTapSnapshot()
    }

    private func centerWindowOnScreen(size: CGSize, screen: NSScreen) -> CGPoint {
        let placementFrame = previewPlacementFrame(on: screen)
        let baseXPosition: CGFloat = switch Defaults[.windowSwitcherHorizontalAnchor] {
        case .left:
            placementFrame.minX
        case .center:
            placementFrame.midX - (size.width / 2)
        case .right:
            placementFrame.maxX - size.width
        }

        let baseYPosition: CGFloat = switch Defaults[.windowSwitcherVerticalAnchor] {
        case .top:
            placementFrame.maxY - size.height
        case .center:
            placementFrame.midY - (size.height / 2)
        case .bottom:
            placementFrame.minY
        }

        let isOffsetEnabled = Defaults[.enableShiftWindowSwitcherPlacement]
        let horizontalOffset = isOffsetEnabled
            ? screen.frame.width * (Defaults[.windowSwitcherHorizontalOffsetPercent] / 100.0)
            : 0
        let verticalOffset = isOffsetEnabled
            ? screen.frame.height * (Defaults[.windowSwitcherVerticalOffsetPercent] / 100.0)
            : 0

        var xPosition = baseXPosition + horizontalOffset
        var yPosition = baseYPosition + verticalOffset

        if reservesWindowSwitcherSearchSpace {
            xPosition = max(placementFrame.minX, min(xPosition, placementFrame.maxX - size.width))
            yPosition = max(placementFrame.minY, min(yPosition, placementFrame.maxY - size.height))
        }

        return constrainHeaderTop(CGPoint(x: xPosition, y: yPosition), windowSize: size, screen: screen)
    }

    private func constrainHeaderTop(_ origin: CGPoint, windowSize: CGSize, screen: NSScreen) -> CGPoint {
        let headerStyle = (contentView as? NSHostingView<WindowPreviewHoverContainer>)?.rootView.appHeaderStyleForPlacement
        return PreviewHeaderLayout.constrainHeaderTop(origin, windowSize: windowSize,
                                                      visibleFrame: screen.visibleFrame, appHeaderStyle: headerStyle)
    }

    private var reservesWindowSwitcherSearchSpace: Bool {
        windowSwitcherCoordinator.windowSwitcherActive && Defaults[.enableWindowSwitcherSearch]
    }

    private func previewPlacementFrame(on screen: NSScreen) -> CGRect {
        guard reservesWindowSwitcherSearchSpace else { return screen.frame }

        var frame = screen.visibleFrame
        frame.size.height = max(0, frame.height - SearchWindow.reservedHeight)
        return frame
    }

    private func maximumPreviewSize(on screen: NSScreen) -> CGSize {
        let frame = reservesWindowSwitcherSearchSpace ? previewPlacementFrame(on: screen) : screen.visibleFrame
        return frame.size
    }

    private func calculateWindowPositionFromMouse(mouseLocation: CGPoint, windowSize: CGSize, screen: NSScreen) -> CGPoint {
        let screenFrame = screen.frame
        let buffer: CGFloat = 10

        var xPosition = mouseLocation.x - (windowSize.width / 2)
        var yPosition = mouseLocation.y + buffer

        xPosition = max(screenFrame.minX, min(xPosition, screenFrame.maxX - windowSize.width))
        yPosition = max(screenFrame.minY, min(yPosition, screenFrame.maxY - windowSize.height))

        return constrainHeaderTop(CGPoint(x: xPosition, y: yPosition), windowSize: windowSize, screen: screen)
    }

    private func calculateWindowPosition(mouseLocation: CGPoint?, windowSize: CGSize, screen: NSScreen, dockIconRect: CGRect, dockPositionOverride: DockPosition? = nil) -> CGPoint {
        guard let mouseLocation else { return .zero }
        let screenFrame = screen.frame
        let dockPosition = dockPositionOverride ?? DockUtils.getDockPosition()

        // Use the anchored icon rect when anchoring is enabled, otherwise use the freshly captured rect
        let iconRect = (Defaults[.anchorDockPreviewPosition] ? anchoredDockItem?.iconRect : nil) ?? dockIconRect
        let flippedIconRect = CGRect(
            origin: DockObserver.cgPointFromNSPoint(iconRect.origin, forScreen: screen),
            size: iconRect.size
        )

        var xPosition: CGFloat
        var yPosition: CGFloat

        switch dockPosition {
        case .bottom, .cmdTab:
            xPosition = flippedIconRect.midX - (windowSize.width / 2)
            yPosition = flippedIconRect.minY
        case .left:
            xPosition = flippedIconRect.maxX
            yPosition = flippedIconRect.midY - (windowSize.height / 2) - flippedIconRect.height
        case .right:
            xPosition = flippedIconRect.minX - windowSize.width
            yPosition = flippedIconRect.midY - (windowSize.height / 2) - flippedIconRect.height
        default:
            xPosition = mouseLocation.x - (windowSize.width / 2)
            yPosition = mouseLocation.y - (windowSize.height / 2)
        }

        let bufferFromDock = Defaults[.bufferFromDock]
        switch dockPosition {
        case .left:
            xPosition += bufferFromDock
        case .right:
            xPosition -= bufferFromDock
        case .bottom:
            yPosition += bufferFromDock
        case .cmdTab:
            yPosition += 5
        default:
            break
        }

        xPosition = max(screenFrame.minX, min(xPosition, screenFrame.maxX - windowSize.width))
        yPosition = max(screenFrame.minY, min(yPosition, screenFrame.maxY - windowSize.height))

        return constrainHeaderTop(CGPoint(x: xPosition, y: yPosition), windowSize: windowSize, screen: screen)
    }

    private func calculateWindowPositionFromFrame(mouseLocation: CGPoint?, windowSize: CGSize, screen: NSScreen, dockItemFrame: CGRect, dockPositionOverride: DockPosition? = nil) -> CGPoint {
        let screenFrame = screen.frame
        let dockPosition = dockPositionOverride ?? DockUtils.getDockPosition()
        let flippedIconRect = dockItemFrame

        var xPosition: CGFloat
        var yPosition: CGFloat

        switch dockPosition {
        case .bottom, .cmdTab, .cli:
            xPosition = flippedIconRect.midX - (windowSize.width / 2)
            yPosition = flippedIconRect.maxY
        case .left:
            xPosition = flippedIconRect.maxX
            yPosition = flippedIconRect.midY - (windowSize.height / 2)
        case .right:
            xPosition = flippedIconRect.minX - windowSize.width
            yPosition = flippedIconRect.midY - (windowSize.height / 2)
        default:
            if let mouseLocation {
                xPosition = mouseLocation.x - (windowSize.width / 2)
                yPosition = mouseLocation.y - (windowSize.height / 2)
            } else {
                xPosition = flippedIconRect.midX - (windowSize.width / 2)
                yPosition = flippedIconRect.maxY
            }
        }

        let bufferFromDock = Defaults[.bufferFromDock]
        switch dockPosition {
        case .left:
            xPosition += bufferFromDock
        case .right:
            xPosition -= bufferFromDock
        case .bottom, .cli:
            yPosition += bufferFromDock
        case .cmdTab:
            yPosition += 5
        default:
            break
        }

        xPosition = max(screenFrame.minX, min(xPosition, screenFrame.maxX - windowSize.width))
        yPosition = max(screenFrame.minY, min(yPosition, screenFrame.maxY - windowSize.height))

        return constrainHeaderTop(CGPoint(x: xPosition, y: yPosition), windowSize: windowSize, screen: screen)
    }

    @MainActor
    private func applyWindowFrame(_ frame: CGRect, animated: Bool, dockPositionOverride: DockPosition? = nil) {
        let shouldAnimate = animated && Defaults[.showAnimations]

        setFrame(frame, display: true)
        alphaValue = 1.0
        makeKeyAndOrderFront(nil)
        publishTapSnapshot()

        if shouldAnimate, let layer = contentView?.layer {
            let animationOffset: CGFloat = 7.0
            let downward: CGFloat = contentView?.superview?.isFlipped == true ? animationOffset : -animationOffset
            let offset = switch dockPositionOverride ?? DockUtils.getDockPosition() {
            case .left: CGSize(width: -animationOffset, height: 0)
            case .right: CGSize(width: animationOffset, height: 0)
            default: CGSize(width: 0, height: downward)
            }

            let slide = CABasicAnimation(keyPath: "transform.translation")
            slide.fromValue = NSValue(size: offset)
            slide.toValue = NSValue(size: .zero)
            slide.isAdditive = true
            slide.duration = 0.175
            slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(slide, forKey: "slideIn")
        }
    }

    @MainActor
    private func performDisplay(
        appName: String,
        windows: [WindowInfo],
        mouseLocation: CGPoint?,
        mouseScreen: NSScreen?,
        dockItemElement: AXUIElement?,
        centeredHoverWindowState: PreviewStateCoordinator.WindowState?,
        onWindowTap: (() -> Void)?,
        bundleIdentifier: String?,
        dockPositionOverride: DockPosition? = nil,
        initialIndex: Int? = nil,
        dockItemFrameOverride: CGRect? = nil,
        renderStartTime: CFAbsoluteTime? = nil
    ) {
        HangDiagnostics.record("preview display started app=\(appName) windows=\(windows.count)")
        let elapsed = renderStartTime.map { (CFAbsoluteTimeGetCurrent() - $0) * 1000 } ?? 0
        DebugLogger.log("PreviewRender", details: "performDisplay start (+\(String(format: "%.1f", elapsed))ms)")

        var dockIconRect: CGRect?
        if let dockItemElement,
           let pos = try? dockItemElement.position(),
           let size = try? dockItemElement.size()
        {
            dockIconRect = CGRect(origin: pos, size: size)
        }

        let screen = mouseScreen ?? NSScreen.main!
        var finalEmbeddedContentType: EmbeddedContentType = .none
        var useBigStandaloneViewInstead = false
        var viewForBigStandalone: AnyView?
        let widgetsAreFiltered = WindowUtil.matchesAppFilters(
            bundleIdentifier: bundleIdentifier,
            appName: appName,
            filters: Defaults[.widgetAppFilters]
        )
        var startsNewPointerSession = !isVisible

        if let bundleId = bundleIdentifier, !widgetsAreFiltered {
            let actualAppContentType = getEmbeddedContentType(for: bundleId)

            switch actualAppContentType {
            case let .media(mediaBundleId):
                if Defaults[.showSpecialAppControls], Defaults[.enableMediaWidget] {
                    let hasRealWindows = windows.contains { !$0.isWindowlessApp }
                    let shouldUseBigControlsForNoValidWindows = Defaults[.showBigControlsWhenNoValidWindows] &&
                        (windows.isEmpty || !hasRealWindows)

                    if Defaults[.useEmbeddedMediaControls], !shouldUseBigControlsForNoValidWindows {
                        finalEmbeddedContentType = .media(bundleIdentifier: mediaBundleId)
                    } else {
                        useBigStandaloneViewInstead = true
                        viewForBigStandalone = AnyView(MediaControlsView(
                            appName: appName,
                            bundleIdentifier: mediaBundleId,
                            dockPosition: dockPositionOverride ?? DockUtils.getDockPosition(),
                            bestGuessMonitor: screen,
                            dockItemElement: dockItemElement,
                            isEmbeddedMode: false
                        ))
                    }
                }
            case let .calendar(calendarBundleId):
                if Defaults[.showSpecialAppControls], Defaults[.enableCalendarWidget] {
                    let hasRealWindows = windows.contains { !$0.isWindowlessApp }
                    let shouldUseBigControlsForNoValidWindows = Defaults[.showBigControlsWhenNoValidWindows] &&
                        (windows.isEmpty || !hasRealWindows)

                    if Defaults[.useEmbeddedMediaControls], !shouldUseBigControlsForNoValidWindows {
                        finalEmbeddedContentType = .calendar(bundleIdentifier: calendarBundleId)
                    } else {
                        useBigStandaloneViewInstead = true
                        viewForBigStandalone = AnyView(CalendarView(
                            appName: appName,
                            bundleIdentifier: calendarBundleId,
                            dockPosition: dockPositionOverride ?? DockUtils.getDockPosition(),
                            bestGuessMonitor: screen,
                            dockItemElement: dockItemElement,
                            isEmbeddedMode: false
                        ))
                    }
                }
            case .none:
                break
            }
        }

        if let dockItemElement {
            let newPID = windows.first?.app.processIdentifier ?? (try? dockItemElement.pid())
            if newPID != currentlyDisplayedPID {
                anchoredDockItem = nil
                startsNewPointerSession = true
            } else if anchoredDockItem?.element == dockItemElement, isVisible {
                // Same dock item element is already displayed and anchored.
                // Skip re-display to prevent position bouncing from duplicate AX notifications
                // (e.g. dock auto-hide at 0s). Window list updates arrive via mergeWindowsIfShowing.
                return
            }
            currentlyDisplayedPID = newPID
            if let dockIconRect {
                anchoredDockItem = (element: dockItemElement, iconRect: dockIconRect)
            }
        }

        let pointerSessionID = startsNewPointerSession
            ? windowSwitcherCoordinator.beginPointerInteractionSession()
            : nil

        if useBigStandaloneViewInstead, let viewToShow = viewForBigStandalone {
            performShowView(viewToShow, mouseLocation: mouseLocation, mouseScreen: screen, dockItemElement: dockItemElement, dockIconRect: dockIconRect, dockPositionOverride: dockPositionOverride, dockItemFrameOverride: dockItemFrameOverride)
        } else {
            performShowWindow(
                appName: appName,
                windows: windows,
                mouseLocation: mouseLocation,
                mouseScreen: screen,
                dockItemElement: dockItemElement,
                dockIconRect: dockIconRect,
                centeredHoverWindowState: centeredHoverWindowState,
                onWindowTap: onWindowTap,
                embeddedContentType: finalEmbeddedContentType,
                dockPositionOverride: dockPositionOverride,
                initialIndex: initialIndex,
                dockItemFrameOverride: dockItemFrameOverride,
                renderStartTime: renderStartTime
            )
        }

        if let pointerSessionID {
            DispatchQueue.main.async { [weak self] in
                self?.windowSwitcherCoordinator.armPointerInteractionSession(pointerSessionID)
            }
        }

        dockManager.preventDockHiding(centeredHoverWindowState != nil)
    }

    @MainActor
    private func performShowWindow(appName: String, windows: [WindowInfo], mouseLocation: CGPoint?,
                                   mouseScreen: NSScreen?, dockItemElement: AXUIElement?,
                                   dockIconRect: CGRect?,
                                   centeredHoverWindowState: PreviewStateCoordinator.WindowState? = nil,
                                   onWindowTap: (() -> Void)?,
                                   embeddedContentType: EmbeddedContentType = .none,
                                   dockPositionOverride: DockPosition? = nil, initialIndex: Int? = nil,
                                   dockItemFrameOverride: CGRect? = nil,
                                   renderStartTime: CFAbsoluteTime? = nil)
    {
        guard !windows.isEmpty || centeredHoverWindowState == .windowSwitcher else { return }

        let shouldCenterOnScreen = centeredHoverWindowState != .none

        let screen = mouseScreen ?? NSScreen.main!
        if centeredHoverWindowState == .fullWindowPreview,
           let windowInfo = windows.first
        {
            let targetScreen: NSScreen = if let windowPosition = try? windowInfo.axElement.position(),
                                            let windowScreen = windowPosition.screen()
            {
                windowScreen
            } else {
                screen
            }
            showFullPreviewWindow(for: windowInfo, on: targetScreen)
        } else {
            hideFullPreviewWindow()
            self.appName = appName
            let activeDockPosition = dockPositionOverride ?? DockUtils.getDockPosition()
            currentDockPosition = activeDockPosition

            windowSwitcherCoordinator.hasEmbeddedContent = embeddedContentType != .none
            windowSwitcherCoordinator.setWindows(windows, dockPosition: activeDockPosition, bestGuessMonitor: screen)

            if let initialIndex {
                let initialSelectionSource: PreviewStateCoordinator.SelectionInputSource =
                    (centeredHoverWindowState == .windowSwitcher || activeDockPosition == .cmdTab) ? .keyboard : .programmatic
                windowSwitcherCoordinator.setIndex(to: initialIndex, shouldScroll: false, source: initialSelectionSource)
            } else {
                windowSwitcherCoordinator.setIndex(to: -1, shouldScroll: false, source: .programmatic)
            }

            self.onWindowTap = onWindowTap

            updateContentViewSizeAndPosition(mouseLocation: mouseLocation, mouseScreen: screen, dockItemElement: dockItemElement, dockIconRect: dockIconRect, animated: !shouldCenterOnScreen,
                                             centerOnScreen: shouldCenterOnScreen, centeredHoverWindowState: centeredHoverWindowState,
                                             embeddedContentType: embeddedContentType, dockPositionOverride: dockPositionOverride,
                                             dockItemFrameOverride: dockItemFrameOverride, renderStartTime: renderStartTime)
        }
    }

    @MainActor
    func cycleWindows(goBackwards: Bool) {
        let coordinator = windowSwitcherCoordinator
        guard !coordinator.windows.isEmpty else { return }

        if coordinator.windowSwitcherActive, coordinator.hasActiveSearch {
            return
        }

        if goBackwards {
            coordinator.cycleBackward()
        } else {
            coordinator.cycleForward()
        }
    }

    @MainActor
    func selectAndBringToFrontCurrentWindow() {
        let coordinator = windowSwitcherCoordinator
        let currentIndex = coordinator.currIndex

        guard currentIndex >= 0, currentIndex < coordinator.windows.count else {
            hideWindow()
            return
        }

        let selectedWindow = coordinator.windows[currentIndex]
        selectedWindow.bringToFront()
        selectedWindow.warpMouseToCenterIfNeeded()

        hideWindow()
    }

    @MainActor
    func navigateWithArrowKey(direction: ArrowDirection, extendingSelection: Bool = false) {
        let coordinator = windowSwitcherCoordinator
        guard !coordinator.windows.isEmpty else { return }
        coordinator.reconcileSelectionRange()
        let extendsRange = extendingSelection && coordinator.keyboardSelectionPress != nil
        if !extendsRange { coordinator.endSelectionRange() }

        coordinator.hasMovedSinceOpen = false
        coordinator.initialHoverLocation = nil

        let threshold = if coordinator.windowSwitcherActive {
            Defaults[.windowSwitcherCompactThreshold]
        } else if currentDockPosition == .cmdTab {
            Defaults[.cmdTabCompactThreshold]
        } else {
            Defaults[.dockPreviewCompactThreshold]
        }
        let forcedCompact = Defaults[.disableImagePreview] || !hasScreenRecordingPermission
        let isListViewMode = forcedCompact || (threshold > 0 && coordinator.windows.count >= threshold)

        // In compact lists, horizontal and vertical arrows both move sequentially.
        if isListViewMode {
            let filteredIndices = coordinator.filteredWindowIndices()
            let indicesToUse = coordinator.hasActiveSearch ? filteredIndices : Array(coordinator.windows.indices)
            guard !indicesToUse.isEmpty else { return }

            let currentPos = indicesToUse.firstIndex(of: coordinator.currIndex) ?? 0
            let newPos: Int = switch direction {
            case .up, .left:
                currentPos > 0 ? currentPos - 1 : (extendsRange ? 0 : indicesToUse.count - 1)
            case .down, .right:
                extendsRange ? min(currentPos + 1, indicesToUse.count - 1) : (currentPos + 1) % indicesToUse.count
            }
            coordinator.setIndex(to: indicesToUse[newPos], source: .keyboard, extendingSelection: extendsRange)
            return
        }

        // Handle filtered navigation when search is active
        if coordinator.windowSwitcherActive, coordinator.hasActiveSearch {
            coordinator.navigateFiltered(direction: direction, extendingSelection: extendsRange)
            return
        }

        if coordinator.currIndex < 0 {
            coordinator.setIndex(to: 0, source: .keyboard)
            return
        }

        let dockPosition = DockUtils.getDockPosition()
        let newIndex = WindowPreviewHoverContainer.navigateWindowSwitcher(
            from: coordinator.currIndex,
            direction: direction,
            totalItems: coordinator.windows.count,
            dockPosition: dockPosition,
            isWindowSwitcherActive: coordinator.windowSwitcherActive,
            wraps: !extendsRange
        )
        coordinator.setIndex(to: newIndex, source: .keyboard, extendingSelection: extendsRange)
    }

    @MainActor
    @discardableResult
    func performActionOnCurrentWindow(action: WindowAction, preservePreviews: Bool = false) -> Bool {
        let coordinator = windowSwitcherCoordinator
        if action == .selectAllWindows {
            coordinator.selectAllDisplayedWindows()
            return false
        }
        if action == .autoTileSelectedWindows {
            guard let first = coordinator.checkedActionTargets(includingWindowlessApps: true)?.first ?? coordinator.getCurrentWindow() else { NSSound.beep(); return false }
            return performCheckedWindowAction(action, on: first, preservePreviews: preservePreviews, keyboard: true) ?? false
        }
        guard coordinator.currIndex >= 0, coordinator.currIndex < coordinator.windows.count else {
            return false
        }

        let window = coordinator.windows[coordinator.currIndex]
        if let dismissed = performCheckedWindowAction(action, on: window, preservePreviews: preservePreviews, keyboard: true) { return dismissed }
        if action.usesConfirmedSingleWindowAction(on: window) {
            return performSingleWindowAction(action, on: window, preservePreviews: preservePreviews, keyboard: true)
        }
        if action == .toggleWindowSelection {
            coordinator.toggleCheckedWindow(window)
            return false
        }
        if action != .none { cancelPreviewBatchAction() }
        let willQuitOnClose = action == .close &&
            !window.isWindowlessApp &&
            WindowUtil.shouldQuitAppOnWindowClose(processIdentifier: window.app.processIdentifier)
        let originalIndex = coordinator.currIndex
        let appPID = window.app.processIdentifier
        let existingAppWindowIDs = Set(
            coordinator.windows
                .filter { $0.app.processIdentifier == appPID && !$0.isWindowlessApp }
                .map(\.id)
        )
        let hiddenStateBeforeAction: Bool? = if action == .hide {
            window.isHidden
        } else {
            nil
        }
        var actionStateWindow = window
        if let hiddenStateBeforeAction {
            actionStateWindow.isHidden = hiddenStateBeforeAction
        }
        let category = action.postActionCategory(
            for: actionStateWindow,
            preferredWindows: coordinator.windows
        )
        let keepPreviewsOpen = preservePreviews || selectionKeepsPreviewsOpen || (category?.keepPreviewsOpen ?? (action != .openAppWindow))
        let closeAfterSuccess = action.closePreviewsOnlyAfterSuccess(
            for: actionStateWindow,
            category: category
        )
        let shouldClosePreviews = !keepPreviewsOpen
        let shouldForegroundMoveResize = Defaults[.moveResizeBringToForeground] &&
            category == .movingAndResizing
        let forceImmediateCloseForFullscreenTransitionPreAction = action.shouldForcePreviewCloseForFullscreenTransition(
            on: actionStateWindow,
            preferredWindows: coordinator.windows
        )
        let skipToggleFullscreenRefresh = action == .toggleFullScreen &&
            (keepPreviewsOpen || forceImmediateCloseForFullscreenTransitionPreAction)
        let shouldRunInPlaceRefresh = action.shouldScheduleAppRefresh &&
            !skipToggleFullscreenRefresh
        let expectedMinimizedState: Bool? = if action == .minimize {
            !window.isMinimized
        } else {
            nil
        }
        let expectedHiddenState = hiddenStateBeforeAction.map { !$0 }
        let expectedMinimizeAllState: Bool? = if action == .minimizeAllWindows {
            switch category {
            case .hiding:
                true
            case .unhiding:
                false
            default:
                nil
            }
        } else {
            nil
        }

        let activationDismissalSuppressionToken: UUID? = if action == .hide,
                                                            keepPreviewsOpen,
                                                            !forceImmediateCloseForFullscreenTransitionPreAction,
                                                            let hiddenStateBeforeAction
        {
            suppressNextActionDrivenActivationDismissal(
                for: window.app,
                wasHidden: hiddenStateBeforeAction
            )
        } else {
            nil
        }

        let feedback = ActionFeedbackController.begin(action, windows: [window], keyboard: true)
        let result = action.perform(
            on: actionStateWindow,
            keepPreviewOnQuit: false,
            preferredWindows: coordinator.windows,
            feedback: feedback
        )
        if case .noChange = result {
            cancelActionDrivenActivationDismissalSuppression(token: activationDismissalSuppressionToken)
        }
        coordinator.scheduleActiveFocusedWindowRefresh()

        var actionConfirmedSuccess = false
        switch result {
        case .dismissed:
            actionConfirmedSuccess = !action.requiresDeferredSuccessWatcher || !closeAfterSuccess || !shouldClosePreviews
        case let .windowUpdated(updatedWindow):
            actionConfirmedSuccess = true
            if action == .hide {
                coordinator.updateHiddenStateForApp(
                    processIdentifier: updatedWindow.app.processIdentifier,
                    isHidden: updatedWindow.isHidden
                )
            } else {
                coordinator.updateWindow(at: originalIndex, with: updatedWindow)
            }
        case .noChange:
            break
        }

        if action == .minimize || action == .hide || action == .minimizeAllWindows {
            coordinator.scheduleVisibilityStateSync(processIdentifier: window.app.processIdentifier)
        }

        if shouldRunInPlaceRefresh {
            scheduleInPlaceActionRefresh(
                for: window.app,
                forceImageRefresh: action == .openNewWindow,
                previousWindowIDs: action == .openNewWindow ? existingAppWindowIDs : nil,
                sourceWindowID: action == .openNewWindow ? window.id : nil
            )
        }

        if shouldForegroundMoveResize,
           actionConfirmedSuccess,
           WindowUtil.canBringWindowToFrontWithoutSpaceSwitch(window)
        {
            if preservePreviews,
               NSWorkspace.shared.frontmostApplication?.processIdentifier != window.app.processIdentifier
            {
                _ = suppressNextActionDrivenActivationDismissal(for: window.app.processIdentifier)
            }
            window.bringToFront()
        }

        if !preservePreviews, action.shouldForcePreviewCloseAfterAction(
            predictedTransition: forceImmediateCloseForFullscreenTransitionPreAction,
            hiddenStateBeforeAction: hiddenStateBeforeAction,
            result: result
        ) {
            hideWindow()
            return true
        }

        guard shouldClosePreviews else { return false }

        if action == .close || action.isQuitAction {
            scheduleFailedClosingFocusNotification(
                action: action,
                window: window,
                willQuitOnClose: willQuitOnClose
            )
            hideWindow()
            return true
        }

        if !closeAfterSuccess {
            if action == .hide, case .noChange = result {
                return false
            }
            hideWindow()
            return true
        }

        if action == .minimize || action == .hide || action == .minimizeAllWindows {
            scheduleVisibilityDismissConfirmation(
                action: action,
                window: window,
                targetMinimizedState: expectedMinimizedState,
                targetHiddenState: expectedHiddenState,
                targetMinimizeAllState: expectedMinimizeAllState
            )
            return false
        }

        if actionConfirmedSuccess {
            hideWindow()
            return true
        }

        switch action {
        case .openNewWindow:
            scheduleNewWindowDismissConfirmation(
                window: window,
                previousWindowIDs: existingAppWindowIDs
            )
        case .close:
            if willQuitOnClose {
                scheduleAppTerminationDismissConfirmation(window: window, sourceAction: .close)
            } else if window.isWindowlessApp {
                scheduleCloseAllDismissConfirmation(window: window, sourceAction: .close)
            } else {
                scheduleWindowClosureDismissConfirmation(window: window)
            }
        case .quit, .forceQuit:
            scheduleAppTerminationDismissConfirmation(window: window, sourceAction: action)
        case .closeAllWindows:
            scheduleCloseAllDismissConfirmation(window: window, sourceAction: .closeAllWindows)
        default:
            break
        }

        return false
    }

    @MainActor
    // nil delegates to single-window handling; the Bool reports immediate preview dismissal.
    func performCheckedWindowAction(_ action: WindowAction, on initiator: WindowInfo, preservePreviews: Bool = false, keyboard: Bool = false) -> Bool? {
        guard action != .toggleWindowSelection, action != .selectAllWindows, action != .none,
              let selectedTargets = action == .autoTileSelectedWindows
              ? windowSwitcherCoordinator.checkedActionTargets(includingWindowlessApps: true) ?? [initiator]
              : windowSwitcherCoordinator.checkedActionTargets(for: initiator, includingWindowlessApps: true)
        else { return nil }
        let hasWindowlessTargets = selectedTargets.contains(where: \.isWindowlessApp)
        let targets = selectedTargets.filter { action.appliesToSelectedWindow($0) }
        guard !targets.isEmpty else { return false }
        guard targets.count > 1 || action == .autoTileSelectedWindows || hasWindowlessTargets else { return nil }
        if action == .toggleFullScreen, !targets.contains(where: { $0.isFullscreen == true }) { return initiator.isWindowlessApp ? false : nil }
        if action == .bringToCurrentSpace {
            let displays = WindowSpaces.managedDisplays()
            guard let spaceID = WindowSpaces.currentManagedSpaceID(mouseLocation: NSEvent.mouseLocation),
                  let destination = WindowSpaces.destination(forSpaceID: spaceID, in: displays)
            else { NSSound.beep(); return false }
            _ = performCheckedSpaceMove(initiator, to: destination, dismissPreviews: { [weak self] in self?.hideWindow() })
            return false
        }

        return performPreviewBatchAction(action, on: targets, initiator: initiator, preservePreviews: preservePreviews, keyboard: keyboard)
    }

    @MainActor
    @discardableResult
    func performSingleWindowAction(_ action: WindowAction, on window: WindowInfo, preservePreviews: Bool = false, keyboard: Bool = false) -> Bool {
        let targets = action == .closeAllWindows
            ? WindowUtil.readCachedWindows(for: window.app.processIdentifier).filter { !$0.isWindowlessApp }
            : [window]
        return performPreviewBatchAction(action, on: targets, initiator: window, preservePreviews: preservePreviews, keyboard: keyboard,
                                         allowFullscreenEntry: action == .toggleFullScreen)
    }

    @MainActor
    func performAppHeaderAction(_ action: WindowAction) {
        guard action == .closeAllWindows || action == .minimizeAllWindows,
              let app = windowSwitcherCoordinator.windows.first?.app
        else { return }
        let targets = WindowUtil.readCachedWindows(for: app.processIdentifier)
            .filter { !$0.isWindowlessApp && !$0.app.isTerminated }
        guard let initiator = targets.first else { NSSound.beep(); return }
        _ = performPreviewBatchAction(action, on: targets, initiator: initiator, usePreviews: false)
    }

    @MainActor
    func tileSelectionSummaryWindows() {
        guard let targets = windowSwitcherCoordinator.checkedActionTargets() else { NSSound.beep(); return }
        guard let initiator = targets.first else { return }
        _ = performPreviewBatchAction(.autoTileSelectedWindows, on: targets, initiator: initiator)
    }

    @MainActor
    private func performPreviewBatchAction(_ action: WindowAction, on targets: [WindowInfo], initiator: WindowInfo,
                                           preservePreviews: Bool = false, keyboard: Bool = false, usePreviews: Bool = true,
                                           allowFullscreenEntry: Bool = false) -> Bool
    {
        let resolvedTargets = action.previewTargets(from: targets, allowFullscreenEntry: allowFullscreenEntry)
        let targetState = action.batchTargetState(for: resolvedTargets)
        let request = WindowUtil.beginPreviewActionRequest(action, windows: targets, resolvedTargets: resolvedTargets)
        let feedback = ActionFeedbackController.begin(action, windows: targets, keyboard: keyboard || NSApp.currentEvent?.type == .keyDown, usePreviews: usePreviews, resolvedTargets: resolvedTargets)
        guard !request.admitted.isEmpty else {
            let applicable = targets.filter {
                action.appliesToSelectedWindow($0) && (targets.count == 1 || action.isSupported(for: $0))
            }
            let autoTile = action.autoTilingDirection(windowCount: applicable.count, fillActionsAutoTile: Defaults[.fillActionsAutoTileSelection]) != nil
            let failed = WindowUtil.PreviewBatchResult(failed: resolvedTargets.isEmpty && !autoTile ? applicable.map(PreviewWindowIdentity.init) : request.rejected)
            feedback?.finish(failed)
            reportBatchFailures(failed.failed, action: action.rawValue)
            return false
        }
        let admittedTargets = resolvedTargets.filter { request.contains(PreviewWindowIdentity($0)) }
        previewBatchTask?.cancel()
        previewBatchTask = nil
        let token = UUID()
        previewBatchToken = token
        let originalContent = contentView
        let category = targetState.map { $0 ? WindowAction.PostActionCategory.hiding : .unhiding }
            ?? action.postActionCategory(for: initiator, preferredWindows: targets)
        let keepOpen = preservePreviews || selectionKeepsPreviewsOpen || (category?.keepPreviewsOpen ?? (action != .openAppWindow))
        let revealsWindows = action == .openAppWindow || category == .unhiding
        var needsTransition = !preservePreviews && ((action == .toggleFullScreen && !allowFullscreenEntry) ||
            (revealsWindows && admittedTargets.contains { WindowUtil.activationMaySwitchSpaces(for: $0) }))
        var suppressionToken: UUID?
        if needsTransition {
            hideWindow()
        }
        windowSwitcherCoordinator.consumeWindowlessSelection(in: admittedTargets)
        let beforeChange: (@MainActor (Bool) -> Bool)? = if allowFullscreenEntry || action == .hide {
            { [weak self] switchesSpaces in
                guard !Task.isCancelled else { return false }
                guard let self, previewBatchToken == token else { return true }
                guard contentView === originalContent || !isVisible else { return true }
                if action == .hide, keepOpen, !needsTransition {
                    suppressionToken = suppressNextActionDrivenActivationDismissal(for: (admittedTargets.first ?? initiator).app, wasHidden: category == .unhiding)
                }
                if switchesSpaces, !preservePreviews {
                    needsTransition = true
                    hideWindow()
                }
                return true
            }
        } else { nil }
        let task = Task { @MainActor [weak self] in
            defer {
                request.finish()
                self?.previewActionTasks.removeValue(forKey: token)
                if self?.previewBatchToken == token { self?.previewBatchTask = nil; self?.previewBatchToken = nil }
            }
            let result = await WindowUtil.performPreviewBatchAction(action, on: targets, allowFullscreenEntry: allowFullscreenEntry, feedback: feedback,
                                                                    request: request, targetState: targetState, resolvedTargets: resolvedTargets,
                                                                    beforeActionChange: beforeChange)
            guard !Task.isCancelled, let self, previewBatchToken == token else { return }
            let succeededIdentities = Set(result.succeeded.map(PreviewWindowIdentity.init))
            let focusTarget = revealsWindows ? targets.first(where: { succeededIdentities.contains(PreviewWindowIdentity($0)) }) ?? result.succeeded.first : nil
            for identity in request.admitted where focusTarget.map(PreviewWindowIdentity.init) != identity {
                request.finish(identity)
            }
            // Mutations are settled; newer actions may cancel remaining focus/presentation work.
            previewBatchTask = previewActionTasks[token]?.task
            reportBatchFailures(result.failed, action: action.rawValue)
            if result.succeeded.isEmpty { cancelActionDrivenActivationDismissalSuppression(token: suppressionToken) }
            var refreshedApps = Set<pid_t>()
            for window in admittedTargets where refreshedApps.insert(window.app.processIdentifier).inserted {
                if action == .minimize || action == .minimizeAllWindows {
                    windowSwitcherCoordinator.scheduleVisibilityStateSync(processIdentifier: window.app.processIdentifier)
                } else if action == .close || action.isQuitAction || action == .closeAllWindows || action == .openNewWindow ||
                    (targets.count == 1 && (action == .hide || action == .openAppWindow))
                {
                    scheduleInPlaceActionRefresh(for: window.app, forceImageRefresh: action == .openNewWindow)
                }
            }
            let samePresentation = contentView === originalContent && isVisible
            guard samePresentation || (needsTransition && !isVisible) else { return }
            if request.mayForeground, let first = focusTarget {
                let refreshed = WindowUtil.readCachedWindows(for: first.app.processIdentifier).first { $0.id == first.id } ?? first
                if !keepOpen || needsTransition || WindowUtil.canBringWindowToFrontWithoutSpaceSwitch(refreshed) {
                    if !keepOpen || needsTransition { hideWindow() }
                    else if action == .hide || action == .openAppWindow { _ = suppressNextActionDrivenActivationDismissal(for: refreshed.app.processIdentifier) }
                    let activated = await refreshed.bringToFrontConfirmed()
                    guard !Task.isCancelled, previewBatchToken == token else { return }
                    if !activated { reportBatchFailures([PreviewWindowIdentity(first)], action: "activateAfterBatch") }
                }
            }
            guard !Task.isCancelled, previewBatchToken == token else { return }
            if !keepOpen, !result.succeeded.isEmpty, samePresentation { hideWindow() }
            windowSwitcherCoordinator.scheduleActiveFocusedWindowRefresh()
        }
        previewActionTasks[token] = (request, task)
        request.onSuperseded { task.cancel() }
        return needsTransition
    }

    @MainActor
    @discardableResult
    func performCheckedSpaceMove(_ initiator: WindowInfo, to destination: ManagedSpaceDestination,
                                 dismissPreviews: (() -> Void)?, keyboard: Bool = false) -> Bool
    {
        guard let targets = windowSwitcherCoordinator.checkedActionTargets(for: initiator) else { return false }
        guard !targets.isEmpty else { return true }
        guard targets.count > 1 || initiator.isWindowlessApp || windowSwitcherCoordinator.checkedWindowCount > targets.count else { return false }
        let request = WindowUtil.beginPreviewActionRequest(.bringToCurrentSpace, windows: targets)
        let feedback = ActionFeedbackController.begin(.bringToCurrentSpace, windows: targets, keyboard: keyboard || NSApp.currentEvent?.type == .keyDown, title: String(localized: "Move to Space \(destination.space.number)"))
        guard !request.admitted.isEmpty else { feedback?.finishRemaining(.failed); return true }
        previewBatchTask?.cancel()
        let token = UUID()
        previewBatchToken = token
        let originalContent = contentView
        let followsDestination = Defaults[.switchToDestinationSpaceAfterMoving]
        let task = WindowActionRequest.$current.withValue(request) { Task { @MainActor [weak self] in
            defer { request.finish(); self?.previewActionTasks.removeValue(forKey: token) }
            defer { feedback?.finishRemaining(.cancelled) }
            guard let self else { return }
            defer {
                if previewBatchToken == token { previewBatchTask = nil; previewBatchToken = nil }
            }
            var succeeded: [WindowInfo] = []
            var failed: [PreviewWindowIdentity] = []
            var pending = Set<PreviewWindowIdentity>()
            var cancellations: [@MainActor () -> Void] = []
            var requestedMove = false
            defer { for cancel in cancellations {
                cancel()
            } }
            let topology = WindowSpaces.managedDisplays()
            for window in targets {
                let identity = PreviewWindowIdentity(window)
                guard request.contains(identity) else { failed.append(identity); feedback?.finish(identity, .failed); continue }
                let sourceError = await WindowSpaces.validateMoveSourceConfirmed(window, in: topology)
                guard !Task.isCancelled else { return }
                if sourceError == nil,
                   WindowSpaces.sourceSpaceIDs(for: window).contains(destination.space.id), destination.space.kind == .desktop
                {
                    succeeded.append(window)
                    continue
                }
                requestedMove = true
                pending.insert(identity)
                let cancel = WindowUtil.performConfirmedSpaceMove(window, to: destination, dismissPreviews: nil,
                                                                  switchToDestination: false,
                                                                  isRequestActive: { request.contains(identity) })
                { success in
                    pending.remove(identity)
                    feedback?.finish(identity, success ? .completed : .failed)
                    if success { succeeded.append(window) } else { failed.append(identity) }
                }
                if let cancel { cancellations.append(cancel) }
            }
            guard requestedMove else {
                feedback?.finishRemaining(.failed)
                reportBatchFailures(targets.map(PreviewWindowIdentity.init), action: "moveToCurrentDestination")
                return
            }
            for window in succeeded {
                feedback?.finish(PreviewWindowIdentity(window), .completed)
            }
            for _ in 0 ..< 25 where !pending.isEmpty {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            }
            guard !Task.isCancelled else { return }
            failed.append(contentsOf: pending)
            for identity in pending {
                feedback?.finish(identity, .failed)
            }
            reportBatchFailures(failed, action: "moveToSpace")
            let succeededIdentities = Set(succeeded.map(PreviewWindowIdentity.init))
            if request.mayForeground, previewBatchToken == token, followsDestination, !succeeded.isEmpty, isVisible, contentView === originalContent,
               let first = targets.first(where: { succeededIdentities.contains(PreviewWindowIdentity($0)) })
            {
                dismissPreviews?()
                var moved = WindowUtil.readCachedWindows(for: first.app.processIdentifier).first { $0.id == first.id } ?? first
                var canFocus = true
                if moved.app.isHidden { canFocus = await WindowUtil.setHiddenStateConfirmed(for: moved.app, isHidden: false) }
                if canFocus, moved.isMinimized {
                    canFocus = await !(WindowUtil.setMinimizedWindowsConfirmed([moved], isMinimized: false)).isEmpty
                    if canFocus { moved.isMinimized = false }
                }
                guard !Task.isCancelled else { return }
                if canFocus { canFocus = await moved.bringToFrontConfirmed() }
                if !canFocus { reportBatchFailures([PreviewWindowIdentity(first)], action: "followSpace") }
            }
            guard !Task.isCancelled else { return }
        } }
        previewActionTasks[token] = (request, task)
        request.onSuperseded { task.cancel() }
        return true
    }

    private func reportBatchFailures(_ failures: [PreviewWindowIdentity], action: String) {
        guard !failures.isEmpty else { return }
        DebugLogger.log("PreviewBatchAction", details: "\(action) failed for " + failures.map { "\($0.pid):\($0.windowID)" }.joined(separator: ", "))
        NSSound.beep()
    }

    func cancelPreviewBatchAction() {
        previewBatchTask?.cancel()
        previewBatchTask = nil
        previewBatchToken = nil
    }

    @MainActor
    @discardableResult
    func performActionOnCmdTabHighlightedApps(
        action: WindowAction,
        apps: [NSRunningApplication],
        preservePreviews: Bool = false, feedback: ActionFeedbackHandle? = nil
    ) -> Bool {
        guard action == .close || action == .minimize || action.isQuitAction else { return false }

        var seenPIDs = Set<pid_t>()
        let targetApps = apps.filter {
            !$0.isTerminated && seenPIDs.insert($0.processIdentifier).inserted
        }
        guard !targetApps.isEmpty else { return false }

        if action == .close { return closeCmdTabHighlightedApps(targetApps, preservePreviews: preservePreviews) }
        if action == .minimize {
            let targets = targetApps.flatMap { cmdTabActionWindows(for: $0) }
            guard let initiator = targets.first else { return false }
            return performPreviewBatchAction(.minimizeAllWindows, on: targets, initiator: initiator,
                                             preservePreviews: preservePreviews, keyboard: true, usePreviews: false)
        }

        let targets = targetApps.map { ($0, WindowInfo.windowlessEntry(for: $0)) }
        let keepPreviewsOpen = preservePreviews || WindowAction.PostActionCategory.closing.keepPreviewsOpen

        let feedback = feedback ?? ActionFeedbackController.begin(action, windows: targets.map(\.1), keyboard: true, usePreviews: false)
        if WindowActionRequest.current == nil {
            let request = WindowActionOwnership.shared.begin(targets.map { PreviewWindowIdentity($0.1) }, apps: Set(targetApps.map(\.processIdentifier)), protect: true)
            guard !request.admitted.isEmpty else { feedback?.finishRemaining(.failed); return false }
            if request.predecessorsResolved {
                defer { request.finish() }
                return WindowActionRequest.$current.withValue(request) {
                    performActionOnCmdTabHighlightedApps(action: action, apps: targetApps, preservePreviews: preservePreviews, feedback: feedback)
                }
            }
            let session = windowSwitcherCoordinator.pointerInteractionSessionID
            let task = Task { @MainActor [weak self] in
                defer { request.finish(); feedback?.finishRemaining(.cancelled); self?.previewActionTasks.removeValue(forKey: request.token) }
                await request.waitForPredecessors()
                guard !Task.isCancelled, let self else { return }
                _ = WindowActionRequest.$current.withValue(request) {
                    performActionOnCmdTabHighlightedApps(action: action, apps: targetApps,
                                                         preservePreviews: preservePreviews || windowSwitcherCoordinator.pointerInteractionSessionID != session,
                                                         feedback: feedback)
                }
            }
            previewActionTasks[request.token] = (request, task)
            request.onSuperseded { task.cancel() }
            return false
        }
        var accepted = false
        for (app, entry) in targets {
            let result = action.perform(
                on: entry,
                keepPreviewOnQuit: false
            )
            if case .noChange = result {
                feedback?.finish(PreviewWindowIdentity(entry), .failed)
                continue
            } else {
                accepted = true
                feedback?.finish(PreviewWindowIdentity(entry), .requested)
            }
            if action.shouldScheduleAppRefresh {
                scheduleInPlaceActionRefresh(for: app)
            }
        }
        guard accepted else { return false }
        windowSwitcherCoordinator.scheduleActiveFocusedWindowRefresh()

        guard !keepPreviewsOpen else { return false }

        for (_, entry) in targets {
            scheduleFailedClosingFocusNotification(
                action: action,
                window: entry,
                willQuitOnClose: false
            )
        }
        hideWindow()
        return true
    }

    @MainActor
    private func cmdTabActionWindows(for app: NSRunningApplication) -> [WindowInfo] {
        let rows = windowSwitcherCoordinator.windows.filter { $0.app.processIdentifier == app.processIdentifier && !$0.isWindowlessApp }
        return rows.isEmpty ? WindowUtil.readCachedWindows(for: app.processIdentifier).filter { !$0.isWindowlessApp } : rows
    }

    @MainActor
    private func closeCmdTabHighlightedApps(_ apps: [NSRunningApplication], preservePreviews: Bool) -> Bool {
        let candidates = apps.map { app in
            (app: app, entry: WindowInfo.windowlessEntry(for: app), windows: cmdTabActionWindows(for: app))
        }
        let requests = candidates.filter { WindowAction.close.isSupported(for: $0.entry) }
        let feedbackTargets = candidates.flatMap(\.windows)
        let feedback = ActionFeedbackController.begin(.closeAllWindows, windows: feedbackTargets, keyboard: true, usePreviews: false, resolvedTargets: requests.flatMap(\.windows))
        guard !requests.isEmpty else { feedback?.finishRemaining(.failed); return false }
        let ownership = WindowActionOwnership.shared.begin(requests.map { PreviewWindowIdentity($0.entry) }, apps: Set(requests.map(\.app.processIdentifier)), protect: true)
        guard !ownership.admitted.isEmpty else { feedback?.finishRemaining(.failed); return false }
        let keepOpen = preservePreviews || WindowAction.PostActionCategory.closing.keepPreviewsOpen
        let sessionID = windowSwitcherCoordinator.pointerInteractionSessionID
        previewBatchTask?.cancel()
        let token = UUID()
        previewBatchToken = token
        let task = WindowActionRequest.$current.withValue(ownership) { Task { @MainActor [weak self] in
            defer { ownership.finish(); self?.previewActionTasks.removeValue(forKey: token) }
            defer {
                feedback?.finishRemaining(.cancelled)
                if let self, previewBatchToken == token { previewBatchTask = nil; previewBatchToken = nil }
            }
            for request in requests {
                guard !Task.isCancelled else { return }
                guard ownership.contains(PreviewWindowIdentity(request.entry)) else {
                    for window in request.windows {
                        feedback?.finish(PreviewWindowIdentity(window), .failed)
                    }
                    continue
                }
                // A failed Close may still fall back to normal Quit. Settle it after that decision.
                let result = await WindowUtil.closeWindows(request.windows, feedback: feedback, settleFailures: false)
                guard !Task.isCancelled else { return }
                let quitAccepted = result.succeeded.isEmpty &&
                    WindowUtil.shouldQuitAppOnWindowClose(processIdentifier: request.app.processIdentifier) && request.entry.quit(force: false)
                for identity in result.failed {
                    feedback?.finish(identity, quitAccepted ? .requested : .failed)
                }
                if let self, previewBatchToken == token,
                   windowSwitcherCoordinator.pointerInteractionSessionID == sessionID, isVisible
                { scheduleInPlaceActionRefresh(for: request.app) }
            }
            guard !Task.isCancelled, let self, previewBatchToken == token,
                  windowSwitcherCoordinator.pointerInteractionSessionID == sessionID, isVisible
            else { return }
            windowSwitcherCoordinator.scheduleActiveFocusedWindowRefresh()
            if !keepOpen {
                for request in requests {
                    scheduleFailedClosingFocusNotification(action: .close, window: request.entry,
                                                           willQuitOnClose: WindowUtil.shouldQuitAppOnWindowClose(processIdentifier: request.app.processIdentifier))
                }
                hideWindow()
            }
        } }
        previewActionTasks[token] = (ownership, task)
        ownership.onSuperseded { task.cancel() }
        return false
    }

    private func scheduleInPlaceActionRefresh(
        for app: NSRunningApplication,
        forceImageRefresh: Bool = false,
        previousWindowIDs: Set<CGWindowID>? = nil,
        sourceWindowID: CGWindowID? = nil
    ) {
        let pid = app.processIdentifier

        startDeferredRefreshTask(pid: pid, purpose: "in-place-action-refresh") { [weak self] in
            guard let self else { return }
            for delay in WindowAction.inPlaceRefreshDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await WindowUtil.updateNewWindowsForApp(app)
                guard !Task.isCancelled else { return }
                if forceImageRefresh {
                    await WindowUtil.refreshCachedWindowImagesAfterOpenNewWindow(
                        for: pid,
                        previousWindowIDs: previousWindowIDs ?? [],
                        sourceWindowID: sourceWindowID
                    )
                    guard !Task.isCancelled else { return }
                }
                refreshSwitcherRowsForPID(pid)
                await MainActor.run {
                    self.windowSwitcherCoordinator.scheduleActiveFocusedWindowRefresh()
                }
            }
        }
    }

    @MainActor
    private func refreshSwitcherRowsForPID(_ pid: pid_t) {
        let runningApp = NSRunningApplication(processIdentifier: pid)
        let canAddWindowlessEntry = (runningApp?.isTerminated == false)
        var fresh = WindowUtil.readCachedWindows(for: pid)
        if !canAddWindowlessEntry {
            fresh = []
        } else {
            fresh = WindowUtil.collapseNativeTabsIfNeeded(fresh)
        }

        if currentDockPosition == .cmdTab {
            let hasOtherInstanceRows = windowSwitcherCoordinator.windows.contains {
                !$0.isWindowlessApp &&
                    $0.app.processIdentifier != pid &&
                    $0.app.bundleIdentifier == runningApp?.bundleIdentifier
            }
            fresh = if canAddWindowlessEntry, let runningApp {
                WindowUtil.cmdTabPreviewWindows(
                    from: fresh,
                    app: runningApp,
                    allowWindowlessPlaceholder: !hasOtherInstanceRows
                ) ?? []
            } else {
                []
            }
            if fresh.isEmpty, !hasOtherInstanceRows {
                hideWindow()
                return
            }
        } else {
            if Defaults[.showWindowsFromCurrentSpaceOnlyInSwitcher] {
                fresh = WindowUtil.filterWindowsByCurrentSpace(fresh)
            }
            if Defaults[.showWindowsFromCurrentMonitorOnlyInSwitcher] {
                fresh = WindowUtil.filterWindowsByCurrentMonitor(fresh)
            }
            if !Defaults[.includeHiddenWindowsInSwitcher] {
                fresh = fresh.filter { !$0.isEffectivelyHiddenForUI && !$0.isMinimized }
            }
            if canAddWindowlessEntry, fresh.isEmpty, Defaults[.showWindowlessAppsInSwitcher], let runningApp {
                fresh = [WindowInfo.windowlessEntry(for: runningApp)]
            }
        }

        let dockPosition: DockPosition = DockObserver.isCmdTabSwitcherActive ? .cmdTab : DockUtils.getDockPosition()
        let mergeResult = windowSwitcherCoordinator.mergeRefreshedRowsForPID(
            pid,
            replacementRows: fresh,
            dockPosition: dockPosition,
            bestGuessMonitor: NSScreen.main ?? NSScreen.screens.first
        )

        refreshDisplayedFullPreviewIfNeeded(sourceWindows: mergeResult.mergedWindows)
    }

    @MainActor
    private func refreshDisplayedFullPreviewIfNeeded(sourceWindows: [WindowInfo]? = nil) {
        guard windowSwitcherCoordinator.fullWindowPreviewActive else { return }
        let windows = sourceWindows ?? windowSwitcherCoordinator.windows
        let selectedIndex = windowSwitcherCoordinator.currIndex
        guard selectedIndex >= 0, selectedIndex < windows.count else { return }
        let selectedWindow = windows[selectedIndex]
        guard !selectedWindow.isWindowlessApp else { return }

        guard let fallbackScreen = NSScreen.main ?? NSScreen.screens.first else { return }
        let targetScreen: NSScreen = if let position = try? selectedWindow.axElement.position(),
                                        let resolved = position.screen()
        {
            resolved
        } else {
            fallbackScreen
        }
        showFullPreviewWindow(for: selectedWindow, on: targetScreen)
    }

    private func scheduleAppTerminationDismissConfirmation(window: WindowInfo, sourceAction: WindowAction) {
        let pid = window.app.processIdentifier
        let app = window.app

        startDeferredActionWatcher(pid: pid, action: sourceAction) { @MainActor [weak self] in
            guard let self else { return }
            for delay in WindowAction.deferredConfirmationPollDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard shouldRunDeferredWatchers else { return }
                let appStillVisible = windowSwitcherCoordinator.windows.contains { $0.app.processIdentifier == pid }
                if app.isTerminated || NSRunningApplication(processIdentifier: pid) == nil || !appStillVisible {
                    hideWindow()
                    return
                }
            }
        }
    }

    private func scheduleFailedClosingFocusNotification(
        action: WindowAction,
        window: WindowInfo,
        willQuitOnClose: Bool
    ) {
        let app = window.app
        let pid = app.processIdentifier
        let windowID = window.id
        let isWindowless = window.isWindowlessApp

        startDeferredActionWatcher(
            pid: pid,
            action: action,
            purpose: "failed-focus"
        ) { @MainActor [weak self] in
            guard let self else { return }
            var missingWindowConfirmations = 0
            var emptyWindowSetConfirmations = 0

            for delay in WindowAction.deferredConfirmationPollDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard shouldRunDeferredWatchers else { return }

                if action.isQuitAction || willQuitOnClose {
                    if app.isTerminated || NSRunningApplication(processIdentifier: pid) == nil {
                        return
                    }
                    continue
                }

                await WindowUtil.updateNewWindowsForApp(app)
                guard shouldRunDeferredWatchers else { return }

                let cached = WindowUtil.readCachedWindows(for: pid).filter { !$0.isWindowlessApp }
                if isWindowless {
                    if cached.isEmpty {
                        emptyWindowSetConfirmations += 1
                        if emptyWindowSetConfirmations >= 2 {
                            return
                        }
                    } else {
                        emptyWindowSetConfirmations = 0
                    }
                    continue
                }

                let stillExists = cached.contains { $0.id == windowID && $0.app.processIdentifier == pid }
                if !stillExists {
                    missingWindowConfirmations += 1
                    if missingWindowConfirmations >= 2 {
                        return
                    }
                } else {
                    missingWindowConfirmations = 0
                }
            }

            guard shouldRunDeferredWatchers else { return }
            guard let runningApp = NSRunningApplication(processIdentifier: pid), !runningApp.isTerminated else { return }

            runningApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

            let cachedWindows = WindowUtil.readCachedWindows(for: pid).filter { !$0.isWindowlessApp }
            if !isWindowless, let exactMatch = cachedWindows.first(where: { $0.id == windowID }) {
                exactMatch.bringToFront()
            } else if let firstWindow = cachedWindows.first {
                firstWindow.bringToFront()
            }
        }
    }

    private func scheduleVisibilityDismissConfirmation(
        action: WindowAction,
        window: WindowInfo,
        targetMinimizedState: Bool?,
        targetHiddenState: Bool?,
        targetMinimizeAllState: Bool?
    ) {
        let pid = window.app.processIdentifier
        let app = window.app

        startDeferredActionWatcher(pid: pid, action: action) { @MainActor [weak self] in
            guard let self else { return }
            for delay in WindowAction.deferredConfirmationPollDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard shouldRunDeferredWatchers else { return }
                await WindowUtil.updateNewWindowsForApp(app)
                guard shouldRunDeferredWatchers else { return }

                var confirmed = false
                switch action {
                case .minimize:
                    if let targetMinimizedState {
                        confirmed = await window.readMinimizedState() == targetMinimizedState
                    }
                case .hide:
                    if let targetHiddenState {
                        confirmed = app.isHidden == targetHiddenState
                    }
                case .minimizeAllWindows:
                    if let targetMinimizeAllState {
                        let nonFullscreen = WindowUtil.readCachedWindows(for: pid).filter {
                            !$0.isWindowlessApp && $0.isFullscreen != true
                        }
                        if !nonFullscreen.isEmpty {
                            if targetMinimizeAllState {
                                confirmed = nonFullscreen.allSatisfy(\.isMinimized)
                            } else {
                                confirmed = nonFullscreen.allSatisfy { !$0.isMinimized }
                            }
                        }
                    }
                default:
                    break
                }

                guard !Task.isCancelled, shouldRunDeferredWatchers else { return }
                if confirmed {
                    hideWindow()
                    return
                }
            }
        }
    }

    private func scheduleWindowClosureDismissConfirmation(window: WindowInfo) {
        let windowID = window.id
        let pid = window.app.processIdentifier
        let app = window.app

        startDeferredActionWatcher(pid: pid, action: .close) { @MainActor [weak self] in
            guard let self else { return }
            for delay in WindowAction.deferredConfirmationPollDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard shouldRunDeferredWatchers else { return }
                await WindowUtil.updateNewWindowsForApp(app)
                let cached = WindowUtil.readCachedWindows(for: pid)
                let stillExists = cached.contains { $0.id == windowID && $0.app.processIdentifier == pid }
                let stillVisible = windowSwitcherCoordinator.windows.contains { $0.id == windowID && $0.app.processIdentifier == pid }
                if !stillExists || !stillVisible {
                    hideWindow()
                    return
                }
            }
        }
    }

    private func scheduleCloseAllDismissConfirmation(window: WindowInfo, sourceAction: WindowAction) {
        let pid = window.app.processIdentifier
        let app = window.app

        startDeferredActionWatcher(pid: pid, action: sourceAction) { @MainActor [weak self] in
            guard let self else { return }
            for delay in WindowAction.deferredConfirmationPollDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard shouldRunDeferredWatchers else { return }
                await WindowUtil.updateNewWindowsForApp(app)
                let cached = WindowUtil.readCachedWindows(for: pid).filter { !$0.isWindowlessApp }
                let visibleNonWindowlessCount = windowSwitcherCoordinator.windows.filter { $0.app.processIdentifier == pid && !$0.isWindowlessApp }.count
                if cached.isEmpty || visibleNonWindowlessCount == 0 {
                    hideWindow()
                    return
                }
            }
        }
    }

    private func scheduleNewWindowDismissConfirmation(window: WindowInfo, previousWindowIDs: Set<CGWindowID>) {
        let pid = window.app.processIdentifier
        let app = window.app
        let originalWindowID = window.id
        let originalWindowTitle = window.windowName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hadNoTrackedWindowsBefore = previousWindowIDs.isEmpty

        startDeferredActionWatcher(pid: pid, action: .openNewWindow) { @MainActor [weak self] in
            guard let self else { return }
            for delay in WindowAction.deferredConfirmationPollDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard shouldRunDeferredWatchers else { return }
                await WindowUtil.updateNewWindowsForApp(app)
                let cached = WindowUtil.readCachedWindows(for: pid).filter { !$0.isWindowlessApp }
                let currentIDs = Set(cached.map(\.id))
                let hasNewWindow = !currentIDs.subtracting(previousWindowIDs).isEmpty
                let hasUsableWindow = cached.contains { !$0.isMinimized && !$0.isEffectivelyHiddenForUI }
                let currentTitle = cached
                    .first(where: { $0.id == originalWindowID })?
                    .windowName?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let titleChanged = switch (originalWindowTitle, currentTitle) {
                case (nil, nil): false
                case (nil, let current?): !current.isEmpty
                case (let original?, nil): !original.isEmpty
                case let (original?, current?): original != current
                }
                let shouldTreatAsSuccess = hasNewWindow ||
                    titleChanged ||
                    (hadNoTrackedWindowsBefore && hasUsableWindow)

                if shouldTreatAsSuccess {
                    hideWindow()
                    return
                }
            }
        }
    }

    func showFolderWidget(
        folderURL: URL,
        folderName: String,
        mouseLocation: CGPoint? = nil,
        mouseScreen: NSScreen? = nil,
        dockItemElement: AXUIElement?
    ) {
        guard canPresentPreviews else { return }
        let shouldSkipDelay = Defaults[.useDelayOnlyForInitialOpen] && isVisible
        let delay = shouldSkipDelay ? 0 : Defaults[.hoverWindowOpenDelay]

        pendingShowWorkItem?.cancel()
        let pendingShowID = UUID()
        pendingShow = (pendingShowID, nil, DockUtils.getDockPosition(), nil)
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, pendingShow?.id == pendingShowID else { return }

            if let dockItemElement {
                guard let currentDockItem = DockObserver.activeInstance?.getHoveredDockItemElement(),
                      currentDockItem == dockItemElement
                else { return }
            }

            Task { @MainActor [weak self] in
                guard let self, pendingShow?.id == pendingShowID else { return }
                pendingShow = nil

                let screen = mouseScreen ?? NSScreen.main!
                let activeDockPosition = DockUtils.getDockPosition()
                currentDockPosition = activeDockPosition
                appName = folderName
                currentlyDisplayedPID = nil
                onWindowTap = nil
                hideFullPreviewWindow()
                searchWindow?.hideSearch()
                windowSwitcherCoordinator.setWindows([], dockPosition: activeDockPosition, bestGuessMonitor: screen)
                windowSwitcherCoordinator.setShowing(.both, toState: false)

                var dockIconRect: CGRect?
                if let dockItemElement,
                   let position = try? dockItemElement.position(),
                   let size = try? dockItemElement.size()
                {
                    let rect = CGRect(origin: position, size: size)
                    dockIconRect = rect
                    anchoredDockItem = (element: dockItemElement, iconRect: rect)
                } else {
                    anchoredDockItem = nil
                }

                let view = FolderWidgetContainerView(
                    folderURL: folderURL,
                    folderName: folderName,
                    bestGuessMonitor: screen,
                    dockPosition: activeDockPosition,
                    dockItemElement: dockItemElement,
                    backgroundAppearance: BackgroundAppearance.resolve()
                )

                performShowView(
                    view,
                    mouseLocation: mouseLocation,
                    mouseScreen: screen,
                    dockItemElement: dockItemElement,
                    dockIconRect: dockIconRect,
                    dockPositionOverride: activeDockPosition
                )

                dockManager.preventDockHiding(false)
            }
        }

        pendingShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func showWindow(appName: String, windows: [WindowInfo], mouseLocation: CGPoint? = nil, mouseScreen: NSScreen? = nil,
                    dockItemElement: AXUIElement?,
                    overrideDelay: Bool = false, centeredHoverWindowState: PreviewStateCoordinator.WindowState? = nil,
                    onWindowTap: (() -> Void)? = nil, bundleIdentifier: String? = nil,
                    bypassDockMouseValidation: Bool = false,
                    dockPositionOverride: DockPosition? = nil, initialIndex: Int? = nil,
                    dockItemFrameOverride: CGRect? = nil, fullPreviewHoverID: UUID? = nil)
    {
        guard canPresentPreviews else { return }
        if windowSwitcherCoordinator.checkedWindowCount > 0,
           centeredHoverWindowState == nil,
           let currentPID = currentlyDisplayedPID,
           let requestedPID = windows.first?.app.processIdentifier,
           currentPID != requestedPID
        {
            if selectionKeepsPreviewsOpen { return }
            windowSwitcherCoordinator.clearCheckedWindows(resetOwnership: true)
        }
        let renderStartTime = CFAbsoluteTimeGetCurrent()
        DebugLogger.log("PreviewRender", details: "showWindow called: \(windows.count) windows for \(appName)")

        if centeredHoverWindowState == .fullWindowPreview,
           let fullPreviewHoverID,
           !isFullPreviewHoverActive(fullPreviewHoverID)
        {
            return
        }

        let shouldSkipDelay = overrideDelay || (Defaults[.useDelayOnlyForInitialOpen] && isVisible)
        let delay = shouldSkipDelay ? 0 : Defaults[.hoverWindowOpenDelay]

        pendingShowWorkItem?.cancel()
        let pendingShowID = UUID()
        pendingShow = (pendingShowID, windows.first?.app.processIdentifier, dockPositionOverride ?? DockUtils.getDockPosition(), nil)
        let workItem = DispatchWorkItem { [weak self, renderStartTime] in
            guard let self, pendingShow?.id == pendingShowID else { return }

            // Check if mouse entered the preview window and we're trying to show a different app
            if mouseIsWithinPreviewWindow,
               let currentPID = currentlyDisplayedPID,
               let expectedBundleId = bundleIdentifier,
               let expectedApp = NSRunningApplication.runningApplications(withBundleIdentifier: expectedBundleId).first,
               currentPID != expectedApp.processIdentifier
            {
                return
            }

            // Final validation: ensure mouse is still over the expected dock item
            if !bypassDockMouseValidation {
                if let expectedBundleId = bundleIdentifier {
                    guard let dockObserver = DockObserver.activeInstance else {
                        return
                    }
                    let currentDockItemStatus = dockObserver.getDockItemAppStatusUnderMouse()
                    let matches: Bool = switch currentDockItemStatus.status {
                    case let .success(app):
                        app.bundleIdentifier == expectedBundleId
                    case let .notRunning(bundleId):
                        bundleId == expectedBundleId
                    case .notFound:
                        false
                    }
                    guard matches,
                          let dockItem = currentDockItemStatus.dockItemElement,
                          dockObserver.isPointOverDockItem(DockObserver.getMousePosition(), item: dockItem)
                    else {
                        return
                    }
                }
            }

            Task { @MainActor [weak self] in
                guard let self, pendingShow?.id == pendingShowID else { return }
                if centeredHoverWindowState == .fullWindowPreview,
                   let fullPreviewHoverID,
                   !isFullPreviewHoverActive(fullPreviewHoverID)
                {
                    return
                }
                let windowsToShow = pendingShow?.freshWindows ?? windows
                pendingShow = nil
                performDisplay(appName: appName, windows: windowsToShow, mouseLocation: mouseLocation, mouseScreen: mouseScreen, dockItemElement: dockItemElement, centeredHoverWindowState: centeredHoverWindowState, onWindowTap: onWindowTap, bundleIdentifier: bundleIdentifier, dockPositionOverride: dockPositionOverride, initialIndex: initialIndex, dockItemFrameOverride: dockItemFrameOverride, renderStartTime: renderStartTime)
            }
        }
        pendingShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
