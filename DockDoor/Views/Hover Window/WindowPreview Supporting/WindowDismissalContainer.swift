import Defaults
import SwiftUI

struct WindowDismissalContainer: NSViewRepresentable {
    let appName: String
    let bestGuessMonitor: NSScreen
    let dockPosition: DockPosition
    let dockItemElement: AXUIElement?
    let applicationProcessIdentifier: pid_t?
    let applicationBundleIdentifier: String?
    let dockItemFrameOverride: CGRect?
    let originalMouseLocation: CGPoint?
    let minimizeAllWindowsCallback: (_ wasAppActiveBeforeClick: Bool) -> Void

    init(appName: String, bestGuessMonitor: NSScreen, dockPosition: DockPosition, dockItemElement: AXUIElement?, applicationProcessIdentifier: pid_t? = nil, applicationBundleIdentifier: String? = nil, dockItemFrameOverride: CGRect? = nil, originalMouseLocation: CGPoint? = nil, minimizeAllWindowsCallback: @escaping (_ wasAppActiveBeforeClick: Bool) -> Void) {
        self.appName = appName
        self.bestGuessMonitor = bestGuessMonitor
        self.dockPosition = dockPosition
        self.dockItemElement = dockItemElement
        self.applicationProcessIdentifier = applicationProcessIdentifier
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.dockItemFrameOverride = dockItemFrameOverride
        self.originalMouseLocation = originalMouseLocation
        self.minimizeAllWindowsCallback = minimizeAllWindowsCallback
    }

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView(appName: appName,
                                       bestGuessMonitor: bestGuessMonitor,
                                       dockPosition: dockPosition,
                                       dockItemElement: dockItemElement,
                                       applicationProcessIdentifier: applicationProcessIdentifier,
                                       applicationBundleIdentifier: applicationBundleIdentifier,
                                       dockItemFrameOverride: dockItemFrameOverride,
                                       originalMouseLocation: originalMouseLocation,
                                       minimizeAllWindowsCallback: minimizeAllWindowsCallback)
        view.resetOpacity()
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {}
}

class MouseTrackingNSView: NSView {
    private let appName: String
    private let bestGuessMonitor: NSScreen
    private let dockPosition: DockPosition
    private let dockItemElement: AXUIElement?
    private let applicationProcessIdentifier: pid_t?
    private let applicationBundleIdentifier: String?
    private let dockItemFrameOverride: CGRect?
    private let originalMouseLocation: CGPoint?
    private let minimizeAllWindowsCallback: (_ wasAppActiveBeforeClick: Bool) -> Void
    private var fadeOutTimer: Timer?
    private let fadeOutDuration: TimeInterval
    private var inactivityCheckTimer: Timer?
    private let inactivityCheckInterval: TimeInterval

