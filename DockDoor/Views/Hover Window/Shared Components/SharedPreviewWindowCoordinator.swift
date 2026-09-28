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

final class SharedPreviewWindowCoordinator: NSPanel {
    weak static var activeInstance: SharedPreviewWindowCoordinator?

    let windowSwitcherCoordinator = PreviewStateCoordinator()
    private let dockManager = DockAutoHideManager()
    private var searchWindow: SearchWindow?

    private var appName: String = ""
    var currentlyDisplayedPID: pid_t?
    var mouseIsWithinPreviewWindow: Bool = false
    private var onWindowTap: (() -> Void)?
    private var fullPreviewWindow: NSPanel?
    private var fullPreviewFadeOutToken: UUID?
    private var activeFullPreviewHoverID: UUID?
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
    }

    private var deferredActionWatchersByKey: [String: DeferredActionWatcher] = [:]
    private var deferredRefreshTasksByKey: [String: DeferredRefreshTask] = [:]
    private var activationDismissalSuppression: ActivationDismissalSuppression?

    var windowSize: CGSize = getWindowSize()

    private var previousHoverWindowOrigin: CGPoint?
    private var currentDockPosition: DockPosition = .bottom

    private var anchoredDockItem: (element: AXUIElement, iconRect: CGRect)?
    private var switcherAnchorCenter: CGPoint?

    private(set) var hasScreenRecordingPermission: Bool = PermissionsChecker.hasScreenRecordingPermission()

    var pinnedWindows: [String: (window: NSWindow, info: PinnedWindowInfo)] = [:]

    struct TapSnapshot {
        var isVisible = false
        var frame: CGRect = .zero
        var fullPreviewFrame: CGRect?
        var searchFrame: CGRect?
        var isSearchFocused = false
    }

    private let tapSnapshotLock = NSLock()
    private var currentTapSnapshot = TapSnapshot()

    /// Window state for event tap callbacks, which run off the main thread.
    var tapSnapshot: TapSnapshot {
        tapSnapshotLock.lock()
        defer { tapSnapshotLock.unlock() }
        return currentTapSnapshot
    }

    @objc private func publishTapSnapshot() {
        let snapshot = TapSnapshot(
            isVisible: isVisible,
            frame: frame,
            fullPreviewFrame: fullPreviewWindow.flatMap { $0.isVisible ? $0.frame : nil },
            searchFrame: searchWindowFrame,
            isSearchFocused: isSearchWindowFocused
        )
        tapSnapshotLock.lock()
        currentTapSnapshot = snapshot
        tapSnapshotLock.unlock()
    }

    init() {
        let styleMask: NSWindow.StyleMask = [.nonactivatingPanel, .fullSizeContentView, .borderless]
        super.init(contentRect: .zero, styleMask: styleMask, backing: .buffered, defer: false)
        SharedPreviewWindowCoordinator.activeInstance = self
        setupWindow()
        setupSearchWindow()
        setupFrameRefreshObserver()
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSWindow.didExposeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(publishTapSnapshot), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(switcherFrameDidChange), name: NSWindow.didResizeNotification, object: self)
    }

    deinit {
        if SharedPreviewWindowCoordinator.activeInstance === self {
            SharedPreviewWindowCoordinator.activeInstance = nil
        }
        dockManager.cleanup()
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
            self?.refreshPanelFrameToFitContent()
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
    }

    func restoreDockAutoHideState() {
        dockManager.restoreDockState()
    }

    func hideWindow(cancelPendingShow shouldCancelPendingShow: Bool = true) {
        if shouldCancelPendingShow {
            cancelPendingShow()
        }
        SpaceMoveMenuController.shared.dismiss()
        cancelAllDeferredActionWatchers()
        activationDismissalSuppression = nil

        // Always restore dock auto-hide state, even if the preview isn't visible.
        restoreDockAutoHideState()
        hideFullPreviewWindow()

        guard isVisible else { return }

        DragPreviewCoordinator.shared.endDragging()

        searchWindow?.hideSearch()

        if let currentContent = contentView {
            currentContent.removeFromSuperview()
        }
        contentView = nil
        appName = ""
        currentlyDisplayedPID = nil
        mouseIsWithinPreviewWindow = false
        anchoredDockItem = nil
        switcherAnchorCenter = nil

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
    private func suppressNextActionDrivenActivationDismissal(for expectedProcessIdentifier: pid_t?) -> UUID? {
        guard isVisible else { return nil }

        let token = UUID()
        activationDismissalSuppression = ActivationDismissalSuppression(
            token: token,
            expectedProcessIdentifier: expectedProcessIdentifier,
            expiresAt: Date().addingTimeInterval(1)
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

        let matches = suppression.expectedProcessIdentifier == nil ||
            suppression.expectedProcessIdentifier == processIdentifier
        if !matches {
            activationDismissalSuppression = nil
        }
        return matches
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
        guard currentlyDisplayedPID == pid, currentDockPosition == dockPosition else { return false }
        windowSwitcherCoordinator.mergeWindows(windows, dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor)
        if dockPosition == .cmdTab, let refreshedPID = windows.first?.app.processIdentifier {
            currentlyDisplayedPID = refreshedPID
        }
        return true
    }

    /// Refreshes the panel frame to match SwiftUI content's intrinsic size after window count changes.
    @MainActor
    private func refreshPanelFrameToFitContent() {
        guard let hostingView = contentView else { return }

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize

        let screen = NSScreen.screenFromQuartzPoint(NSEvent.mouseLocation)
        let screenFrame = screen.frame

        let newSize = fittingSize
        guard newSize != frame.size else { return }

        if let centeredFrame = centeredSwitcherFrame(for: newSize) {
            let searchFrame = searchWindow.flatMap { $0.isVisible ? $0.targetFrame(relativeTo: centeredFrame, on: self.screen ?? screen) : nil }
            animateWithUserPreference {
                self.animator().setFrame(centeredFrame, display: true)
                if let searchFrame { self.searchWindow?.animator().setFrame(searchFrame, display: true) }
            }
            return
        }

        let wasClampedToTop = frame.maxY >= screenFrame.maxY - 1
        let wasClampedToBottom = frame.minY <= screenFrame.minY + 1

        // Anchor based on dock position; if clamped to screen edge, keep that edge fixed
        var newOrigin = switch currentDockPosition {
        case .left:
            if wasClampedToTop {
                CGPoint(x: frame.minX, y: frame.maxY - newSize.height)
            } else if wasClampedToBottom {
                CGPoint(x: frame.minX, y: frame.minY)
            } else {
                CGPoint(x: frame.minX, y: frame.midY - newSize.height / 2)
            }
        case .right:
            if wasClampedToTop {
                CGPoint(x: frame.maxX - newSize.width, y: frame.maxY - newSize.height)
            } else if wasClampedToBottom {
                CGPoint(x: frame.maxX - newSize.width, y: frame.minY)
            } else {
                CGPoint(x: frame.maxX - newSize.width, y: frame.midY - newSize.height / 2)
            }
        case .bottom, .cmdTab:
            CGPoint(x: frame.midX - newSize.width / 2, y: frame.minY)
        default:
            CGPoint(x: frame.midX - newSize.width / 2, y: frame.midY - newSize.height / 2)
        }

        newOrigin.x = max(screenFrame.minX, min(newOrigin.x, screenFrame.maxX - newSize.width))
        newOrigin.y = max(screenFrame.minY, min(newOrigin.y, screenFrame.maxY - newSize.height))

        animateWithUserPreference {
            self.animator().setFrame(CGRect(origin: newOrigin, size: newSize), display: true)
        }
    }

    private func centeredSwitcherFrame(for size: CGSize) -> CGRect? {
        guard let center = switcherAnchorCenter else { return nil }
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        var origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        if let screenFrame = screen?.frame {
            origin.x = max(screenFrame.minX, min(origin.x, screenFrame.maxX - size.width))
            origin.y = max(screenFrame.minY, min(origin.y, screenFrame.maxY - size.height))
        }
        return CGRect(origin: origin, size: size)
    }

    @objc private func switcherFrameDidChange() {
        guard let target = centeredSwitcherFrame(for: frame.size),
              abs(target.minX - frame.minX) > 0.5 || abs(target.minY - frame.minY) > 0.5
        else { return }
        setFrame(target, display: true)
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
        let hostingView = NSHostingView(rootView: view)

        if let oldContentView = contentView {
            oldContentView.removeFromSuperview()
        }
        contentView = hostingView

        let newHoverWindowSize = hostingView.fittingSize
        let position: CGPoint

        if dockItemElement != nil, let dockIconRect {
            position = calculateWindowPosition(mouseLocation: mouseLocation,
                                               windowSize: newHoverWindowSize,
                                               screen: mouseScreen,
                                               dockIconRect: dockIconRect,
                                               dockPositionOverride: dockPositionOverride)

            // Prevent rendering if position calculation failed for cmd-tab
            if dockPositionOverride == .cmdTab, position == .zero {
                if let oldContentView = contentView {
                    oldContentView.removeFromSuperview()
                }
                contentView = nil
                return
            }
        } else if let frameOverride = dockItemFrameOverride {
            position = calculateWindowPositionFromFrame(mouseLocation: mouseLocation,
                                                        windowSize: newHoverWindowSize,
                                                        screen: mouseScreen,
                                                        dockItemFrame: frameOverride,
                                                        dockPositionOverride: dockPositionOverride)
        } else {
            position = centerWindowOnScreen(size: newHoverWindowSize, screen: mouseScreen)
        }

        let finalFrame = CGRect(origin: position, size: newHoverWindowSize)
        applyWindowFrame(finalFrame, animated: true, dockPositionOverride: dockPositionOverride)
        previousHoverWindowOrigin = position
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
            newHoverWindowSize = CGSize(
                width: min(targetSize.width, mouseScreen.visibleFrame.width),
                height: min(targetSize.height, mouseScreen.visibleFrame.height)
            )
        }

        let position: CGPoint
        if centerOnScreen {
            position = centerWindowOnScreen(size: newHoverWindowSize, screen: mouseScreen)
        } else {
            if dockItemElement != nil, let dockIconRect {
                position = calculateWindowPosition(mouseLocation: mouseLocation, windowSize: newHoverWindowSize, screen: mouseScreen, dockIconRect: dockIconRect, dockPositionOverride: dockPositionOverride)

                // Prevent rendering if position calculation failed for cmd-tab
                if dockPositionOverride == .cmdTab, position == .zero {
                    if let oldContentView = contentView {
                        oldContentView.removeFromSuperview()
                    }
                    contentView = nil
                    return
                }
            } else if let frameOverride = dockItemFrameOverride {
                position = calculateWindowPositionFromFrame(mouseLocation: mouseLocation, windowSize: newHoverWindowSize, screen: mouseScreen, dockItemFrame: frameOverride, dockPositionOverride: dockPositionOverride)
            } else if let mouseLocation, dockPositionOverride == .cli {
                position = calculateWindowPositionFromMouse(mouseLocation: mouseLocation, windowSize: newHoverWindowSize, screen: mouseScreen)
            } else {
                position = centerWindowOnScreen(size: newHoverWindowSize, screen: mouseScreen)
            }
        }
        let finalFrame = CGRect(origin: position, size: newHoverWindowSize)

        switcherAnchorCenter = nil
        setFrame(finalFrame, display: false)
        applyWindowFrame(finalFrame, animated: animated, dockPositionOverride: dockPositionOverride)
        previousHoverWindowOrigin = position
        if centerOnScreen, windowSwitcherCoordinator.windowSwitcherActive {
            switcherAnchorCenter = CGPoint(x: finalFrame.midX, y: finalFrame.midY)
        }

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
    private func showFullPreviewWindow(for windowInfo: WindowInfo, on screen: NSScreen) {
        windowSwitcherCoordinator.setShowing(.fullWindowPreview, toState: true)

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

        let windowSize = (try? windowInfo.axElement.size()) ?? CGSize(width: screen.frame.width, height: screen.frame.height)
        let axPosition = (try? windowInfo.axElement.position()) ?? CGPoint(x: screen.frame.midX, y: screen.frame.midY)

        let convertedPosition = DockObserver.cgPointFromNSPoint(axPosition, forScreen: screen)
        let adjustedPosition = CGPoint(x: convertedPosition.x, y: convertedPosition.y - windowSize.height)

        let flippedIconRect = CGRect(origin: adjustedPosition, size: windowSize)

        let previewView = FullSizePreviewView(windowInfo: windowInfo, windowSize: windowSize)
        let hostingView = NSHostingView(rootView: previewView)

        if let oldFullPreviewContent = fullPreviewWindow?.contentView {
            oldFullPreviewContent.removeFromSuperview()
        }
        fullPreviewWindow?.contentView = hostingView

        fullPreviewWindow?.setFrame(flippedIconRect, display: true)
        guard let fullPreviewWindow else { return }

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
    func hideFullPreviewWindow() {
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
        let baseXPosition: CGFloat = switch Defaults[.windowSwitcherHorizontalAnchor] {
        case .left:
            screen.frame.minX
        case .center:
            screen.frame.midX - (size.width / 2)
        case .right:
            screen.frame.maxX - size.width
        }

        let baseYPosition: CGFloat = switch Defaults[.windowSwitcherVerticalAnchor] {
        case .top:
            screen.frame.maxY - size.height
        case .center:
            screen.frame.midY - (size.height / 2)
        case .bottom:
            screen.frame.minY
        }

        let isOffsetEnabled = Defaults[.enableShiftWindowSwitcherPlacement]
        let horizontalOffset = isOffsetEnabled
            ? screen.frame.width * (Defaults[.windowSwitcherHorizontalOffsetPercent] / 100.0)
            : 0
        let verticalOffset = isOffsetEnabled
            ? screen.frame.height * (Defaults[.windowSwitcherVerticalOffsetPercent] / 100.0)
            : 0

        let xPosition = baseXPosition + horizontalOffset
        let yPosition = baseYPosition + verticalOffset

        return CGPoint(x: xPosition, y: yPosition)
    }

    private func calculateWindowPositionFromMouse(mouseLocation: CGPoint, windowSize: CGSize, screen: NSScreen) -> CGPoint {
        let screenFrame = screen.frame
        let buffer: CGFloat = 10

        var xPosition = mouseLocation.x - (windowSize.width / 2)
        var yPosition = mouseLocation.y + buffer

        xPosition = max(screenFrame.minX, min(xPosition, screenFrame.maxX - windowSize.width))
        yPosition = max(screenFrame.minY, min(yPosition, screenFrame.maxY - windowSize.height))

        return CGPoint(x: xPosition, y: yPosition)
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
            xPosition = screenFrame.maxX - flippedIconRect.width - windowSize.width
            yPosition = flippedIconRect.minY - (windowSize.height / 2)
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

        return CGPoint(x: xPosition, y: yPosition)
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

        return CGPoint(x: xPosition, y: yPosition)
    }

    @MainActor
    private func applyWindowFrame(_ frame: CGRect, animated: Bool, dockPositionOverride: DockPosition? = nil) {
        let shouldAnimate = animated && Defaults[.showAnimations]

        if shouldAnimate {
            // Window is appearing for the first time, apply slide animation
            let dockPosition = dockPositionOverride ?? DockUtils.getDockPosition()
            let animationOffset: CGFloat = 7.0
            var startFrame = frame

            switch dockPosition {
            case .bottom, .cli:
                startFrame.origin.y -= animationOffset
            case .left:
                startFrame.origin.x -= animationOffset
            case .right:
                startFrame.origin.x += animationOffset
            default:
                startFrame.origin.y -= animationOffset
            }

            setFrame(startFrame, display: true)
            orderFront(nil)

            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.175
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(frame, display: true)
            }
        } else {
            setFrame(frame, display: true)
        }

        alphaValue = 1.0
        makeKeyAndOrderFront(nil)
        publishTapSnapshot()
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
    func selectAndBringToFrontCurrentWindow(warpMouse: Bool = true) {
        let coordinator = windowSwitcherCoordinator
        let currentIndex = coordinator.currIndex

        guard currentIndex >= 0, currentIndex < coordinator.windows.count else {
            hideWindow()
            return
        }

        let selectedWindow = coordinator.windows[currentIndex]
        selectedWindow.bringToFront()
        if warpMouse {
            selectedWindow.warpMouseToCenterIfNeeded()
        }

        hideWindow()
    }

    @MainActor
    func navigateWithArrowKey(direction: ArrowDirection) {
        let coordinator = windowSwitcherCoordinator
        guard !coordinator.windows.isEmpty else { return }

        coordinator.hasMovedSinceOpen = false
        coordinator.initialHoverLocation = nil

        let threshold = Defaults[.windowSwitcherCompactThreshold]
        let forcedCompact = Defaults[.disableImagePreview] || !hasScreenRecordingPermission
        let isListViewMode = coordinator.windowSwitcherActive
            && (forcedCompact || (threshold > 0 && coordinator.windows.count >= threshold))

        // Handle list view navigation (up/down only, with filtering support)
        if isListViewMode {
            let filteredIndices = coordinator.filteredWindowIndices()
            let indicesToUse = coordinator.hasActiveSearch ? filteredIndices : Array(coordinator.windows.indices)
            guard !indicesToUse.isEmpty else { return }

            let currentPos = indicesToUse.firstIndex(of: coordinator.currIndex) ?? 0
            let newPos: Int = switch direction {
            case .up, .left:
                currentPos > 0 ? currentPos - 1 : indicesToUse.count - 1
            case .down, .right:
                (currentPos + 1) % indicesToUse.count
            }
            coordinator.setIndex(to: indicesToUse[newPos], source: .keyboard)
            return
        }

        // Handle filtered navigation when search is active
        if coordinator.windowSwitcherActive, coordinator.hasActiveSearch {
            coordinator.navigateFiltered(direction: direction)
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
            isWindowSwitcherActive: coordinator.windowSwitcherActive
        )
        coordinator.setIndex(to: newIndex, source: .keyboard)
    }

    @MainActor
    @discardableResult
    func performActionOnCurrentWindow(action: WindowAction, preservePreviews: Bool = false) -> Bool {
        let coordinator = windowSwitcherCoordinator
        guard coordinator.currIndex >= 0, coordinator.currIndex < coordinator.windows.count else {
            return false
        }

        let window = coordinator.windows[coordinator.currIndex]
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
            (try? window.appAxElement.attribute(kAXHiddenAttribute, Bool.self)) ?? window.isHidden
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
        let keepPreviewsOpen = preservePreviews || (category?.keepPreviewsOpen ?? (action != .openAppWindow))
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
        let expectedFullscreenState: Bool? = if action == .toggleFullScreen {
            (try? window.axElement.isFullscreen()).map(!)
        } else {
            nil
        }
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

        let result = action.perform(
            on: actionStateWindow,
            keepPreviewOnQuit: false,
            preferredWindows: coordinator.windows,
            hiddenStateBeforeAction: hiddenStateBeforeAction
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

        if action == .close || action == .quit {
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
        case .toggleFullScreen:
            if let expectedFullscreenState {
                scheduleFullscreenDismissConfirmation(
                    window: window,
                    targetFullscreenState: expectedFullscreenState
                )
            }
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
        case .quit:
            scheduleAppTerminationDismissConfirmation(window: window, sourceAction: .quit)
        case .closeAllWindows:
            scheduleCloseAllDismissConfirmation(window: window, sourceAction: .closeAllWindows)
        default:
            break
        }

        return false
    }

    @MainActor
    @discardableResult
    func performActionOnCmdTabHighlightedApps(
        action: WindowAction,
        apps: [NSRunningApplication],
        preservePreviews: Bool = false
    ) -> Bool {
        guard action == .close || action == .quit else { return false }

        var seenPIDs = Set<pid_t>()
        let targetApps = apps.filter {
            !$0.isTerminated && seenPIDs.insert($0.processIdentifier).inserted
        }
        guard !targetApps.isEmpty else { return false }

        let preferredWindows = windowSwitcherCoordinator.windows
        let targets = targetApps.map { ($0, WindowInfo.windowlessEntry(for: $0)) }
        let keepPreviewsOpen = preservePreviews || WindowAction.PostActionCategory.closing.keepPreviewsOpen

        for (app, entry) in targets {
            let appRows = preferredWindows.filter {
                $0.app.processIdentifier == app.processIdentifier && !$0.isWindowlessApp
            }
            _ = action.perform(
                on: entry,
                keepPreviewOnQuit: false,
                preferredWindows: appRows.isEmpty ? nil : appRows
            )
            if action.shouldScheduleAppRefresh {
                scheduleInPlaceActionRefresh(for: app)
            }
        }
        windowSwitcherCoordinator.scheduleActiveFocusedWindowRefresh()

        guard !keepPreviewsOpen else { return false }

        for (app, entry) in targets {
            scheduleFailedClosingFocusNotification(
                action: action,
                window: entry,
                willQuitOnClose: action == .close &&
                    WindowUtil.shouldQuitAppOnWindowClose(processIdentifier: app.processIdentifier)
            )
        }
        hideWindow()
        return true
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

                if action == .quit || willQuitOnClose {
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
                        confirmed = (try? window.axElement.isMinimized()) == targetMinimizedState
                    }
                case .hide:
                    if let targetHiddenState {
                        confirmed = app.isHidden == targetHiddenState
                    }
                case .minimizeAllWindows:
                    if let targetMinimizeAllState {
                        let nonFullscreen = WindowUtil.readCachedWindows(for: pid).filter {
                            !$0.isWindowlessApp && (try? $0.axElement.isFullscreen()) != true
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

    private func scheduleFullscreenDismissConfirmation(
        window: WindowInfo,
        targetFullscreenState: Bool
    ) {
        let windowID = window.id
        let pid = window.app.processIdentifier

        startDeferredActionWatcher(pid: pid, action: .toggleFullScreen) { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: WindowAction.fullscreenConfirmationDelay)
            guard shouldRunDeferredWatchers else { return }
            guard let confirmedFullscreen = try? window.axElement.isFullscreen(),
                  confirmedFullscreen == targetFullscreenState
            else { return }

            let coordinator = windowSwitcherCoordinator
            guard coordinator.windows.contains(where: { $0.id == windowID && $0.app.processIdentifier == pid }) else {
                return
            }

            hideWindow()
        }
    }

    func showFolderWidget(
        folderURL: URL,
        folderName: String,
        mouseLocation: CGPoint? = nil,
        mouseScreen: NSScreen? = nil,
        dockItemElement: AXUIElement?
    ) {
        let shouldSkipDelay = Defaults[.useDelayOnlyForInitialOpen] && isVisible
        let delay = shouldSkipDelay ? 0 : Defaults[.hoverWindowOpenDelay]

        pendingShowWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            if let dockItemElement {
                guard let currentDockItem = DockObserver.activeInstance?.getHoveredDockItemElement(),
                      currentDockItem == dockItemElement
                else { return }
            }

            Task { @MainActor [weak self] in
                guard let self else { return }

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
        let workItem = DispatchWorkItem { [weak self, renderStartTime] in
            guard let self else { return }

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
                    guard let currentDockItemStatus = DockObserver.activeInstance?.getDockItemAppStatusUnderMouse() else {
                        return
                    }
                    let matches: Bool = switch currentDockItemStatus.status {
                    case let .success(app):
                        app.bundleIdentifier == expectedBundleId
                    case let .notRunning(bundleId):
                        bundleId == expectedBundleId
                    case .notFound:
                        false
                    }
                    guard matches else {
                        return
                    }
                }
            }

            Task { @MainActor [weak self] in
                if centeredHoverWindowState == .fullWindowPreview,
                   let fullPreviewHoverID,
                   self?.isFullPreviewHoverActive(fullPreviewHoverID) != true
                {
                    return
                }
                self?.performDisplay(appName: appName, windows: windows, mouseLocation: mouseLocation, mouseScreen: mouseScreen, dockItemElement: dockItemElement, centeredHoverWindowState: centeredHoverWindowState, onWindowTap: onWindowTap, bundleIdentifier: bundleIdentifier, dockPositionOverride: dockPositionOverride, initialIndex: initialIndex, dockItemFrameOverride: dockItemFrameOverride, renderStartTime: renderStartTime)
            }
        }
        pendingShowWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
