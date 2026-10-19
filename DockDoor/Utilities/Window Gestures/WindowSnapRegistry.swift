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
    private struct PendingChange {
        let token: UUID
        var mouseIsDown: Bool
        var revision = 0
    }

    private var pendingChanges: [PreviewWindowIdentity: PendingChange] = [:]

    var hasRecords: Bool { lock.withLock { !records.isEmpty } }

    func record(for window: WindowInfo?) -> Record? {
        guard let window else { return nil }
        return lock.withLock { records[PreviewWindowIdentity(window)] }
    }

    @MainActor
    func snapped(_ window: WindowInfo, restoreFrame: CGRect, origin: Origin = .gesture, confirmedDestination: ManagedSpaceDestination? = nil) async {
        guard origin.isEnabled else { return }
        let target = window.frameTarget, context = WindowFrameContext()
        let fallbackSpace = window.spaceID, hidden = window.app.isHidden
        let topology = WindowSpaces.managedDisplays()
        let candidate = await WindowFrameTransactions.run(for: target.ownerPID) { cancellation -> Record? in
            guard !cancellation.isCancelled else { return nil }
            let reported = target.identity.windowID.cgsSpaces()
            let spaces = Set(reported.isEmpty ? fallbackSpace.map { [CGSSpaceID($0)] } ?? [] : reported)
            guard spaces.count == 1, let spaceID = spaces.first,
                  (confirmedDestination ?? WindowSpaces.destination(forSpaceID: spaceID, in: topology))?.space.kind == .desktop,
                  !cancellation.isCancelled, let frame = target.frame(primaryMaxY: context.primaryMaxY, cancellation: cancellation),
                  let screen = context.screen(containing: frame),
                  confirmedDestination == nil || confirmedDestination?.space.id == spaceID
            else { return nil }
            let record = Record(origin: origin, identity: target.identity, element: target.element, ownerPID: target.ownerPID,
                                snappedFrame: frame, restoreFrame: restoreFrame, screenIdentifier: screen.identifier, spaceID: spaceID)
            guard !cancellation.isCancelled, Self.isLive(record, hidden: hidden, frame: frame, context: context, fallbackSpace: fallbackSpace, cancellation: cancellation) else { return nil }
            return record
        } ?? nil
        guard !Task.isCancelled, origin.isEnabled, let record = candidate else { return }
        lock.withLock {
            if let old = identitiesByWindowID[record.identity.windowID] { records.removeValue(forKey: old) }
            records[record.identity] = record
            identitiesByWindowID[record.identity.windowID] = record.identity
        }
    }

    @discardableResult
    func remove(_ identity: PreviewWindowIdentity) -> Record? {
        lock.withLock {
            pendingChanges.removeValue(forKey: identity)
            guard let removed = records.removeValue(forKey: identity) else { return nil }
            if identitiesByWindowID[identity.windowID] == identity { identitiesByWindowID.removeValue(forKey: identity.windowID) }
            return removed
        }
    }

    @MainActor
    func liveRecord(for window: WindowInfo) async -> Record? {
        guard let record = record(for: window) else { return nil }
        let context = WindowFrameContext()
        guard let frame = await liveFrame(record, context: context), Self.matches(frame, record.snappedFrame) else {
            if !Task.isCancelled { replace(record, with: nil) }
            return nil
        }
        return !Task.isCancelled && isCurrent(record) ? record : nil
    }

    func windowFrameChanged(_ element: AXUIElement, mouseIsDown: Bool) {
        guard hasRecords else { return }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, let windowID = try? element.cgWindowId() else { return }
        guard let identity = lock.withLock({ identitiesByWindowID[windowID] }) else { return }
        let token: UUID? = lock.withLock {
            guard let record = records[identity], record.ownerPID == pid else { return nil }
            if var pending = pendingChanges[identity], pending.token == record.token {
                pending.mouseIsDown = pending.mouseIsDown || mouseIsDown
                pending.revision += 1
                pendingChanges[identity] = pending
                return nil
            }
            pendingChanges[identity] = PendingChange(token: record.token, mouseIsDown: mouseIsDown)
            return record.token
        }
        guard let token else { return }
        queue.async { [weak self] in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                let context = await MainActor.run { WindowFrameContext() }
                while let change = lock.withLock({ self.pendingChanges[identity] }), change.token == token {
                    guard let record = lock.withLock({ self.records[identity] }), record.token == token else {
                        lock.withLock { if self.pendingChanges[identity]?.token == token { self.pendingChanges.removeValue(forKey: identity) } }
                        return
                    }
                    await handleFrameChange(record, mouseIsDown: change.mouseIsDown, context: context)
                    let finished = lock.withLock {
                        guard self.pendingChanges[identity]?.token == token else { return true }
                        guard self.pendingChanges[identity]?.revision == change.revision else { return false }
                        self.pendingChanges.removeValue(forKey: identity)
                        return true
                    }
                    if finished { return }
                }
            }
        }
    }

    private static func isLive(_ record: Record, hidden: Bool, frame: CGRect, context: WindowFrameContext, fallbackSpace: Int?,
                               cancellation: WindowFrameTransactions.Cancellation) -> Bool
    {
        guard !hidden, !cancellation.isCancelled, (try? record.element.isMinimized()) == false,
              !cancellation.isCancelled, (try? record.element.isFullscreen()) == false,
              !cancellation.isCancelled,
              context.screen(containing: frame)?.identifier == record.screenIdentifier else { return false }
        let reported = record.identity.windowID.cgsSpaces()
        let spaces = Set(reported.isEmpty ? fallbackSpace.map { [CGSSpaceID($0)] } ?? [] : reported)
        return spaces == Set([record.spaceID])
    }

    private func liveFrame(_ record: Record, context: WindowFrameContext) async -> CGRect? {
        guard let app = LauncherShortcutResolver.application(forProcessIdentifier: record.identity.pid), !app.isTerminated else { return nil }
        let hidden = app.isHidden
        let fallbackSpace = WindowUtil.readCachedWindows(for: record.identity.pid).first { $0.id == record.identity.windowID }?.spaceID ?? Int(record.spaceID)
        let target = WindowFrameTarget(element: record.element, application: AXUIElementCreateApplication(record.ownerPID), ownerPID: record.ownerPID, identity: record.identity)
        return await WindowFrameTransactions.run(for: record.ownerPID) { cancellation in
            guard !cancellation.isCancelled, (try? record.element.cgWindowId()) == record.identity.windowID,
                  !cancellation.isCancelled, let frame = target.frame(primaryMaxY: context.primaryMaxY, cancellation: cancellation),
                  !cancellation.isCancelled, Self.isLive(record, hidden: hidden, frame: frame, context: context, fallbackSpace: fallbackSpace, cancellation: cancellation)
            else { return nil as CGRect? }
            return frame
        } ?? nil
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
            replace(record, with: nil, matchingFrame: false)
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
                replace(record, with: nil, matchingFrame: false)
            }
        }
    }

    private func isCurrent(_ record: Record) -> Bool {
        lock.withLock { records[record.identity]?.token == record.token && records[record.identity]?.snappedFrame == record.snappedFrame }
    }

    private func handleFrameChange(_ record: Record, mouseIsDown: Bool, context: WindowFrameContext) async {
        guard let frame = await liveFrame(record, context: context) else {
            replace(record, with: nil)
            return
        }
        guard !Self.matches(frame, record.snappedFrame) else { return }
        guard mouseIsDown, isCurrent(record) else {
            replace(record, with: nil)
            return
        }
        if Self.matches(frame.size, record.snappedFrame.size) { await unsnap(record, draggedTo: frame, context: context) }
        else { await resizeNeighbors(of: record, to: frame, context: context) }
    }

    private func apply(_ frame: CGRect, to record: Record, context: WindowFrameContext, source: Record? = nil) async -> WindowFrameTarget.Result? {
        if WindowActionRequest.current == nil {
            return await WindowActionRequest.run([record.identity]) { _ in await self.apply(frame, to: record, context: context, source: source) } ?? nil
        }
        guard WindowActionRequest.current?.contains(record.identity) == true else { return nil }
        let target = WindowFrameTarget(element: record.element, application: AXUIElementCreateApplication(record.ownerPID), ownerPID: record.ownerPID, identity: record.identity)
        let result = await WindowFrameTransactions.run(for: record.ownerPID) { [self] cancellation -> WindowFrameTarget.Result? in
            guard !cancellation.isCancelled, record.origin.isEnabled,
                  source.map({ isCurrent($0) && isCurrent(record) }) ?? lock.withLock({ pendingChanges[record.identity]?.token == record.token })
            else { return nil }
            let result = target.apply(frame, primaryMaxY: context.primaryMaxY, cancellation: cancellation, preservesSnapRecord: true)
            if source != nil {
                // Publish the linked frame before the next queued AX read can observe its notification.
                if result.applied, let actual = result.frame, Self.matches(actual, frame, tolerance: 1) {
                    var updated = record
                    updated.snappedFrame = actual
                    replace(record, with: updated)
                } else { replace(record, with: nil) }
            }
            return result
        } ?? nil
        if result?.attempted == true {
            await MainActor.run {
                if let window = WindowUtil.readCachedWindows(for: record.identity.pid).first(where: { $0.id == record.identity.windowID }) {
                    WindowUtil.refreshCachedPreviewAfterProgrammaticResize(window, targetScreenIdentifier: record.screenIdentifier)
                } else {
                    WindowUtil.scheduleCachedWindowMetadataReconciliation(pid: record.identity.pid, windowID: record.identity.windowID)
                }
            }
        }
        return result
    }

    private func unsnap(_ record: Record, draggedTo frame: CGRect, context: WindowFrameContext) async {
        guard isCurrent(record) else { return }
        replace(record, with: nil)
        guard let screen = context.screen(containing: frame) else { return }
        let bounds = screen.bounds
        let size = CGSize(width: min(record.restoreFrame.width, bounds.width), height: min(record.restoreFrame.height, bounds.height))
        let cursorX = await MainActor.run { DockObserver.getMousePosition().x }
        let fraction = frame.width > 0 ? min(1, max(0, (cursorX - frame.minX) / frame.width)) : 0.5
        let x = min(max(cursorX - fraction * size.width, bounds.minX), bounds.maxX - size.width)
        let y = min(max(frame.maxY - size.height, bounds.minY), bounds.maxY - size.height)
        _ = await apply(CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size), to: record, context: context)
    }

    private func resizeNeighbors(of record: Record, to frame: CGRect, context: WindowFrameContext) async {
        let neighbors = lock.withLock {
            records.values.filter { $0.identity != record.identity && $0.origin == record.origin && $0.screenIdentifier == record.screenIdentifier && $0.spaceID == record.spaceID }
        }
        let possible = Self.linkedFrames([record.snappedFrame] + neighbors.map(\.snappedFrame), movingFirstTo: frame)
        var eligible: [Record] = []
        for (index, neighbor) in neighbors.enumerated() where possible[index + 1] != nil {
            guard let actual = await liveFrame(neighbor, context: context), Self.matches(actual, neighbor.snappedFrame) else {
                replace(neighbor, with: nil); continue
            }
            eligible.append(neighbor)
        }
        _ = await WindowActionRequest.run([record.identity] + eligible.map(\.identity), atomic: true) { [self] _ in
            let targets = Self.linkedFrames([record.snappedFrame] + eligible.map(\.snappedFrame), movingFirstTo: frame)
            for (index, neighbor) in eligible.enumerated() {
                guard isCurrent(record) else { return }
                guard let target = targets[index + 1], isCurrent(neighbor) else { continue }
                guard let result = await apply(target, to: neighbor, context: context, source: record) else { continue }
                if !result.applied || result.frame.map({ !Self.matches($0, target, tolerance: 1) }) != false {
                    DebugLogger.log("WindowSnapping", details: "Neighbor refused resize: PID \(neighbor.identity.pid), window \(neighbor.identity.windowID)")
                }
            }
            var updated = record
            updated.snappedFrame = frame
            replace(record, with: updated)
        }
    }

    private func replace(_ record: Record, with updated: Record?, matchingFrame: Bool = true) {
        lock.withLock {
            guard records[record.identity]?.token == record.token,
                  (!matchingFrame && updated == nil) || records[record.identity]?.snappedFrame == record.snappedFrame else { return }
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
