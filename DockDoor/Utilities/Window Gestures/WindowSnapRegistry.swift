import AppKit
import ApplicationServices
import Defaults

final class WindowSnapRegistry: @unchecked Sendable {
    enum Origin: Equatable {
        case gesture
        case tiling(UUID)

        var isEnabled: Bool {
            switch self {
            case .gesture: Defaults[.enableWindowGestures]
            case .tiling: Defaults[.linkTiledWindowsWhenResizing]
            }
        }
    }

    struct Record {
        let origin: Origin
        let identity: PreviewWindowIdentity
        let token = UUID()
        let element: AXUIElement
        let ownerPID: pid_t
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
    private var identitiesByWindowID: [CGWindowID: PreviewWindowIdentity] = [:]
    private var pendingChanges: Set<PreviewWindowIdentity> = []

    var hasRecords: Bool { lock.withLock { !records.isEmpty } }

    func record(for window: WindowInfo?) -> Record? {
        guard let window else { return nil }
        return lock.withLock { records[PreviewWindowIdentity(window)] }
    }

    func snapped(_ window: WindowInfo, restoreFrame: CGRect, origin: Origin = .gesture, confirmedDestination: ManagedSpaceDestination? = nil) {
        guard origin.isEnabled else { return }
        let spaces = WindowSpaces.sourceSpaceIDs(for: window)
        guard spaces.count == 1, let spaceID = spaces.first,
              (confirmedDestination ?? WindowSpaces.destination(forSpaceID: spaceID))?.space.kind == .desktop,
              let frame = window.currentWindowFrame(),
              let screen = NSScreen.screen(containing: frame)
        else { return }
        guard confirmedDestination == nil || confirmedDestination?.space.id == spaceID else { return }
        let record = Record(origin: origin, identity: PreviewWindowIdentity(window), element: window.axElement, ownerPID: window.ownerApp.processIdentifier,
                            snappedFrame: frame, restoreFrame: restoreFrame,
                            screenIdentifier: screen.uniqueIdentifier(), spaceID: spaceID)
        guard isLive(record, window: window, frame: frame) else { return }
        lock.withLock {
            if let old = identitiesByWindowID[record.identity.windowID] { records.removeValue(forKey: old) }
            records[record.identity] = record
            identitiesByWindowID[record.identity.windowID] = record.identity
        }
    }

    @discardableResult
    func remove(_ identity: PreviewWindowIdentity) -> Record? {
        lock.withLock {
            guard let removed = records.removeValue(forKey: identity) else { return nil }
            if identitiesByWindowID[identity.windowID] == identity { identitiesByWindowID.removeValue(forKey: identity.windowID) }
            return removed
        }
    }

    func liveRecord(for window: WindowInfo) -> Record? {
        guard let record = record(for: window) else { return nil }
        guard let frame = window.currentWindowFrame(), Self.matches(frame, record.snappedFrame), isLive(record, window: window, frame: frame) else {
            replace(record, with: nil)
            return nil
        }
        return record
    }

