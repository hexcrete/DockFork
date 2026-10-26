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
            let cells = frames(count: capacity, in: bounds, direction: direction,
                               maximumRows: rows, maximumColumns: columns)
            return (0 ..< count).map { cells[$0 % capacity] }
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

enum WindowFrameTransactions {
    final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }

    private struct Worker {
        let queue: DispatchQueue
        var users: Int
    }

    private static let lock = NSLock()
    private static var workers: [pid_t: Worker] = [:]

    private static func acquire(_ pid: pid_t) -> DispatchQueue {
        lock.withLock {
            var worker = workers[pid] ?? Worker(queue: DispatchQueue(label: "com.ethanbills.DockDoor.frames.\(pid)", qos: .userInteractive), users: 0)
            worker.users += 1
            workers[pid] = worker
            return worker.queue
        }
    }

    private static func release(_ pid: pid_t) {
        lock.withLock {
            guard var worker = workers[pid] else { return }
            worker.users -= 1
            workers[pid] = worker.users == 0 ? nil : worker
        }
    }

    static func run<T>(for pid: pid_t, _ operation: @escaping (Cancellation) -> T) async -> T? {
        let cancellation = Cancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let queue = acquire(pid)
                queue.async {
                    let result = cancellation.isCancelled ? nil : operation(cancellation)
                    release(pid)
                    continuation.resume(returning: result)
                }
            }
        } onCancel: { cancellation.cancel() }
    }
}

struct WindowFrameContext {
    struct Screen {
        let frame: CGRect
        let bounds: CGRect
        let identifier: String
    }

    let primaryMaxY: CGFloat
    let screens: [Screen]
    let fallbackIdentifier: String?

    @MainActor
    init() {
        primaryMaxY = NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
        screens = NSScreen.screens.map { Screen(frame: $0.frame, bounds: $0.snappingFrame, identifier: $0.uniqueIdentifier()) }
        fallbackIdentifier = NSScreen.main?.uniqueIdentifier()
    }

    func screen(containing frame: CGRect) -> Screen? {
        func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let intersection = a.intersection(b)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        return screens.max { overlap($0.frame, frame) < overlap($1.frame, frame) }
            .flatMap { overlap($0.frame, frame) > 0 ? $0 : screens.first { $0.identifier == fallbackIdentifier } }
    }
}

struct WindowFrameTarget {
    let element: AXUIElement
    let application: AXUIElement
    let ownerPID: pid_t
    let identity: PreviewWindowIdentity

    func readPreviewGeometry() async -> (position: CGPoint?, size: CGSize?)? {
        let element = element
        return await WindowFrameTransactions.run(for: ownerPID) { cancellation in
            guard !cancellation.isCancelled else { return nil as (position: CGPoint?, size: CGSize?)? }
            let position = try? element.position()
            guard !cancellation.isCancelled else { return nil }
            let size = try? element.size()
            guard !cancellation.isCancelled else { return nil }
            return (position, size)
        } ?? nil
    }

    func frame(primaryMaxY: CGFloat, cancellation: WindowFrameTransactions.Cancellation? = nil) -> CGRect? {
        guard cancellation?.isCancelled != true, let position = try? element.position(),
              cancellation?.isCancelled != true, let size = try? element.size(), cancellation?.isCancelled != true else { return nil }
        return CGRect(x: position.x, y: primaryMaxY - position.y - size.height, width: size.width, height: size.height)
    }

    struct Result {
        var applied = false
        var attempted = false
        var accepted = false
        var frame: CGRect?
    }