    init(appName: String, bestGuessMonitor: NSScreen, dockPosition: DockPosition, dockItemElement: AXUIElement?, applicationProcessIdentifier: pid_t? = nil, applicationBundleIdentifier: String? = nil, dockItemFrameOverride: CGRect? = nil, originalMouseLocation: CGPoint? = nil, minimizeAllWindowsCallback: @escaping (_ wasAppActiveBeforeClick: Bool) -> Void, frame frameRect: NSRect = .zero) {
        self.appName = appName
        self.bestGuessMonitor = bestGuessMonitor
        self.dockPosition = dockPosition
        self.dockItemElement = dockItemElement
        self.applicationProcessIdentifier = applicationProcessIdentifier
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.dockItemFrameOverride = dockItemFrameOverride
        self.originalMouseLocation = originalMouseLocation
        self.minimizeAllWindowsCallback = minimizeAllWindowsCallback
        fadeOutDuration = Defaults[.fadeOutDuration]
        inactivityCheckInterval = TimeInterval(Defaults[.inactivityTimeout])
        super.init(frame: frameRect)
        setupTrackingArea()
        startInactivityMonitoring()
        resetOpacityVisually()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupTrackingArea() {
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    deinit {
        clearTimers()
    }

    private func clearTimers() {
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
        inactivityCheckTimer?.invalidate()
        inactivityCheckTimer = nil
    }

    private func startInactivityMonitoring() {
        inactivityCheckTimer?.invalidate()
        inactivityCheckTimer = Timer.scheduledTimer(withTimeInterval: inactivityCheckInterval, repeats: true) { [weak self] _ in
            guard let self, let window else { return }

            let currentMouseLocation = NSEvent.mouseLocation
            let windowFrame = window.frame.insetBy(dx: HoverContainerPadding.container, dy: HoverContainerPadding.container)

            let isMouseOverDockIcon = checkIfMouseIsOverDockIcon()

            if windowFrame.contains(currentMouseLocation) || isMouseOverDockIcon {
                resetOpacityVisually()
            } else {
                if fadeOutTimer == nil, window.alphaValue == 1.0 {
                    startFadeOut()
                }
            }
        }
    }

    private func checkIfMouseIsOverDockIcon() -> Bool {
        if dockPosition == .cli {
            if let frameOverride = dockItemFrameOverride {
                return frameOverride.insetBy(dx: -15, dy: -15).contains(NSEvent.mouseLocation)
            }
            return isNearOriginalMouseLocation()
        }

        guard let activeDockObserver = DockObserver.activeInstance else { return false }
        guard let originalDockItem = dockItemElement else { return false }

        if let applicationProcessIdentifier {
            switch activeDockObserver.getDockItemAppStatusUnderMouse().status {
            case let .success(app):
                return app.processIdentifier == applicationProcessIdentifier
            case .notFound:
                return isNearOriginalMouseLocation()
            case let .notRunning(bundleIdentifier):
                return bundleIdentifier == applicationBundleIdentifier
            }
        }

        guard let currentDockItem = activeDockObserver.getHoveredApplicationDockItem() else { return false }

        return originalDockItem == currentDockItem
    }

    private func isNearOriginalMouseLocation() -> Bool {
        guard let originalMouseLocation else { return false }
        let currentMouseLocation = NSEvent.mouseLocation
        return hypot(
            currentMouseLocation.x - originalMouseLocation.x,
            currentMouseLocation.y - originalMouseLocation.y
        ) < 50
    }

    func resetOpacity() {
        resetOpacityVisually()
    }

    private func resetOpacityVisually() {
        guard !Defaults[.preventPreviewReentryDuringFadeOut] else { return }
        cancelFadeOut()
        setWindowOpacity(to: 1.0, duration: 0.2)
    }

    override func mouseEntered(with event: NSEvent) {
        resetOpacityVisually()
        SharedPreviewWindowCoordinator.activeInstance?.mouseIsWithinPreviewWindow = true
    }

    override func mouseExited(with event: NSEvent) {
        SharedPreviewWindowCoordinator.activeInstance?.mouseIsWithinPreviewWindow = false
    }

    private func startFadeOut() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard SharedPreviewWindowCoordinator.activeInstance?.windowSwitcherCoordinator.windowSwitcherActive == false else { return }
            guard !DockObserver.isCmdTabSwitcherActive else { return }

            guard let window, window.alphaValue > 0 else { return }

            cancelFadeOut()

            if fadeOutDuration == 0 {
                performHideWindow()
            } else {
                setWindowOpacity(to: 0.0, duration: fadeOutDuration)
                fadeOutTimer = Timer.scheduledTimer(withTimeInterval: fadeOutDuration, repeats: false) { [weak self] _ in
                    self?.performHideWindow()
                }
            }
        }
    }

    func cancelFadeOut() {
        fadeOutTimer?.invalidate()
        fadeOutTimer = nil
    }

    private func setWindowOpacity(to value: CGFloat, duration: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            if window.alphaValue == value { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                window.animator().alphaValue = value
            }
        }
    }

    private func performHideWindow(preventLastAppClear: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            guard self != nil else { return }
            SharedPreviewWindowCoordinator.activeInstance?.hideWindow()
        }
    }
}
