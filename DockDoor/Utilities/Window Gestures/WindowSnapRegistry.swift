import AppKit
import ApplicationServices

final class WindowSnapRegistry: @unchecked Sendable {
    struct Record {
        let identity: PreviewWindowIdentity
        let token = UUID()
        let window: WindowInfo
        var snappedFrame: CGRect
        let restoreFrame: CGRect
        let screenIdentifier: String
        let spaceID: CGSSpaceID
    }

    private static let instanceLock = NSLock()
    private static var instance: WindowSnapRegistry?
    static var shared: WindowSnapRegistry {
        instanceLock.withLock {
            if let instance { return instance }
            let registry = WindowSnapRegistry()
            instance = registry
            return registry
        }
    }

    static var existing: WindowSnapRegistry? { instanceLock.withLock { instance } }
    private static let tolerance: CGFloat = 6
    private static let adjacencyTolerance: CGFloat = 8
    private static let minimumSize: CGFloat = 100

    private let queue = DispatchQueue(label: "com.ethanbills.DockDoor.windowGestures.snapRegistry", qos: .userInteractive)
    private let lock = NSLock()
    private var records: [PreviewWindowIdentity: Record] = [:]
    private var pendingChanges: Set<PreviewWindowIdentity> = []

    func record(for window: WindowInfo?) -> Record? {
        guard let window else { return nil }
        return lock.withLock { records[PreviewWindowIdentity(window)] }
    }

    func snapped(_ window: WindowInfo, restoreFrame: CGRect) {
        let spaces = WindowSpaces.sourceSpaceIDs(for: window)
        guard spaces.count == 1, let spaceID = spaces.first,
              WindowSpaces.destination(forSpaceID: spaceID)?.space.kind == .desktop,
              let frame = window.currentWindowFrame(),
              let screen = NSScreen.screen(containing: frame)
        else { return }
        let record = Record(identity: PreviewWindowIdentity(window), window: window,
                            snappedFrame: frame, restoreFrame: restoreFrame,
                            screenIdentifier: screen.uniqueIdentifier(), spaceID: spaceID)
        guard isLive(record, frame: frame) else { return }
        lock.withLock { records[record.identity] = record }
    }

    @discardableResult
    func remove(_ identity: PreviewWindowIdentity) -> Record? {
        lock.withLock { records.removeValue(forKey: identity) }
    }

    func liveRecord(for window: WindowInfo) -> Record? {
        guard let record = record(for: window) else { return nil }
        guard let frame = window.currentWindowFrame(), Self.matches(frame, record.snappedFrame), isLive(record, frame: frame) else {
            replace(record, with: nil)
            return nil
        }
        return record
    }

    func windowFrameChanged(_ element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, let windowID = try? element.cgWindowId() else { return }
        let identity = PreviewWindowIdentity(pid: pid, windowID: windowID)
        let token: UUID? = lock.withLock {
            guard let record = records[identity], pendingChanges.insert(identity).inserted else { return nil }
            return record.token
        }
        guard let token else { return }
        queue.async { [weak self] in
            guard let self else { return }
            lock.withLock { _ = self.pendingChanges.remove(identity) }
            guard let record = lock.withLock({ self.records[identity] }), record.token == token else { return }
            handleFrameChange(record)
        }
    }

    private func isLive(_ record: Record, frame: CGRect) -> Bool {
        let window = record.window
        return !window.app.isTerminated && !window.app.isHidden &&
            (try? window.axElement.isMinimized()) == false &&
            (try? window.axElement.isFullscreen()) == false &&
            WindowSpaces.sourceSpaceIDs(for: window) == Set([record.spaceID]) &&
            NSScreen.screen(containing: frame)?.uniqueIdentifier() == record.screenIdentifier
    }

    private func isCurrent(_ record: Record) -> Bool {
        lock.withLock { records[record.identity]?.token == record.token && records[record.identity]?.snappedFrame == record.snappedFrame }
    }