    func apply(_ targetFrame: CGRect, primaryMaxY: CGFloat, cancellation: WindowFrameTransactions.Cancellation,
               preservesSnapRecord: Bool = false, captureFrame: Bool = true) -> Result
    {
        var result = Result()
        let readBack: Bool = {
            guard !cancellation.isCancelled,
                  let position = AXValue.from(point: CGPoint(x: targetFrame.minX, y: primaryMaxY - targetFrame.maxY)),
                  let size = AXValue.from(size: targetFrame.size)
            else { return false }
            if !preservesSnapRecord { WindowSnapRegistry.existing?.remove(identity) }
            let attribute = "AXEnhancedUserInterface"
            let restore = (try? application.attribute(attribute, Bool.self)) == true
            var modeAttempted = false
            defer { if restore, modeAttempted { try? application.setAttribute(attribute, true) } }
            guard !cancellation.isCancelled else { return false }
            // A write can take effect even when AX returns an error. Always restore the prior mode.
            if restore {
                modeAttempted = true
                try? application.setAttribute(attribute, false)
            }
            guard !cancellation.isCancelled else { return false }
            let existingSize = try? element.size()
            guard !cancellation.isCancelled else { return false }
            var sized = existingSize == targetFrame.size
            if !sized {
                result.attempted = true
                sized = (try? element.setAttribute(kAXSizeAttribute, size)) != nil
            }
            guard !cancellation.isCancelled else { return false }
            result.attempted = true
            let positioned = (try? element.setAttribute(kAXPositionAttribute, position)) != nil
            guard !cancellation.isCancelled else { return false }
            if positioned, let actualSize = try? element.size(), actualSize != targetFrame.size {
                guard !cancellation.isCancelled else { return false }
                sized = (try? element.setAttribute(kAXSizeAttribute, size)) != nil
            }
            result.applied = positioned && sized
            guard !cancellation.isCancelled else { return false }
            return positioned || sized
        }()
        result.accepted = readBack
        if captureFrame, readBack, !cancellation.isCancelled { result.frame = frame(primaryMaxY: primaryMaxY, cancellation: cancellation) }
        return result
    }

    func placeCentered(at pointer: CGPoint, within bounds: CGRect, primaryMaxY: CGFloat,
                       cancellation: WindowFrameTransactions.Cancellation) -> Result
    {
        var result = Result()
        guard !cancellation.isCancelled, let windowSize = try? element.size(),
              windowSize.width > 0, windowSize.height > 0, !cancellation.isCancelled
        else { return result }
        WindowSnapRegistry.existing?.remove(identity)
        let fittedSize = CGSize(width: min(windowSize.width, bounds.width), height: min(windowSize.height, bounds.height))
        if fittedSize != windowSize, let value = AXValue.from(size: fittedSize) {
            result.attempted = true
            result.accepted = (try? element.setAttribute(kAXSizeAttribute, value)) != nil
        }
        guard !cancellation.isCancelled else { return result }
        let resolvedSize = (try? element.size()) ?? fittedSize
        guard !cancellation.isCancelled else { return result }
        let origin = CGPoint(x: Self.clampedCenteredOrigin(pointer: pointer.x, length: resolvedSize.width, minimum: bounds.minX, maximum: bounds.maxX),
                             y: Self.clampedCenteredOrigin(pointer: pointer.y, length: resolvedSize.height, minimum: bounds.minY, maximum: bounds.maxY))
        let position = CGPoint(x: origin.x, y: primaryMaxY - origin.y - resolvedSize.height)
        guard let value = AXValue.from(point: position) else { return result }
        do {
            result.attempted = true
            try element.setAttribute(kAXPositionAttribute, value)
        } catch {
            DebugLogger.log("WindowUtil.placeWindowCentered", details: "Failed to position window \(identity.windowID): \(error)")
            return result
        }
        result.applied = true
        result.accepted = true
        guard !cancellation.isCancelled else { return result }
        let actualPosition = (try? element.position()) ?? position
        guard !cancellation.isCancelled else { return result }
        let actualSize = (try? element.size()) ?? resolvedSize
        guard !cancellation.isCancelled else { return result }
        result.frame = CGRect(x: actualPosition.x, y: primaryMaxY - actualPosition.y - actualSize.height,
                              width: actualSize.width, height: actualSize.height)
        return result
    }

    private static func clampedCenteredOrigin(pointer: CGFloat, length: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        let availableLength = maximum - minimum
        guard length <= availableLength else { return minimum + (availableLength - length) / 2 }
        return min(max(pointer - length / 2, minimum), maximum - length)
    }
}

struct WindowInfo: Identifiable, Hashable {
    let id: CGWindowID
    let windowProvider: WindowPropertiesProviding
    let app: NSRunningApplication
    let ownerApp: NSRunningApplication
    let isWineWindow: Bool
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
        isWineWindow = WindowCandidateDiscriminator.isWineApplication(ownerApp ?? app)
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
        isHidden && isFullscreen != true
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

    var frameTarget: WindowFrameTarget {
        WindowFrameTarget(element: axElement, application: AXUIElementCreateApplication(ownerApp.processIdentifier), ownerPID: ownerApp.processIdentifier, identity: PreviewWindowIdentity(self))
    }

    static func positionedFrame(_ rect: WindowPositionRect, for windowFrame: CGRect, size: CGSize? = nil) -> CGRect? {
        guard let screen = NSScreen.screen(containing: windowFrame) else { return nil }
        return rect.frame(in: screen.snappingFrame, currentSize: size ?? windowFrame.size)
    }