    func windowFrameChanged(_ element: AXUIElement) {
        guard hasRecords else { return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, let windowID = try? element.cgWindowId() else { return }
        guard let identity = lock.withLock({ identitiesByWindowID[windowID] }) else { return }
        let token: UUID? = lock.withLock {
            guard let record = records[identity], record.ownerPID == pid, pendingChanges.insert(identity).inserted else { return nil }
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

    private func resolve(_ record: Record) -> WindowInfo? {
        guard let app = LauncherShortcutResolver.application(forProcessIdentifier: record.identity.pid), !app.isTerminated,
              (try? record.element.cgWindowId()) == record.identity.windowID
        else { return nil }
        return WindowUtil.windowInfo(for: record.element, app: app, windowID: record.identity.windowID)
    }

    private func isLive(_ record: Record, window: WindowInfo, frame: CGRect) -> Bool {
        !window.app.isHidden &&
            (try? record.element.isMinimized()) == false &&
            (try? record.element.isFullscreen()) == false &&
            WindowSpaces.sourceSpaceIDs(for: window) == Set([record.spaceID]) &&
            NSScreen.screen(containing: frame)?.uniqueIdentifier() == record.screenIdentifier
    }

    func removeDisabledRecords() {
        let gestures = Defaults[.enableWindowGestures]
        let tiling = Defaults[.linkTiledWindowsWhenResizing]
        let stale = lock.withLock {
            records.values.filter { record in
                switch record.origin {
                case .gesture: !gestures
                case .tiling: !tiling
                }
            }
        }
        for record in stale {
            replace(record, with: nil)
        }
    }

    func removeAll(for pid: pid_t) {
        let identities = lock.withLock { records.keys.filter { $0.pid == pid } }
        for identity in identities {
            remove(identity)
        }
    }

    func remove(windowID: CGWindowID) {
        if let identity = lock.withLock({ identitiesByWindowID[windowID] }) { remove(identity) }
    }

    func reconcileCachedWindows(_ windows: [WindowInfo]) {
        guard hasRecords else { return }
        let latest = Dictionary(windows.map { (PreviewWindowIdentity($0), $0) }, uniquingKeysWith: { _, newest in newest })
        let invalidated: [(PreviewWindowIdentity, UUID)] = lock.withLock {
            guard !records.isEmpty else { return [] }
            return latest.values.compactMap { window in
                let identity = PreviewWindowIdentity(window)
                guard let record = records[identity] else { return nil }
                let invalid = window.isMinimized || window.isHidden || window.isFullscreen == true ||
                    window.spaceID.map { $0 != Int(record.spaceID) } == true ||
                    window.screenIdentifier.map { $0 != record.screenIdentifier } == true
                return invalid ? (identity, record.token) : nil
            }
        }
        guard !invalidated.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            for (identity, token) in invalidated {
                guard let record = lock.withLock({ self.records[identity] }), record.token == token else { continue }
                replace(record, with: nil)
            }
        }
    }

    private func isCurrent(_ record: Record) -> Bool {
        lock.withLock { records[record.identity]?.token == record.token && records[record.identity]?.snappedFrame == record.snappedFrame }
    }

    private func handleFrameChange(_ record: Record) {
        guard let window = resolve(record), let frame = window.currentWindowFrame(), isLive(record, window: window, frame: frame) else {
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
        resolve(record)?.applyFrame(CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size))
    }

    private func resizeNeighbors(of record: Record, to frame: CGRect) {
        let neighbors = lock.withLock {
            records.values.filter { $0.identity != record.identity && $0.origin == record.origin && $0.screenIdentifier == record.screenIdentifier && $0.spaceID == record.spaceID }
        }
        let possible = Self.linkedFrames([record.snappedFrame] + neighbors.map(\.snappedFrame), movingFirstTo: frame)
        var eligible: [(Record, WindowInfo)] = []
        for (index, neighbor) in neighbors.enumerated() where possible[index + 1] != nil {
            guard let window = resolve(neighbor), let actual = window.currentWindowFrame(),
                  Self.matches(actual, neighbor.snappedFrame), isLive(neighbor, window: window, frame: actual)
            else { replace(neighbor, with: nil); continue }
            eligible.append((neighbor, window))
        }
        let targets = Self.linkedFrames([record.snappedFrame] + eligible.map(\.0.snappedFrame), movingFirstTo: frame)
        for (index, member) in eligible.enumerated() {
            guard isCurrent(record) else { return }
            let (neighbor, window) = member
            guard let target = targets[index + 1], isCurrent(neighbor) else { continue }
            let applied = window.applyFrame(target)
            if applied, let actual = window.currentWindowFrame(), Self.matches(actual, target, tolerance: 1) {
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
            guard records[record.identity]?.token == record.token, updated == nil || records[record.identity]?.snappedFrame == record.snappedFrame else { return }
            records[record.identity] = updated
            if updated == nil, identitiesByWindowID[record.identity.windowID] == record.identity {
                identitiesByWindowID.removeValue(forKey: record.identity.windowID)
            }
        }
    }

    private enum Edge: CaseIterable {
        case left, right, bottom, top
        var opposite: Edge {
            switch self {
            case .left: .right
            case .right: .left
            case .bottom: .top
            case .top: .bottom
            }
        }

        var vertical: Bool { self == .left || self == .right }

        func coordinate(_ frame: CGRect) -> CGFloat {
            switch self {
            case .left: frame.minX
            case .right: frame.maxX
            case .bottom: frame.minY
            case .top: frame.maxY
            }
        }

        func setting(_ frame: CGRect, to line: CGFloat) -> CGRect {
            switch self {
            case .left: CGRect(x: line, y: frame.minY, width: frame.maxX - line, height: frame.height)
            case .right: CGRect(x: frame.minX, y: frame.minY, width: line - frame.minX, height: frame.height)
            case .bottom: CGRect(x: frame.minX, y: line, width: frame.width, height: frame.maxY - line)
            case .top: CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: line - frame.minY)
            }
        }
    }

    static func linkedFrames(_ frames: [CGRect], movingFirstTo newFrame: CGRect) -> [Int: CGRect] {
        guard let original = frames.first else { return [:] }
        var result = [0: newFrame]
        for edge in Edge.allCases {
            let oldLine = edge.coordinate(original), newLine = edge.coordinate(newFrame)
            guard abs(newLine - oldLine) > 0.5 else { continue }
            var pending = [(0, edge)]
            var visited: Set<Int> = [0]
            var cursor = 0
            while cursor < pending.count {
                let (index, boundary) = pending[cursor]
                cursor += 1
                let opposite = boundary.opposite
                for candidate in frames.indices where !visited.contains(candidate) {
                    let a = frames[index], b = frames[candidate]
                    let overlaps = boundary.vertical
                        ? min(a.maxY, b.maxY) > max(a.minY, b.minY)
                        : min(a.maxX, b.maxX) > max(a.minX, b.minX)
                    guard overlaps, abs(opposite.coordinate(b) - oldLine) <= adjacencyTolerance else { continue }
                    let target = opposite.setting(result[candidate] ?? b, to: newLine)
                    guard target.width >= minimumSize, target.height >= minimumSize else { continue }
                    result[candidate] = target
                    visited.insert(candidate)
                    pending.append((candidate, opposite))
                }
            }
        }
        return result
    }

    static func neighborFrame(_ neighbor: CGRect, following old: CGRect, to new: CGRect) -> CGRect? {
        linkedFrames([old, neighbor], movingFirstTo: new)[1]
    }

    private static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = WindowSnapRegistry.tolerance) -> Bool {
        abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance &&
            abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }

    private static func matches(_ lhs: CGSize, _ rhs: CGSize) -> Bool {
        abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
    }
}