    private func handleFrameChange(_ record: Record) {
        guard let frame = record.window.currentWindowFrame(), isLive(record, frame: frame) else {
            replace(record, with: nil)
            return
        }
        guard !Self.matches(frame, record.snappedFrame) else { return }
        guard CGEventSource.buttonState(.combinedSessionState, button: .left), isCurrent(record) else {
            replace(record, with: nil)
            return
        }
        if Self.matches(frame.size, record.snappedFrame.size) { unsnap(record, draggedTo: frame) }
        else { resizeNeighbors(of: record, to: frame) }
    }

    private func unsnap(_ record: Record, draggedTo frame: CGRect) {
        guard isCurrent(record) else { return }
        replace(record, with: nil)
        guard let screen = NSScreen.screen(containing: frame) else { return }
        let bounds = screen.snappingFrame
        let size = CGSize(width: min(record.restoreFrame.width, bounds.width), height: min(record.restoreFrame.height, bounds.height))
        let cursorX = DockObserver.getMousePosition().x
        let fraction = frame.width > 0 ? min(1, max(0, (cursorX - frame.minX) / frame.width)) : 0.5
        let x = min(max(cursorX - fraction * size.width, bounds.minX), bounds.maxX - size.width)
        let y = min(max(frame.maxY - size.height, bounds.minY), bounds.maxY - size.height)
        record.window.applyFrame(CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size))
    }

    private func resizeNeighbors(of record: Record, to frame: CGRect) {
        let neighbors = lock.withLock {
            records.values.filter { $0.identity != record.identity && $0.screenIdentifier == record.screenIdentifier && $0.spaceID == record.spaceID }
        }
        for neighbor in neighbors {
            guard isCurrent(record) else { return }
            guard let actual = neighbor.window.currentWindowFrame(), Self.matches(actual, neighbor.snappedFrame), isLive(neighbor, frame: actual) else {
                replace(neighbor, with: nil)
                continue
            }
            guard let target = Self.neighborFrame(neighbor.snappedFrame, following: record.snappedFrame, to: frame), isCurrent(neighbor) else { continue }
            let applied = neighbor.window.applyFrame(target)
            if applied, let actual = neighbor.window.currentWindowFrame(), Self.matches(actual, target, tolerance: 1) {
                var updated = neighbor
                updated.snappedFrame = actual
                replace(neighbor, with: updated)
            } else {
                replace(neighbor, with: nil)
                DebugLogger.log("WindowSnapping", details: "Neighbor refused resize: PID \(neighbor.identity.pid), window \(neighbor.identity.windowID)")
            }
        }
        var updated = record
        updated.snappedFrame = frame
        replace(record, with: updated)
    }

    private func replace(_ record: Record, with updated: Record?) {
        lock.withLock {
            guard records[record.identity]?.token == record.token, records[record.identity]?.snappedFrame == record.snappedFrame else { return }
            records[record.identity] = updated
        }
    }

    static func neighborFrame(_ neighbor: CGRect, following old: CGRect, to new: CGRect) -> CGRect? {
        var result = neighbor
        var moved = false
        if min(neighbor.maxY, old.maxY) > max(neighbor.minY, old.minY) {
            if abs(neighbor.maxX - old.minX) <= adjacencyTolerance, abs(new.minX - old.minX) > 0.5 {
                result.size.width = new.minX - result.minX
                moved = true
            } else if abs(neighbor.minX - old.maxX) <= adjacencyTolerance, abs(new.maxX - old.maxX) > 0.5 {
                result.origin.x = new.maxX
                result.size.width = neighbor.maxX - new.maxX
                moved = true
            }
        }
        if min(neighbor.maxX, old.maxX) > max(neighbor.minX, old.minX) {
            if abs(neighbor.maxY - old.minY) <= adjacencyTolerance, abs(new.minY - old.minY) > 0.5 {
                result.size.height = new.minY - result.minY
                moved = true
            } else if abs(neighbor.minY - old.maxY) <= adjacencyTolerance, abs(new.maxY - old.maxY) > 0.5 {
                result.origin.y = new.maxY
                result.size.height = neighbor.maxY - new.maxY
                moved = true
            }
        }
        return moved && result.width >= minimumSize && result.height >= minimumSize ? result : nil
    }

    private static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = WindowSnapRegistry.tolerance) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    private static func matches(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}