    static func currentWindowFrame(for element: AXUIElement) -> CGRect? {
        guard let currentPosition = try? element.position(), let currentSize = try? element.size() else { return nil }
        let primaryScreenMaxY = NSScreen.screens.first?.frame.maxY ?? NSScreen.main?.frame.maxY ?? 0
        return CGRect(x: currentPosition.x, y: primaryScreenMaxY - currentPosition.y - currentSize.height,
                      width: currentSize.width, height: currentSize.height)
    }

    func currentWindowFrame() -> CGRect? { Self.currentWindowFrame(for: axElement) }

    @MainActor
    func readWindowFrame() async -> CGRect? {
        let target = frameTarget, context = WindowFrameContext()
        return await WindowFrameTransactions.run(for: target.ownerPID) { cancellation in
            cancellation.isCancelled ? nil : target.frame(primaryMaxY: context.primaryMaxY, cancellation: cancellation)
        } ?? nil
    }

    func readFullscreenState() async -> Bool? {
        let element = axElement
        return await WindowFrameTransactions.run(for: ownerApp.processIdentifier) { cancellation in
            guard !cancellation.isCancelled else { return nil as Bool? }
            return try? element.isFullscreen()
        } ?? nil
    }

    func readMinimizedState() async -> Bool? {
        let element = axElement
        return await WindowFrameTransactions.run(for: ownerApp.processIdentifier) { cancellation in
            guard !cancellation.isCancelled else { return nil as Bool? }
            return try? element.isMinimized()
        } ?? nil
    }

    func readVisibilityState() async -> (minimized: Bool?, hidden: Bool?, fullscreen: Bool?)? {
        let element = axElement, application = appAxElement
        return await WindowFrameTransactions.run(for: ownerApp.processIdentifier) { cancellation in
            guard !cancellation.isCancelled else { return nil as (Bool?, Bool?, Bool?)? }
            let minimized = try? element.isMinimized()
            guard !cancellation.isCancelled else { return nil }
            let hidden = try? application.attribute(kAXHiddenAttribute, Bool.self)
            guard !cancellation.isCancelled else { return nil }
            let fullscreen = try? element.isFullscreen()
            return (minimized, hidden, fullscreen)
        } ?? nil
    }

    @MainActor
    private func publishFrameResult(_ result: WindowFrameTarget.Result?, screenIdentifier: String?, active: Bool) {
        guard let result, result.attempted else { return }
        if active, result.accepted, let screenIdentifier {
            WindowUtil.refreshCachedPreviewAfterProgrammaticResize(self, targetScreenIdentifier: screenIdentifier)
        } else {
            // An in-flight AX write may have taken effect after cancellation; reconcile without stale UI publication.
            WindowUtil.scheduleCachedWindowMetadataReconciliation(pid: app.processIdentifier, windowID: id)
        }
    }

    @MainActor
    @discardableResult
    func setWindowFrame(_ targetFrame: CGRect, on targetScreen: NSScreen? = nil) async -> Bool {
        if WindowActionRequest.current == nil {
            return await WindowActionRequest.run([PreviewWindowIdentity(self)]) { _ in await self.setWindowFrame(targetFrame, on: targetScreen) } ?? false
        }
        guard WindowActionRequest.current?.contains(PreviewWindowIdentity(self)) == true else { return false }
        let context = WindowFrameContext(), target = frameTarget
        guard let screenIdentifier = targetScreen?.uniqueIdentifier() ?? context.screen(containing: targetFrame)?.identifier else { return false }
        let result = await WindowFrameTransactions.run(for: target.ownerPID) { cancellation in
            target.apply(targetFrame, primaryMaxY: context.primaryMaxY, cancellation: cancellation, captureFrame: false)
        }
        publishFrameResult(result, screenIdentifier: screenIdentifier, active: !Task.isCancelled)
        return !Task.isCancelled && result?.applied == true
    }

