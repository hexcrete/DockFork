import ApplicationServices
import Cocoa
import Defaults
import ScreenCaptureKit

enum PreviewTilingLayout {
    enum Direction: CaseIterable {
        case neutral, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight

        var isQuarter: Bool {
            switch self {
            case .topLeft, .topRight, .bottomLeft, .bottomRight: true
            default: false
            }
        }
    }

    static func frames(count: Int, in bounds: CGRect, direction: Direction = .neutral,
                       maximumRows: Int, maximumColumns: Int) -> [CGRect?]
    {
        guard count > 0 else { return [] }
        let rows = min(6, max(1, maximumRows))
        let columns = min(6, max(1, maximumColumns))
        guard rows != 1 || columns != 1 else { return Array(repeating: nil, count: count) }
        let capacity = rows * columns
        if count > capacity {
            return stride(from: 0, to: count, by: capacity).flatMap { start in
                frames(count: min(capacity, count - start), in: bounds, direction: direction,
                       maximumRows: rows, maximumColumns: columns)
            }
        }
        let tiledCount = min(count, rows * columns)
        var normalized: [CGRect] = []
        if tiledCount == 1 {
            normalized = switch direction {
            case .neutral: [CGRect(x: 0, y: 0, width: 1, height: 1)]
            case .left, .right: [CGRect(x: 0, y: 0, width: 0.5, height: 1)]
            case .top, .bottom: [CGRect(x: 0, y: 0.5, width: 1, height: 0.5)]
            case .topLeft, .topRight, .bottomLeft, .bottomRight: [CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)]
            }
        } else if direction.isQuarter, tiledCount <= 4, rows >= 2, columns >= 2 {
            normalized = (0 ..< tiledCount).map { CGRect(x: CGFloat($0 % 2) / 2, y: $0 < 2 ? 0.5 : 0, width: 0.5, height: 0.5) }
        } else if tiledCount == 2, rows >= 2, columns >= 2 {
            normalized = direction == .top || direction == .bottom
                ? [CGRect(x: 0, y: 0.5, width: 1, height: 0.5), CGRect(x: 0, y: 0, width: 1, height: 0.5)]
                : [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0, width: 0.5, height: 1)]
        } else if tiledCount == 3, rows >= 2, columns >= 2 {
            normalized = direction == .top || direction == .bottom
                ? [CGRect(x: 0, y: 0.5, width: 1, height: 0.5), CGRect(x: 0, y: 0, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)]
                : [CGRect(x: 0, y: 0, width: 0.5, height: 1), CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5), CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)]
        } else if tiledCount == 4, rows >= 2, columns >= 2 {
            normalized = (0 ..< 4).map { CGRect(x: CGFloat($0 % 2) / 2, y: $0 < 2 ? 0.5 : 0, width: 0.5, height: 0.5) }
        } else {
            var grid = (rows: rows, columns: columns)
            var bestUnused = Int.max
            var bestAspect = CGFloat.infinity
            for r in 1 ... rows {
                for c in 1 ... columns where r * c >= tiledCount {
                    let unused = r * c - tiledCount
                    let aspect = abs(log((bounds.width / CGFloat(c)) / (bounds.height / CGFloat(r))))
                    if unused < bestUnused || (unused == bestUnused && aspect < bestAspect) {
                        grid = (r, c); bestUnused = unused; bestAspect = aspect
                    }
                }
            }
            for index in 0 ..< tiledCount {
                let row = index / grid.columns
                let rowCount = min(grid.columns, tiledCount - row * grid.columns)
                normalized.append(CGRect(x: CGFloat(index % grid.columns) / CGFloat(rowCount),
                                         y: 1 - CGFloat(row + 1) / CGFloat(grid.rows),
                                         width: 1 / CGFloat(rowCount), height: 1 / CGFloat(grid.rows)))
            }
        }
        let mirrorX = direction == .right || direction == .topRight || direction == .bottomRight
        let mirrorY = direction == .bottom || direction == .bottomLeft || direction == .bottomRight
        let frames = normalized.map { frame -> CGRect? in
            let x = mirrorX ? 1 - frame.maxX : frame.minX
            let y = mirrorY ? 1 - frame.maxY : frame.minY
            return CGRect(x: bounds.minX + x * bounds.width, y: bounds.minY + y * bounds.height,
                          width: frame.width * bounds.width, height: frame.height * bounds.height)
        }
        return frames + Array(repeating: nil, count: count - tiledCount)
    }
}

