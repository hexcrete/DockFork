import ApplicationServices
import Cocoa
import Defaults
import ScreenCaptureKit

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let windowProvider: WindowPropertiesProviding
    let app: NSRunningApplication
    var windowName: String?
    var image: CGImage?
    var axElement: AXUIElement
    var appAxElement: AXUIElement
    var closeButton: AXUIElement?
    var spaceID: Int?
    var screenIdentifier: String?
    var lastAccessedTime: Date
    var creationTime: Date
    var imageCapturedTime: Date
    var isMinimized: Bool
    var isHidden: Bool
    var isFullscreen: Bool?
    private(set) var isWindowlessApp: Bool

    private var _scWindow: SCWindow?

    init(windowProvider: WindowPropertiesProviding, app: NSRunningApplication, image: CGImage?, axElement: AXUIElement, appAxElement: AXUIElement, closeButton: AXUIElement?, lastAccessedTime: Date, creationTime: Date? = nil, imageCapturedTime: Date? = nil, spaceID: Int? = nil, screenIdentifier: String? = nil, isMinimized: Bool, isHidden: Bool, isFullscreen: Bool? = nil) {
        id = windowProvider.windowID
        self.windowProvider = windowProvider
        self.app = app
        windowName = (try? axElement.title()) ?? windowProvider.title
        self.image = image
        self.axElement = axElement
        self.appAxElement = appAxElement
        self.closeButton = closeButton
        self.spaceID = spaceID
        self.screenIdentifier = screenIdentifier
        self.lastAccessedTime = lastAccessedTime
        self.creationTime = creationTime ?? lastAccessedTime
        self.imageCapturedTime = imageCapturedTime ?? lastAccessedTime
        self.isMinimized = isMinimized
        self.isHidden = isHidden
        self.isFullscreen = isFullscreen
        isWindowlessApp = false
        _scWindow = windowProvider as? SCWindow
    }

    var frame: CGRect { windowProvider.frame }
    var scWindow: SCWindow? { _scWindow }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(app.processIdentifier)
    }

    static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id &&
            lhs.app.processIdentifier == rhs.app.processIdentifier &&
            lhs.axElement == rhs.axElement
    }

    struct ViewSnapshot: Equatable {
        let id: CGWindowID
        let pid: pid_t
        let windowName: String?
        let isMinimized: Bool
        let isHidden: Bool
        let isFullscreen: Bool?
        let imagePointer: UnsafeRawPointer?
    }

    var viewSnapshot: ViewSnapshot {
        ViewSnapshot(
            id: id,
            pid: app.processIdentifier,
            windowName: windowName,
            isMinimized: isMinimized,
            isHidden: isHidden,
            isFullscreen: isFullscreen,
            imagePointer: image.map { Unmanaged.passUnretained($0).toOpaque() }
        )
    }
}

extension WindowInfo {
    var isEffectivelyHiddenForUI: Bool {
        guard isHidden else { return false }
        if let isFullscreen {
            return !isFullscreen
        }
        return (try? axElement.isFullscreen()) != true
    }

    static func windowlessEntry(for app: NSRunningApplication) -> WindowInfo {
        let pid = app.processIdentifier
        let appAX = AXUIElementCreateApplication(pid)
        let provider = MockPreviewWindow(
            windowID: 0,
            frame: .zero,
            title: app.localizedName,
            owningApplicationBundleIdentifier: app.bundleIdentifier,
            owningApplicationProcessID: pid,
            isOnScreen: false,
            windowLayer: 0
        )
        var info = WindowInfo(
            windowProvider: provider,
            app: app,
            image: nil,
            axElement: appAX,
            appAxElement: appAX,
            closeButton: nil,
            lastAccessedTime: .distantPast,
            isMinimized: false,
            isHidden: false
        )
        info.isWindowlessApp = true
        return info
    }