    @MainActor
    func setWindowFrameResult(_ targetFrame: CGRect, on screen: NSScreen,
                              isRequestActive: @escaping @MainActor () -> Bool) async -> WindowFramePlacementResult
    {
        if WindowActionRequest.current == nil {
            return await WindowActionRequest.run([PreviewWindowIdentity(self)]) { _ in await self.setWindowFrameResult(targetFrame, on: screen, isRequestActive: isRequestActive) } ?? .failed
        }
        guard WindowActionRequest.current?.contains(PreviewWindowIdentity(self)) == true else { return .failed }
        guard !Task.isCancelled, isRequestActive() else { return .failed }
        let target = frameTarget, context = WindowFrameContext(), screenIdentifier = screen.uniqueIdentifier()
        let result = await WindowFrameTransactions.run(for: target.ownerPID) { cancellation in
            target.apply(targetFrame, primaryMaxY: context.primaryMaxY, cancellation: cancellation)
        }
        defer { publishFrameResult(result, screenIdentifier: screenIdentifier, active: !Task.isCancelled && isRequestActive()) }
        guard !Task.isCancelled, isRequestActive() else { return .failed }
        var actualFrame = result?.frame
        if result?.applied == true {
            for check in 0 ..< 2 {
                if check == 1 {
                    do { try await Task.sleep(nanoseconds: 100_000_000) }
                    catch { return .failed }
                    guard !Task.isCancelled, isRequestActive() else { return .failed }
                    actualFrame = await WindowFrameTransactions.run(for: target.ownerPID) { cancellation in
                        cancellation.isCancelled ? nil : target.frame(primaryMaxY: context.primaryMaxY, cancellation: cancellation)
                    } ?? nil
                }
                guard !Task.isCancelled, isRequestActive() else { return .failed }
                if let actualFrame,
                   abs(actualFrame.minX - targetFrame.minX) <= 1,
                   abs(actualFrame.minY - targetFrame.minY) <= 1,
                   abs(actualFrame.width - targetFrame.width) <= 1,
                   abs(actualFrame.height - targetFrame.height) <= 1
                { return .confirmed }
            }
        }
        DebugLogger.log("WindowPlacement", details: "PID: \(app.processIdentifier), window: \(id), target: \(targetFrame), actual: \(String(describing: actualFrame)), confirmed: false")
        return result?.applied == true && actualFrame != nil ? .unconfirmed : .failed
    }