enum WindowFramePlacementResult {
    case confirmed
    // AX accepted the writes, but the actual frame did not match the request.
    case unconfirmed
    case failed
}

enum WindowActivationResult {
    case succeeded
    case failed
    case cancelled
}

final class WindowActivationRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var result: WindowActivationResult?
    private var completion: ((WindowActivationResult) -> Void)?

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func onCompletion(_ completion: @escaping (WindowActivationResult) -> Void) {
        lock.lock()
        if let result {
            lock.unlock()
            completion(result)
        } else {
            self.completion = completion
            lock.unlock()
        }
    }

    func finish(_ success: Bool) {
        resolve(success, cancelling: false)
    }

    func cancel() {
        resolve(false, cancelling: true)
    }

    private func resolve(_ success: Bool, cancelling: Bool) {
        lock.lock()
        cancelled = cancelled || cancelling
        guard result == nil else {
            lock.unlock()
            return
        }
        let result: WindowActivationResult = cancelled ? .cancelled : success ? .succeeded : .failed
        self.result = result
        let completion = completion
        self.completion = nil
        lock.unlock()
        completion?(result)
    }
}

final class WindowActivationCoordinator: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: WindowActivationRequest?

    func begin(_ request: WindowActivationRequest) {
        lock.lock()
        guard !request.isCancelled else {
            lock.unlock()
            return
        }
        let previous = latest
        latest = request
        lock.unlock()
        // Completion may resume a task; never invoke it while holding the coordinator lock.
        previous?.cancel()
    }
}

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let windowProvider: WindowPropertiesProviding
    let app: NSRunningApplication
    let ownerApp: NSRunningApplication
    var windowName: String?
    var frame: CGRect
    var image: CGImage?
    var axElement: AXUIElement
    var appAxElement: AXUIElement
    var closeButton: AXUIElement?
    let hasLimitedWindowControls: Bool
    var spaceID: Int?
    var spaceNumberOverride: Int?
    var screenIdentifier: String?
    var lastAccessedTime: Date
    var creationTime: Date
    var imageCapturedTime: Date
    var isMinimized: Bool
    var isHidden: Bool
    var isFullscreen: Bool?
    private(set) var isWindowlessApp: Bool

    private var _scWindow: SCWindow?

    init(windowProvider: WindowPropertiesProviding, app: NSRunningApplication, ownerApp: NSRunningApplication? = nil, image: CGImage?, axElement: AXUIElement, appAxElement: AXUIElement, closeButton: AXUIElement?, hasLimitedWindowControls: Bool = false, lastAccessedTime: Date, creationTime: Date? = nil, imageCapturedTime: Date? = nil, spaceID: Int? = nil, spaceNumberOverride: Int? = nil, screenIdentifier: String? = nil, isMinimized: Bool, isHidden: Bool, isFullscreen: Bool? = nil, readsAXTitle: Bool = true) {
        id = windowProvider.windowID
        self.windowProvider = windowProvider
        self.app = app
        self.ownerApp = ownerApp ?? app
        if readsAXTitle, !AXResponsiveness.isUnresponsive(app.processIdentifier) {
            windowName = (try? axElement.title()) ?? windowProvider.title
        } else {
            windowName = windowProvider.title
        }
        frame = windowProvider.frame
        self.image = image
        self.axElement = axElement
        self.appAxElement = appAxElement
        self.closeButton = closeButton
        self.hasLimitedWindowControls = hasLimitedWindowControls
        self.spaceID = spaceID
        self.spaceNumberOverride = spaceNumberOverride
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

    var scWindow: SCWindow? { _scWindow }
    var spaceNumber: Int? {
        guard !isWindowlessApp else { return nil }
        return spaceNumberOverride ?? SpaceNumberResolver.number(for: spaceID)
    }

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
        let hasLimitedWindowControls: Bool
        let spaceID: Int?
        let spaceNumberOverride: Int?
        let screenIdentifier: String?
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
            hasLimitedWindowControls: hasLimitedWindowControls,
            spaceID: spaceID,
            spaceNumberOverride: spaceNumberOverride,
            screenIdentifier: screenIdentifier,
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
            isHidden: false,
            readsAXTitle: false
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

    @discardableResult
    func zoom() -> Bool {
        positionWindow(.full)
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
                let requested = currentSize ?? CGSize(width: visibleFrame.width * 0.6, height: visibleFrame.height * 0.6)
                let size = CGSize(width: min(requested.width, visibleFrame.width), height: min(requested.height, visibleFrame.height))
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
        guard let windowFrame = currentWindowFrame(),
              let screen = NSScreen.screen(containing: windowFrame)
        else {
            return nil
        }

        return (screen, windowFrame.size)
    }

    static func positionedFrame(_ rect: WindowPositionRect, for windowFrame: CGRect, size: CGSize? = nil) -> CGRect? {
        guard let screen = NSScreen.screen(containing: windowFrame) else { return nil }
        return rect.frame(in: screen.snappingFrame, currentSize: size ?? windowFrame.size)
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

    @discardableResult
    private func applyWindowFrame(_ targetFrame: CGRect, on screen: NSScreen, refreshPreview: Bool = true, preservesSnapRecord: Bool = false) -> Bool {
        let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let axY = primaryScreenMaxY - targetFrame.maxY
        let newPosition = CGPoint(x: targetFrame.origin.x, y: axY)
        let newSize = CGSize(width: targetFrame.width, height: targetFrame.height)

        guard let positionValue = AXValue.from(point: newPosition),
              let sizeValue = AXValue.from(size: newSize)
        else {
            return false
        }

        if !preservesSnapRecord { WindowSnapRegistry.existing?.remove(PreviewWindowIdentity(self)) }
        let enhancedUIAttribute = "AXEnhancedUserInterface"
        let restoreEnhancedUI = (try? appAxElement.attribute(enhancedUIAttribute, Bool.self)) == true
        // Some apps apply this write despite reporting an error; always restore the prior state.
        if restoreEnhancedUI { try? appAxElement.setAttribute(enhancedUIAttribute, false) }
        defer {
            if restoreEnhancedUI { try? appAxElement.setAttribute(enhancedUIAttribute, true) }
        }

        // Either write can be constrained by the old frame; finish resizing at the new position if needed.
        var sizeApplied = (try? axElement.size()) == newSize ||
            (try? axElement.setAttribute(kAXSizeAttribute, sizeValue)) != nil
        let positionApplied = (try? axElement.setAttribute(kAXPositionAttribute, positionValue)) != nil
        if positionApplied, let actualSize = try? axElement.size(), actualSize != newSize {
            sizeApplied = (try? axElement.setAttribute(kAXSizeAttribute, sizeValue)) != nil
        }

        guard positionApplied || sizeApplied else { return false }
        if refreshPreview || !positionApplied || !sizeApplied {
            WindowUtil.refreshCachedPreviewAfterProgrammaticResize(self, targetScreenIdentifier: screen.uniqueIdentifier())
        }
        return positionApplied && sizeApplied
    }

    @discardableResult
    func setWindowFrame(_ targetFrame: CGRect, on targetScreen: NSScreen? = nil) -> Bool {
        guard let screen = targetScreen ?? NSScreen.screens.first(where: { $0.frame.intersects(targetFrame) })
            ?? currentWindowPlacementContext()?.screen
            ?? NSScreen.main
        else {
            return false
        }

        return applyWindowFrame(targetFrame, on: screen)
    }

    @discardableResult
    func applyFrame(_ targetFrame: CGRect) -> Bool {
        guard let screen = NSScreen.screen(containing: targetFrame) else { return false }
        return applyWindowFrame(targetFrame, on: screen, preservesSnapRecord: true)
    }

    @MainActor
    func setWindowFrameResult(_ targetFrame: CGRect, on screen: NSScreen,
                              isRequestActive: @escaping @MainActor () -> Bool) async -> WindowFramePlacementResult
    {
        guard !Task.isCancelled, isRequestActive() else { return .failed }
        var actualFrame: CGRect?
        let applied = applyWindowFrame(targetFrame, on: screen, refreshPreview: false)
        defer {
            if applied, !Task.isCancelled, isRequestActive() {
                WindowUtil.refreshCachedPreviewAfterProgrammaticResize(self, targetScreenIdentifier: screen.uniqueIdentifier())
            }
        }
        if applied {
            for check in 0 ..< 2 {
                if check == 1 {
                    do { try await Task.sleep(nanoseconds: 100_000_000) }
                    catch { return .failed }
                }
                guard !Task.isCancelled, isRequestActive() else { return .failed }
                actualFrame = currentWindowFrame()
                if let actualFrame,
                   abs(actualFrame.minX - targetFrame.minX) <= 1,
                   abs(actualFrame.minY - targetFrame.minY) <= 1,
                   abs(actualFrame.width - targetFrame.width) <= 1,
                   abs(actualFrame.height - targetFrame.height) <= 1
                { return .confirmed }
            }
        }
        DebugLogger.log("WindowPlacement", details: "PID: \(app.processIdentifier), window: \(id), target: \(targetFrame), actual: \(String(describing: actualFrame)), confirmed: false")
        return applied && actualFrame != nil ? .unconfirmed : .failed
    }

    @discardableResult
    func positionWindow(_ rect: WindowPositionRect, size: CGSize? = nil) -> Bool {
        guard let context = currentWindowPlacementContext() else {
            return false
        }

        let visibleFrame = context.screen.snappingFrame
        let targetFrame = rect.frame(in: visibleFrame, currentSize: size ?? context.size)
        return applyWindowFrame(targetFrame, on: context.screen)
    }

    @discardableResult
    func fillLeftHalf() -> Bool {
        positionWindow(.leftHalf)
    }

    @discardableResult
    func fillRightHalf() -> Bool {
        positionWindow(.rightHalf)
    }

    @discardableResult
    func fillTopHalf() -> Bool {
        positionWindow(.topHalf)
    }

    @discardableResult
    func fillBottomHalf() -> Bool {
        positionWindow(.bottomHalf)
    }

    @discardableResult
    func fillTopLeftQuarter() -> Bool {
        positionWindow(.topLeftQuarter)
    }

    @discardableResult
    func fillTopRightQuarter() -> Bool {
        positionWindow(.topRightQuarter)
    }

    @discardableResult
    func fillBottomLeftQuarter() -> Bool {
        positionWindow(.bottomLeftQuarter)
    }

    @discardableResult
    func fillBottomRightQuarter() -> Bool {
        positionWindow(.bottomRightQuarter)
    }

    @discardableResult
    func centerWindow() -> Bool {
        positionWindow(.center)
    }

    func centerWindow(scale: CGFloat) {
        guard let context = currentWindowPlacementContext() else {
            return
        }

        let visibleFrame = context.screen.snappingFrame
        let clampedScale = min(max(scale, 0.2), 1.0)
        let targetSize = CGSize(
            width: visibleFrame.width * clampedScale,
            height: visibleFrame.height * clampedScale
        )
        let targetFrame = WindowPositionRect.center.frame(in: visibleFrame, currentSize: targetSize)
        setWindowFrame(targetFrame)
    }

    func centerWindow(widthScale: CGFloat, heightScale: CGFloat, lockAspectRatio: Bool) {
        guard let context = currentWindowPlacementContext() else {
            return
        }

        let visibleFrame = context.screen.snappingFrame

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
                setWindowFrame(targetFrame)
                return
            }

            let scaleFactor = min(maxWidth / currentSize.width, maxHeight / currentSize.height)
            targetSize = CGSize(width: currentSize.width * scaleFactor, height: currentSize.height * scaleFactor)
        } else {
            targetSize = CGSize(width: maxWidth, height: maxHeight)
        }

        let targetFrame = WindowPositionRect.center.frame(in: visibleFrame, currentSize: targetSize)
        setWindowFrame(targetFrame)
    }

    @discardableResult
    func moveToCurrentManagedSpace(mouseLocation: CGPoint = NSEvent.mouseLocation) -> Bool {
        WindowUtil.moveWindowToCurrentManagedSpace(self, mouseLocation: mouseLocation)
    }

    private static let axRaiseQueue = DispatchQueue(label: "com.ethanbills.DockDoor.axRaise", qos: .userInteractive)

    private static let activationCoordinator = WindowActivationCoordinator()

    func bringToFront() {
        enqueueActivation(request: WindowActivationRequest())
    }

    @MainActor
    func bringToFrontConfirmed() async -> Bool {
        await bringToFrontResult() == .succeeded
    }

    @MainActor
    func bringToFrontResult() async -> WindowActivationResult {
        let request = WindowActivationRequest()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                request.onCompletion { success in
                    continuation.resume(returning: success)
                }
                enqueueActivation(request: request)
            }
        } onCancel: {
            request.cancel()
        }
    }

    private func enqueueActivation(request: WindowActivationRequest) {
        guard !request.isCancelled, !ownerApp.isTerminated else {
            request.finish(false)
            return
        }

        WindowInfo.activationCoordinator.begin(request)
        guard !request.isCancelled else { return }

        guard !isWindowlessApp else {
            WindowUtil.activateWindowlessApp(app: app)
            request.finish(true)
            return
        }

        var psn = ProcessSerialNumber()
        _ = GetProcessForPID(ownerApp.processIdentifier, &psn)
        _ = _SLPSSetFrontProcessWithOptions(&psn, UInt32(id), SLPSMode.userGenerated.rawValue)
        WindowUtil.makeKeyWindow(&psn, windowID: id)

        let window = self
        WindowInfo.axRaiseQueue.async {
            let maxRetries = 3
            for attempt in 0 ..< maxRetries {
                guard !request.isCancelled, !window.ownerApp.isTerminated else {
                    request.finish(false)
                    return
                }
                do {
                    if attempt > 0 {
                        var psn = ProcessSerialNumber()
                        _ = GetProcessForPID(window.ownerApp.processIdentifier, &psn)
                        _ = _SLPSSetFrontProcessWithOptions(&psn, UInt32(window.id), SLPSMode.userGenerated.rawValue)
                        WindowUtil.makeKeyWindow(&psn, windowID: window.id)
                    }

                    try window.axElement.performAction(kAXRaiseAction)
                    guard !request.isCancelled else {
                        request.finish(false)
                        return
                    }
                    try window.axElement.setAttribute(kAXMainAttribute, true)
                    guard !request.isCancelled else {
                        request.finish(false)
                        return
                    }
                    WindowUtil.updateTimestampOptimistically(for: window)
                    request.finish(true)
                    return
                } catch {
                    guard !request.isCancelled else { return }
                    print("Attempt \(attempt + 1) failed to bring window to front: \(error)")
                    DebugLogger.log("WindowActivation", details: "PID: \(window.app.processIdentifier), window: \(window.id), attempt: \(attempt + 1), failed: \(error)")
                    if error is AxError {
                        WindowUtil.removeWindowFromDesktopSpaceCache(with: window.id, in: window.app.processIdentifier)
                    }
                    if attempt + 1 < maxRetries, !request.isCancelled {
                        usleep(50000)
                    }
                }
            }
            print("Failed to bring window to front after \(maxRetries) attempts")
            request.finish(false)
        }
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