    @discardableResult
    mutating func toggleMinimize() -> Bool? {
        guard !isWindowlessApp else { return nil }
        let newMinimizedState = !isMinimized

        do {
            if !newMinimizedState, app.isHidden {
                app.unhide()
            }

            try axElement.setAttribute(kAXMinimizedAttribute, newMinimizedState)

            if !newMinimizedState {
                app.activate()
                bringToFront()
            }

            let confirmedState = try? axElement.isMinimized()
            guard confirmedState == newMinimizedState else {
                return nil
            }

            isMinimized = newMinimizedState
            WindowUtil.updateCachedWindowState(self, isMinimized: newMinimizedState)
            return newMinimizedState
        } catch {
            return nil
        }
    }

    @discardableResult
    mutating func toggleHidden(from currentHiddenState: Bool? = nil) -> Bool? {
        guard !isWindowlessApp else { return nil }
        let resolvedHiddenState = currentHiddenState ??
            ((try? appAxElement.attribute(kAXHiddenAttribute, Bool.self)) ?? isHidden)
        let newHiddenState = !resolvedHiddenState

        do {
            try appAxElement.setAttribute(kAXHiddenAttribute, newHiddenState)

            if !newHiddenState {
                app.activate()
                bringToFront()
            }

            isHidden = newHiddenState
            WindowUtil.updateCachedWindowState(self, isHidden: newHiddenState)
            return newHiddenState
        } catch {
            print("Error toggling hidden state of application")
            return nil
        }
    }

    @discardableResult
    mutating func toggleFullScreen() -> Bool {
        guard !isWindowlessApp else { return false }
        guard let isCurrentlyInFullScreen = try? axElement.isFullscreen() else {
            print("Failed to determine current full screen state")
            return false
        }

        do {
            let targetState = !isCurrentlyInFullScreen
            try axElement.setAttribute(kAXFullscreenAttribute, targetState)
            // Non-blocking confirmation: if state does not reflect immediately, treat as no-change.
            let confirmedState = (try? axElement.isFullscreen()) == targetState
            if confirmedState {
                isFullscreen = targetState
                WindowUtil.updateCachedWindowState(self, isFullscreen: targetState)
            }
            return confirmedState
        } catch {
            print("Failed to toggle full screen")
            return false
        }
    }

    func zoom() {
        positionWindow(rect: .full)
    }

    // MARK: - Window Positioning

    enum WindowPositionRect {
        case full
        case leftHalf
        case rightHalf
        case topHalf
        case bottomHalf
        case topLeftQuarter
        case topRightQuarter
        case bottomLeftQuarter
        case bottomRightQuarter
        case center

        func frame(in visibleFrame: CGRect, currentSize: CGSize? = nil) -> CGRect {
            switch self {
            case .full:
                return visibleFrame
            case .leftHalf:
                return CGRect(
                    x: visibleFrame.origin.x,
                    y: visibleFrame.origin.y,
                    width: visibleFrame.width / 2,
                    height: visibleFrame.height
                )
            case .rightHalf:
                return CGRect(
                    x: visibleFrame.origin.x + visibleFrame.width / 2,
                    y: visibleFrame.origin.y,
                    width: visibleFrame.width / 2,
                    height: visibleFrame.height
                )
            case .topHalf:
                return CGRect(
                    x: visibleFrame.origin.x,
                    y: visibleFrame.origin.y + visibleFrame.height / 2,
                    width: visibleFrame.width,
                    height: visibleFrame.height / 2
                )
            case .bottomHalf:
                return CGRect(
                    x: visibleFrame.origin.x,
                    y: visibleFrame.origin.y,
                    width: visibleFrame.width,
                    height: visibleFrame.height / 2
                )
            case .topLeftQuarter:
                return CGRect(
                    x: visibleFrame.origin.x,
                    y: visibleFrame.origin.y + visibleFrame.height / 2,
                    width: visibleFrame.width / 2,
                    height: visibleFrame.height / 2
                )
            case .topRightQuarter:
                return CGRect(
                    x: visibleFrame.origin.x + visibleFrame.width / 2,
                    y: visibleFrame.origin.y + visibleFrame.height / 2,
                    width: visibleFrame.width / 2,
                    height: visibleFrame.height / 2
                )
            case .bottomLeftQuarter:
                return CGRect(
                    x: visibleFrame.origin.x,
                    y: visibleFrame.origin.y,
                    width: visibleFrame.width / 2,
                    height: visibleFrame.height / 2
                )
            case .bottomRightQuarter:
                return CGRect(
                    x: visibleFrame.origin.x + visibleFrame.width / 2,
                    y: visibleFrame.origin.y,
                    width: visibleFrame.width / 2,
                    height: visibleFrame.height / 2
                )
            case .center:
                let size = currentSize ?? CGSize(width: visibleFrame.width * 0.6, height: visibleFrame.height * 0.6)
                return CGRect(
                    x: visibleFrame.origin.x + (visibleFrame.width - size.width) / 2,
                    y: visibleFrame.origin.y + (visibleFrame.height - size.height) / 2,
                    width: size.width,
                    height: size.height
                )
            }
        }
    }