    @MainActor
    @discardableResult
    func positionWindow(_ rect: WindowPositionRect, size: CGSize? = nil,
                        widthScale: CGFloat? = nil, heightScale: CGFloat? = nil, lockAspectRatio: Bool = false) async -> Bool
    {
        if WindowActionRequest.current == nil {
            return await WindowActionRequest.run([PreviewWindowIdentity(self)]) { _ in await self.positionWindow(rect, size: size, widthScale: widthScale, heightScale: heightScale, lockAspectRatio: lockAspectRatio) } ?? false
        }
        guard WindowActionRequest.current?.contains(PreviewWindowIdentity(self)) == true else { return false }
        let target = frameTarget, context = WindowFrameContext()
        let placement = await WindowFrameTransactions.run(for: target.ownerPID) { cancellation -> (WindowFrameTarget.Result, String)? in
            guard !cancellation.isCancelled, (try? target.element.isFullscreen()) != true,
                  !cancellation.isCancelled, let current = target.frame(primaryMaxY: context.primaryMaxY, cancellation: cancellation),
                  !cancellation.isCancelled, let screen = context.screen(containing: current)
            else { return nil }
            var resolvedSize = size ?? current.size
            if let widthScale, let heightScale {
                let maximum = CGSize(width: screen.bounds.width * min(max(widthScale, 0.2), 1),
                                     height: screen.bounds.height * min(max(heightScale, 0.2), 1))
                if lockAspectRatio, current.width > 0, current.height > 0 {
                    let scale = min(maximum.width / current.width, maximum.height / current.height)
                    resolvedSize = CGSize(width: current.width * scale, height: current.height * scale)
                } else { resolvedSize = maximum }
            }
            return (target.apply(rect.frame(in: screen.bounds, currentSize: resolvedSize), primaryMaxY: context.primaryMaxY,
                                 cancellation: cancellation, captureFrame: false), screen.identifier)
        } ?? nil
        publishFrameResult(placement?.0, screenIdentifier: placement?.1, active: !Task.isCancelled)
        return !Task.isCancelled && placement?.0.applied == true
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
        let ownership = WindowActionRequest.current
        let isActive = { !request.isCancelled && ownership?.mayForeground != false }
        guard isActive(), !ownerApp.isTerminated else {
            request.finish(false)
            return
        }

        WindowInfo.activationCoordinator.begin(request)
        guard isActive() else { request.finish(false); return }

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
                guard isActive(), !window.ownerApp.isTerminated else {
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
                    guard isActive() else {
                        request.finish(false)
                        return
                    }
                    try window.axElement.setAttribute(kAXMainAttribute, true)
                    guard isActive() else {
                        request.finish(false)
                        return
                    }
                    WindowUtil.updateTimestampOptimistically(for: window)
                    request.finish(true)
                    return
                } catch {
                    guard isActive() else { request.finish(false); return }
                    print("Attempt \(attempt + 1) failed to bring window to front: \(error)")
                    DebugLogger.log("WindowActivation", details: "PID: \(window.app.processIdentifier), window: \(window.id), attempt: \(attempt + 1), failed: \(error)")
                    if error is AxError {
                        WindowUtil.removeWindowFromDesktopSpaceCache(with: window.id, in: window.app.processIdentifier)
                    }
                    if attempt + 1 < maxRetries, isActive() {
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
        let showsFeedback = Defaults[.enableActionFeedback] && Defaults[.showMouseFollowsFocusFeedback]
        let mousePosition = mode == .differentDisplayOnly || showsFeedback ? CGEvent(source: nil)?.location : nil

        if mode == .differentDisplayOnly {
            guard let mousePosition else { return }
            let mouseScreen = NSScreen.screenFromQuartzPoint(mousePosition)
            let windowScreen = NSScreen.screenFromQuartzPoint(windowCenter)
            if mouseScreen == windowScreen {
                return
            }
        }

        let moved = CGWarpMouseCursorPosition(windowCenter) == .success
        CGAssociateMouseAndMouseCursorPosition(1)
        if moved, showsFeedback, let mousePosition, mousePosition != windowCenter {
            Task { @MainActor in ActionFeedbackController.mouseFollowedFocus() }
        }
    }

    @discardableResult
    func close(progress: (@Sendable (Int, Int) -> Void)? = nil) -> Bool {
        guard WindowAction.close.isSupported(for: self) else { return false }
        let parent = WindowActionRequest.current
        let request = parent ?? WindowActionOwnership.shared.begin([PreviewWindowIdentity(self)], protect: true, replacingSingles: false)
        defer { if parent == nil { request.finish() } }
        guard request.contains(PreviewWindowIdentity(self)) else { return false }
        guard !isWindowlessApp, !Task.isCancelled else { return false }
        do {
            var finalCloseButton = closeButton
            var nativeTabCount: Int?
            if Defaults[.collapseNativeTabsIntoSingleWindow],
               let group = try axElement.nativeTabGroup(),
               let initialTabs = try group.nativeBackgroundTabs(), !initialTabs.isEmpty
            {
                let total = initialTabs.count + 1
                nativeTabCount = total
                progress?(0, total)
                // Finder rebuilds tab buttons after Close. Keep the group, not its old buttons.
                for remaining in stride(from: initialTabs.count, through: 1, by: -1) {
                    guard !Task.isCancelled else { return false }
                    guard let tabs = try group.nativeBackgroundTabs(), tabs.count == remaining,
                          let tab = tabs.first,
                          var window = try group.attribute(kAXWindowAttribute, AXUIElement.self)
                    else { return false }
                    if try (window.cgWindowId()) == id {
                        guard !Task.isCancelled else { return false }
                        try tab.performAction(kAXPressAction)
                        guard let selectedWindow = try group.attribute(kAXWindowAttribute, AXUIElement.self) else { return false }
                        window = selectedWindow
                    }
                    guard let selectedID = try window.cgWindowId(), selectedID != 0, selectedID != id,
                          let button = try window.closeButton()
                    else { return false }
                    guard !Task.isCancelled else { return false }
                    try button.performAction(kAXPressAction)
                    // A save prompt or refused Close must not advance to another tab.
                    guard try window.closeButton() == nil else { return false }
                    progress?(total - remaining, total)
                }
                // Preserve the original tab until last, even if the tab bar disappears.
                finalCloseButton = try axElement.closeButton()
            }
            guard let finalCloseButton else {
                DebugLogger.log("WindowClose", details: "window: \(id), final Close button unavailable")
                return false
            }
            guard !Task.isCancelled else { return false }
            try finalCloseButton.performAction(kAXPressAction)
            if let nativeTabCount { progress?(nativeTabCount, nativeTabCount) }
            DebugLogger.log("WindowClose", details: "window: \(id), final Close requested")
            return true
        } catch {
            DebugLogger.log("WindowClose", details: "window: \(id), failed: \(error)")
            print("Error closing window")
            return false
        }
    }

    @discardableResult
    func quit(force: Bool) -> Bool {
        let parent = WindowActionRequest.current
        let request = parent ?? WindowActionOwnership.shared.begin([PreviewWindowIdentity(self)], apps: [app.processIdentifier], protect: true, replacingSingles: false)
        defer { if parent == nil { request.finish() } }
        guard request.reserveApp(app.processIdentifier) else { return false }
        return force ? app.forceTerminate() : app.terminate()
    }
}