    private func currentWindowPlacementContext() -> (screen: NSScreen, size: CGSize)? {
        guard let currentSize = try? axElement.size(),
              let windowFrame = Self.currentWindowFrame(for: axElement)
        else {
            return nil
        }

        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(windowFrame) }) ?? NSScreen.main else {
            return nil
        }

        return (screen, currentSize)
    }

    static func currentWindowFrame(for element: AXUIElement) -> CGRect? {
        guard let currentPosition = try? element.position(),
              let currentSize = try? element.size()
        else {
            return nil
        }

        let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
        return CGRect(
            x: currentPosition.x,
            y: primaryScreenMaxY - currentPosition.y - currentSize.height,
            width: currentSize.width,
            height: currentSize.height
        )
    }

    func currentWindowFrame() -> CGRect? {
        Self.currentWindowFrame(for: axElement)
    }

    private func applyWindowFrame(_ targetFrame: CGRect, on screen: NSScreen) {
        let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let axY = primaryScreenMaxY - targetFrame.maxY
        let newPosition = CGPoint(x: targetFrame.origin.x, y: axY)
        let newSize = CGSize(width: targetFrame.width, height: targetFrame.height)

        guard let positionValue = AXValue.from(point: newPosition),
              let sizeValue = AXValue.from(size: newSize)
        else {
            return
        }

        let positionApplied = (try? axElement.setAttribute(kAXPositionAttribute, positionValue)) != nil
        let sizeApplied = (try? axElement.setAttribute(kAXSizeAttribute, sizeValue)) != nil

        guard positionApplied || sizeApplied else { return }
        WindowUtil.refreshCachedPreviewAfterProgrammaticResize(self, targetScreenIdentifier: screen.uniqueIdentifier())
    }

    func setWindowFrame(_ targetFrame: CGRect) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(targetFrame) })
            ?? currentWindowPlacementContext()?.screen
            ?? NSScreen.main
        else {
            return
        }

        applyWindowFrame(targetFrame, on: screen)
    }

    private func positionWindow(rect: WindowPositionRect) {
        guard let context = currentWindowPlacementContext() else {
            return
        }

        let visibleFrame = context.screen.visibleFrame
        let targetFrame = rect.frame(in: visibleFrame, currentSize: context.size)
        applyWindowFrame(targetFrame, on: context.screen)
    }

    func fillLeftHalf() {
        positionWindow(rect: .leftHalf)
    }

    func fillRightHalf() {
        positionWindow(rect: .rightHalf)
    }

    func fillTopHalf() {
        positionWindow(rect: .topHalf)
    }

    func fillBottomHalf() {
        positionWindow(rect: .bottomHalf)
    }

    func fillTopLeftQuarter() {
        positionWindow(rect: .topLeftQuarter)
    }

    func fillTopRightQuarter() {
        positionWindow(rect: .topRightQuarter)
    }

    func fillBottomLeftQuarter() {
        positionWindow(rect: .bottomLeftQuarter)
    }

    func fillBottomRightQuarter() {
        positionWindow(rect: .bottomRightQuarter)
    }

    func centerWindow() {
        positionWindow(rect: .center)
    }

    func centerWindow(scale: CGFloat) {
        guard let context = currentWindowPlacementContext() else {
            return
        }

        let visibleFrame = context.screen.visibleFrame
        let clampedScale = min(max(scale, 0.2), 1.0)
        let targetSize = CGSize(
            width: visibleFrame.width * clampedScale,
            height: visibleFrame.height * clampedScale
        )
        let targetFrame = WindowPositionRect.center.frame(in: visibleFrame, currentSize: targetSize)
        applyWindowFrame(targetFrame, on: context.screen)
    }

    func centerWindow(widthScale: CGFloat, heightScale: CGFloat, lockAspectRatio: Bool) {
        guard let context = currentWindowPlacementContext() else {
            return
        }

        let visibleFrame = context.screen.visibleFrame

        let clampedWidthScale = min(max(widthScale, 0.2), 1.0)
        let clampedHeightScale = min(max(heightScale, 0.2), 1.0)

        let maxWidth = visibleFrame.width * clampedWidthScale
        let maxHeight = visibleFrame.height * clampedHeightScale

        let targetSize: CGSize
        if lockAspectRatio {
            let currentSize = context.size
            guard currentSize.width > 0, currentSize.height > 0 else {
                targetSize = CGSize(width: maxWidth, height: maxHeight)
                let targetFrame = WindowPositionRect.center.frame(in: visibleFrame, currentSize: targetSize)
                applyWindowFrame(targetFrame, on: context.screen)
                return
            }

            let scaleFactor = min(maxWidth / currentSize.width, maxHeight / currentSize.height)
            targetSize = CGSize(width: currentSize.width * scaleFactor, height: currentSize.height * scaleFactor)
        } else {
            targetSize = CGSize(width: maxWidth, height: maxHeight)
        }

        let targetFrame = WindowPositionRect.center.frame(in: visibleFrame, currentSize: targetSize)
        applyWindowFrame(targetFrame, on: context.screen)
    }

    func bringToFront() {
        guard !isWindowlessApp else {
            WindowUtil.activateWindowlessApp(app: app)
            return
        }
        let maxRetries = 3
        var retryCount = 0

        func attemptActivation() -> Bool {
            do {
                var psn = ProcessSerialNumber()
                _ = GetProcessForPID(app.processIdentifier, &psn)
                _ = _SLPSSetFrontProcessWithOptions(&psn, UInt32(id), SLPSMode.userGenerated.rawValue)

                WindowUtil.makeKeyWindow(&psn, windowID: id)

                try axElement.performAction(kAXRaiseAction)
                try axElement.setAttribute(kAXMainWindowAttribute, true)

                return true
            } catch {
                print("Attempt \(retryCount + 1) failed to bring window to front: \(error)")
                if error is AxError {
                    WindowUtil.removeWindowFromDesktopSpaceCache(with: id, in: app.processIdentifier)
                }
                return false
            }
        }

        while retryCount < maxRetries {
            if attemptActivation() {
                WindowUtil.updateTimestampOptimistically(for: self)
                return
            }
            retryCount += 1
            if retryCount < maxRetries {
                usleep(50000)
            }
        }

        print("Failed to bring window to front after \(maxRetries) attempts")
    }

    func warpMouseToCenterIfNeeded() {
        let mode = Defaults[.mouseFollowsFocusMode]
        guard mode != .never else { return }

        guard let position = try? axElement.position(), let size = try? axElement.size(),
              size.width > 0, size.height > 0
        else { return }
        let windowCenter = CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2)

        if mode == .differentDisplayOnly {
            let mousePosition = DockObserver.getMousePosition()
            let mouseScreen = NSScreen.screenFromQuartzPoint(mousePosition)
            let windowScreen = NSScreen.screenFromQuartzPoint(windowCenter)
            if mouseScreen == windowScreen {
                return
            }
        }

        CGWarpMouseCursorPosition(windowCenter)
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    @discardableResult
    func close() -> Bool {
        guard !isWindowlessApp else { return false }
        guard closeButton != nil else {
            print("Error: closeButton is nil.")
            return false
        }

        do {
            try closeButton?.performAction(kAXPressAction)
            return true
        } catch {
            print("Error closing window")
            return false
        }
    }

    func quit(force: Bool) {
        if force {
            app.forceTerminate()
        } else {
            app.terminate()
        }
    }
}
