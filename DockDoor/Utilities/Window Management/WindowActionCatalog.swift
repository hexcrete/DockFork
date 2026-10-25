import AppKit
import Defaults

final class WindowActionRequest: @unchecked Sendable {
    fileprivate final class Completion: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        var isComplete: Bool { lock.withLock { done } }
        func wait() async {
            await withCheckedContinuation { waiter in
                let ready = lock.withLock {
                    if done { return true }
                    waiters.append(waiter); return false
                }
                if ready { waiter.resume() }
            }
        }

        func finish() {
            let ready = lock.withLock {
                done = true
                let ready = waiters; waiters.removeAll(); return ready
            }
            for waiter in ready {
                waiter.resume()
            }
        }
    }

    @TaskLocal static var current: WindowActionRequest?
    let token: UUID
    let admitted: [PreviewWindowIdentity]
    let rejected: [PreviewWindowIdentity]
    private let owner: WindowActionOwnership
    fileprivate let completion: Completion
    private let predecessors: [Completion]

    fileprivate init(token: UUID, admitted: [PreviewWindowIdentity], rejected: [PreviewWindowIdentity], owner: WindowActionOwnership,
                     completion: Completion, predecessors: [Completion] = [])
    {
        self.token = token
        self.admitted = admitted
        self.rejected = rejected
        self.owner = owner
        self.completion = completion
        self.predecessors = predecessors
    }

    func contains(_ identity: PreviewWindowIdentity) -> Bool { owner.contains(identity, token: token) }
    func containsApp(_ pid: pid_t) -> Bool { owner.containsApp(pid, token: token) }
    func reserveApp(_ pid: pid_t) -> Bool { owner.reserveApp(pid, token: token) }
    var mayForeground: Bool { owner.mayForeground(token: token) }
    func finish(_ identity: PreviewWindowIdentity) { owner.finish(identity, token: token) }
    func finish() { owner.finish(token: token); completion.finish() }
    var predecessorsResolved: Bool { predecessors.allSatisfy(\.isComplete) }
    func waitForPredecessors() async { for predecessor in predecessors {
        await predecessor.wait()
    } }
    func onSuperseded(_ cancel: @escaping @Sendable () -> Void) { owner.onSuperseded(token: token, cancel: cancel) }

    static func run<T>(_ targets: [PreviewWindowIdentity], apps: Set<pid_t> = [], protect: Bool = false,
                       atomic: Bool = false, operation: @escaping (WindowActionRequest) async -> T) async -> T?
    {
        guard !Task.isCancelled else { return nil }
        let parent = current
        let request = parent ?? WindowActionOwnership.shared.begin(targets, apps: apps, protect: protect, atomic: atomic)
        defer { if parent == nil { request.finish() } }
        guard targets.contains(where: request.contains), !atomic || targets.allSatisfy(request.contains) else { return nil }
        if parent != nil { return await operation(request) }
        let task = Task {
            await request.waitForPredecessors()
            guard !Task.isCancelled else { return nil as T? }
            return await $current.withValue(request) { await operation(request) }
        }
        request.onSuperseded { task.cancel() }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    deinit { finish() }
}

final class WindowActionOwnership: @unchecked Sendable {
    static let shared = WindowActionOwnership()

    private struct Record {
        var targets: Set<PreviewWindowIdentity>
        var apps: Set<pid_t>
        var protected: Bool
        var superseded = false
        var cancel: (@Sendable () -> Void)?
        let completion: WindowActionRequest.Completion
    }

    private let lock = NSLock()
    private var records: [UUID: Record] = [:]
    private var latestForegroundToken: UUID?

    func begin(_ targets: [PreviewWindowIdentity], apps: Set<pid_t> = [], protect: Bool = false, atomic: Bool = false,
               replacingSingles: Bool = true) -> WindowActionRequest
    {
        var seen = Set<PreviewWindowIdentity>()
        let targets = targets.filter { seen.insert($0).inserted }
        let token = UUID()
        var admitted: [PreviewWindowIdentity] = []
        var claimedApps = Set<pid_t>()
        var cancellations: [@Sendable () -> Void] = []
        let completion = WindowActionRequest.Completion()
        var predecessors: [WindowActionRequest.Completion] = []
        lock.lock()
        let blockedApps = Set(apps.filter { pid in
            records.values.contains { ((!$0.superseded && $0.protected) || !replacingSingles) && ($0.apps.contains(pid) || $0.targets.contains { $0.pid == pid }) }
        })
        if atomic, !blockedApps.isEmpty || targets.contains(where: { target in
            records.values.contains { ((!$0.superseded && $0.protected) || !replacingSingles) && ($0.apps.contains(target.pid) || $0.targets.contains(target)) }
        }) {
            lock.unlock()
            return WindowActionRequest(token: token, admitted: [], rejected: targets, owner: self, completion: completion)
        }
        for target in targets {
            guard !blockedApps.contains(target.pid) else { continue }
            let overlaps = records.filter { _, record in
                record.apps.contains(target.pid) || record.targets.contains(target) ||
                    (apps.contains(target.pid) && record.targets.contains { $0.pid == target.pid })
            }
            guard !overlaps.values.contains(where: { (!$0.superseded && $0.protected) || !replacingSingles }) else { continue }
            for (previous, record) in overlaps {
                predecessors.append(record.completion)
                if !record.superseded {
                    if let cancel = record.cancel { cancellations.append(cancel) }
                    // Retain its cleanup barrier until the in-flight AX transaction returns.
                    records[previous]?.superseded = true
                    records[previous]?.cancel = nil
                }
            }
            admitted.append(target)
            if apps.contains(target.pid) { claimedApps.insert(target.pid) }
        }
        if !admitted.isEmpty {
            latestForegroundToken = token
            records[token] = Record(targets: Set(admitted), apps: claimedApps,
                                    protected: protect || targets.count > 1 || !claimedApps.isEmpty, completion: completion)
        }
        lock.unlock()
        // Cancelling can resume tasks; never invoke a callback under the ownership lock.
        for cancel in cancellations {
            cancel()
        }
        let accepted = Set(admitted)
        return WindowActionRequest(token: token, admitted: admitted, rejected: targets.filter { !accepted.contains($0) }, owner: self,
                                   completion: completion, predecessors: predecessors)
    }

    fileprivate func contains(_ identity: PreviewWindowIdentity, token: UUID) -> Bool {
        lock.withLock { records[token].map { !$0.superseded && ($0.targets.contains(identity) || $0.apps.contains(identity.pid)) } == true }
    }

    fileprivate func containsApp(_ pid: pid_t, token: UUID) -> Bool {
        lock.withLock { records[token].map { !$0.superseded && ($0.apps.contains(pid) || $0.targets.contains { $0.pid == pid }) } == true }
    }

    fileprivate func mayForeground(token: UUID) -> Bool {
        lock.withLock { latestForegroundToken == token && records[token]?.superseded == false }
    }

    fileprivate func reserveApp(_ pid: pid_t, token: UUID) -> Bool {
        lock.withLock {
            guard var record = records[token], !record.superseded,
                  record.apps.contains(pid) || record.targets.contains(where: { $0.pid == pid }) else { return false }
            if record.apps.contains(pid) { return true }
            guard !records.contains(where: { $0.key != token && ($0.value.apps.contains(pid) || $0.value.targets.contains { $0.pid == pid }) }) else { return false }
            record.apps.insert(pid)
            record.protected = true
            records[token] = record
            return true
        }
    }

    fileprivate func onSuperseded(token: UUID, cancel: @escaping @Sendable () -> Void) {
        let inactive = lock.withLock {
            guard records[token]?.superseded == false else { return true }
            records[token]?.cancel = cancel
            return false
        }
        if inactive { cancel() }
    }

    fileprivate func finish(_ identity: PreviewWindowIdentity, token: UUID) {
        lock.withLock {
            guard var record = records[token] else { return }
            record.targets.remove(identity)
            if !record.targets.contains(where: { $0.pid == identity.pid }) { record.apps.remove(identity.pid) }
            if record.targets.isEmpty { records.removeValue(forKey: token) }
            else { records[token] = record }
        }
    }

    fileprivate func finish(token: UUID) { _ = lock.withLock { records.removeValue(forKey: token) } }
}

enum PreviewBatchTogglePolicy {
    static func targetState(_ states: [Bool]) -> Bool? {
        states.isEmpty ? nil : !states.allSatisfy { $0 }
    }
}

struct WindowActionGroup: Identifiable {
    let id: WindowAction.Group
    let actions: [WindowAction]
}

extension WindowAction {
    enum TargetScope: Equatable {
        case initiator
        case selectedWindows
        case selectedApps
        case allWindowsOfSelectedApps
    }

    var targetScope: TargetScope {
        switch self {
        case .openAppWindow, .toggleWindowSelection, .selectAllWindows, .none:
            .initiator
        case .hide, .quit, .forceQuit, .openNewWindow:
            .selectedApps
        case .closeAllWindows, .minimizeAllWindows:
            .allWindowsOfSelectedApps
        case .close, .minimize, .toggleFullScreen, .maximize, .bringToCurrentSpace,
             .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center, .autoTileSelectedWindows:
            .selectedWindows
        }
    }

    func selectedPreviewTargets(for initiator: WindowInfo, from selection: [WindowInfo]?) -> [WindowInfo]? {
        guard targetScope != .initiator, let selection,
              selection.contains(where: { PreviewWindowIdentity($0) == PreviewWindowIdentity(initiator) })
        else { return nil }
        if self == .toggleFullScreen,
           !selection.contains(where: { !$0.isWindowlessApp && isSupported(for: $0) && $0.isFullscreen == true })
        { return initiator.isWindowlessApp ? [] : nil }
        return selection
    }

    func isAvailable(for window: WindowInfo, batchTargets: [WindowInfo]?) -> Bool {
        guard let selected = selectedPreviewTargets(for: window, from: batchTargets) else { return isAvailable(for: window) }
        let targets = previewTargets(from: selected, allowFullscreenEntry: false)
        return targets.contains { self == .toggleFullScreen || isAvailable(for: $0) }
    }

    func isSupported(for window: WindowInfo) -> Bool {
        if window.isFullscreen == true,
           positionRect != nil || [.minimize, .minimizeAllWindows, .autoTileSelectedWindows, .bringToCurrentSpace].contains(self)
        { return false }
        guard window.isWineWindow else { return true }
        switch self {
        case .quit, .forceQuit, .hide, .bringToCurrentSpace, .openAppWindow,
             .maximize, .center, .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .autoTileSelectedWindows, .toggleWindowSelection, .selectAllWindows:
            return true
        case .close, .closeAllWindows, .minimize, .minimizeAllWindows, .toggleFullScreen, .openNewWindow, .none:
            return false
        }
    }

    func usesConfirmedSingleWindowAction(on window: WindowInfo) -> Bool {
        positionRect != nil || [.minimize, .hide, .toggleFullScreen, .closeAllWindows, .minimizeAllWindows, .autoTileSelectedWindows,
                                .quit, .forceQuit, .openNewWindow, .bringToCurrentSpace].contains(self) ||
            (!window.isWindowlessApp && [.openAppWindow, .close].contains(self))
    }

    static let spaceMenuActions: [WindowAction] = [
        .close, .minimize, .autoTileSelectedWindows, .bringToCurrentSpace, .hide,
        .quit, .forceQuit, .openNewWindow, .selectAllWindows, .toggleFullScreen,
    ]

    func spaceTargets(from residents: [WindowInfo]) -> [WindowInfo] {
        guard self != .openAppWindow, self != .toggleWindowSelection, self != .none else { return [] }
        let targets = previewTargets(from: residents)
        if self == .bringToCurrentSpace {
            return targets.filter { WindowSpaces.sourceSpaceIDs(for: $0).count == 1 }
        }
        return targets
    }

    func spaceMenuTitle(for targets: [WindowInfo]) -> String {
        let singular = targets.count == 1
        let oneApp = Set(targets.map(\.app.processIdentifier)).count == 1
        switch self {
        case .close:
            return singular ? String(localized: "Close Window on This Space") : String(localized: "Close All Windows on This Space")
        case .minimize:
            if batchTargetState(for: targets) == false {
                return singular ? String(localized: "Un-minimize Window on This Space") : String(localized: "Un-minimize All Windows on This Space")
            }
            return singular ? String(localized: "Minimize Window on This Space") : String(localized: "Minimize All Windows on This Space")
        case .autoTileSelectedWindows:
            return singular ? String(localized: "Auto Tile Window on This Space") : String(localized: "Auto Tile Windows on This Space")
        case .bringToCurrentSpace:
            return singular ? String(localized: "Bring Window to Current Space") : String(localized: "Bring All Windows to Current Space")
        case .hide:
            if batchTargetState(for: targets) == false {
                return oneApp ? String(localized: "Unhide App on This Space") : String(localized: "Unhide Apps on This Space")
            }
            return oneApp ? String(localized: "Hide App on This Space") : String(localized: "Hide Apps on This Space")
        case .quit:
            return oneApp ? String(localized: "Quit App on This Space") : String(localized: "Quit Apps on This Space")
        case .forceQuit:
            return oneApp ? String(localized: "Force Quit App on This Space") : String(localized: "Force Quit Apps on This Space")
        case .openNewWindow:
            return oneApp ? String(localized: "Open New Window for App on This Space") : String(localized: "Open New Window for Apps on This Space")
        case .selectAllWindows:
            return singular ? String(localized: "Select Window on This Space") : String(localized: "Select All Windows on This Space")
        case .toggleFullScreen:
            return String(localized: "Exit Full Screen")
        default:
            return localizedName
        }
    }

    var spaceMenuHelp: String? {
        switch self {
        case .hide, .quit, .forceQuit:
            String(localized: "This action affects these apps, including their windows on other Spaces.")
        case .openNewWindow:
            String(localized: "Requests one new window per app. Apps decide where new windows open.")
        default:
            nil
        }
    }

    func autoTilingDirection(windowCount: Int, fillActionsAutoTile: Bool) -> PreviewTilingLayout.Direction? {
        guard self == .autoTileSelectedWindows || (windowCount > 1 && fillActionsAutoTile) else { return nil }
        return tilingDirection
    }

    var tilingDirection: PreviewTilingLayout.Direction? {
        switch self {
        case .autoTileSelectedWindows: .neutral
        case .fillLeftHalf: .left
        case .fillRightHalf: .right
        case .fillTopHalf: .top
        case .fillBottomHalf: .bottom
        case .fillTopLeftQuarter: .topLeft
        case .fillTopRightQuarter: .topRight
        case .fillBottomLeftQuarter: .bottomLeft
        case .fillBottomRightQuarter: .bottomRight
        default: nil
        }
    }

    func appliesToSelectedWindow(_ window: WindowInfo) -> Bool {
        !window.isWindowlessApp || isQuitAction || self == .openNewWindow
    }

    func previewTargets(from windows: [WindowInfo], allowFullscreenEntry: Bool = true) -> [WindowInfo] {
        var targets = windows.filter { appliesToSelectedWindow($0) }
        if targetScope == .allWindowsOfSelectedApps {
            var apps = Set<pid_t>()
            targets = targets.flatMap { window -> [WindowInfo] in
                guard apps.insert(window.app.processIdentifier).inserted else { return [] }
                let cached = WindowUtil.readCachedWindows(for: window.app.processIdentifier).filter { !$0.isWindowlessApp }
                return cached.isEmpty ? windows.filter { $0.app.processIdentifier == window.app.processIdentifier && !$0.isWindowlessApp } : cached
            }
        }
        var seen = Set<PreviewWindowIdentity>()
        targets = targets.filter { isSupported(for: $0) && seen.insert(PreviewWindowIdentity($0)).inserted }
        if self == .toggleFullScreen, !allowFullscreenEntry || targets.count > 1 { targets.removeAll { $0.isFullscreen != true } }
        if self == .hide {
            let eligibleApps = Set(batchTargets(from: targets).map(\.app.processIdentifier))
            targets.removeAll { !eligibleApps.contains($0.app.processIdentifier) }
        }
        if autoTilingDirection(windowCount: targets.count, fillActionsAutoTile: Defaults[.fillActionsAutoTileSelection]) != nil {
            targets = WindowUtil.autoTileTargets(from: targets)
        }
        return targets
    }

    func batchTargets(from windows: [WindowInfo]) -> [WindowInfo] {
        var seenApps = Set<pid_t>()
        return windows.filter { window in
            guard appliesToSelectedWindow(window), isSupported(for: window) else { return false }
            guard !isAppWidePreviewAction || seenApps.insert(window.app.processIdentifier).inserted else { return false }
            if self == .toggleFullScreen { return window.isFullscreen == true }
            if self == .hide, !window.app.isHidden {
                let appWindows = WindowUtil.readCachedWindows(for: window.app.processIdentifier)
                if !appWindows.isEmpty, appWindows.allSatisfy({ $0.isFullscreen == true }) { return false }
            }
            return true
        }
    }

    func batchTargetState(for windows: [WindowInfo]) -> Bool? {
        switch self {
        case .minimize, .minimizeAllWindows:
            let candidates = self == .minimizeAllWindows
                ? Set(windows.map(\.app.processIdentifier)).flatMap { WindowUtil.readCachedWindows(for: $0) }
                : windows
            let eligible = candidates.filter { !$0.isWindowlessApp && $0.isFullscreen != true && isSupported(for: $0) }
            return PreviewBatchTogglePolicy.targetState(eligible.map(\.isMinimized))
        case .hide:
            return PreviewBatchTogglePolicy.targetState(batchTargets(from: windows).map(\.app.isHidden))
        default:
            return nil
        }
    }

    var isQuitAction: Bool { self == .quit || self == .forceQuit }

    var isAppWidePreviewAction: Bool {
        switch targetScope {
        case .selectedApps, .allWindowsOfSelectedApps: true
        default: false
        }
    }

    enum Group: String, CaseIterable {
        case window
        case arrange
        case app

        var localizedName: String {
            switch self {
            case .window:
                String(localized: "Window", comment: "Window action menu group")
            case .arrange:
                String(localized: "Arrange", comment: "Window action menu group")
            case .app:
                String(localized: "Application", comment: "Window action menu group")
            }
        }

        var actions: [WindowAction] {
            switch self {
            case .window:
                [.toggleWindowSelection, .selectAllWindows, .openAppWindow, .openNewWindow, .minimize, .hide, .maximize, .toggleFullScreen, .bringToCurrentSpace]
            case .arrange:
                [.autoTileSelectedWindows, .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
                 .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter, .center]
            case .app:
                [.close, .quit, .forceQuit]
            }
        }
    }

    static func availableGroups(for window: WindowInfo, batchTargets: [WindowInfo]? = nil,
                                includeSelectionActions: Bool = false) -> [WindowActionGroup]
    {
        Group.allCases.compactMap { group in
            let actions = group.actions.filter {
                (![.toggleWindowSelection, .selectAllWindows].contains($0) || includeSelectionActions) &&
                    $0.isAvailable(for: window, batchTargets: batchTargets)
            }
            return actions.isEmpty ? nil : WindowActionGroup(id: group, actions: actions)
        }
    }

    func isAvailable(for window: WindowInfo) -> Bool {
        if self == .none || !isSupported(for: window) { return false }

        if window.isWindowlessApp {
            if self == .toggleWindowSelection || self == .selectAllWindows {
                return Defaults[.enableMultiWindowSelection] && Defaults[.enableWindowlessAppSelection]
            }
            return self == .openAppWindow || self == .openNewWindow || isQuitAction || self == .hide
        }

        switch self {
        case .toggleWindowSelection, .selectAllWindows:
            return Defaults[.enableMultiWindowSelection]
        case .autoTileSelectedWindows:
            return true
        case .close:
            return window.closeButton != nil
        case .hide:
            return !batchTargets(from: [window]).isEmpty
        case .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center, .maximize, .toggleFullScreen:
            return !window.isMinimized && !window.isHidden
        default:
            return true
        }
    }

    var positionRect: WindowInfo.WindowPositionRect? {
        switch self {
        case .maximize: .full
        case .fillLeftHalf: .leftHalf
        case .fillRightHalf: .rightHalf
        case .fillTopHalf: .topHalf
        case .fillBottomHalf: .bottomHalf
        case .fillTopLeftQuarter: .topLeftQuarter
        case .fillTopRightQuarter: .topRightQuarter
        case .fillBottomLeftQuarter: .bottomLeftQuarter
        case .fillBottomRightQuarter: .bottomRightQuarter
        case .center: .center
        default: nil
        }
    }

    func feedbackTitle(for window: WindowInfo, batchTargets: [WindowInfo]? = nil) -> String {
        if self == .autoTileSelectedWindows { return String(localized: "Auto Tile") }
        if self == .close || self == .closeAllWindows { return String(localized: "Close") }
        if self == .minimize || self == .minimizeAllWindows {
            return batchTargetState(for: batchTargets ?? [window]) == false
                ? String(localized: "Un-minimize") : String(localized: "Minimize")
        }
        if self == .hide {
            return batchTargetState(for: batchTargets ?? [window]) == false
                ? String(localized: "Unhide App") : String(localized: "Hide App")
        }
        if self == .toggleFullScreen {
            return (batchTargets ?? [window]).contains { isSupported(for: $0) && $0.isFullscreen == true }
                ? String(localized: "Exit Full Screen") : String(localized: "Enter Full Screen")
        }
        if self == .openAppWindow, window.isWindowlessApp { return String(localized: "Activate App") }
        return localizedName
    }

    func menuTitle(for window: WindowInfo, batchTargets: [WindowInfo]? = nil) -> String {
        if self == .toggleWindowSelection {
            return batchTargets == nil ? String(localized: "Add to Selection") : String(localized: "Remove from Selection")
        }
        let hasSelection = batchTargets?.contains { PreviewWindowIdentity($0) == PreviewWindowIdentity(window) } == true
        if self == .openAppWindow {
            if window.isWindowlessApp { return String(localized: "Activate App") }
            return hasSelection ? String(localized: "Open Window (This Window)") : localizedName
        }
        let selected = selectedPreviewTargets(for: window, from: batchTargets)
        if self == .toggleFullScreen, selected == nil {
            if window.isFullscreen == true { return String(localized: "Exit Full Screen") }
            return hasSelection ? String(localized: "Enter Full Screen (This Window)") : String(localized: "Enter Full Screen")
        }
        if let selected {
            let targets = previewTargets(from: selected, allowFullscreenEntry: false)
            let singleWindow = targets.count == 1
            let singleApp = Set(targets.map(\.app.processIdentifier)).count == 1
            if self != .autoTileSelectedWindows,
               autoTilingDirection(windowCount: selected.filter { appliesToSelectedWindow($0) }.count,
                                   fillActionsAutoTile: Defaults[.fillActionsAutoTileSelection]) != nil
            {
                return singleWindow
                    ? String(localized: "Auto Tile Selected Window (\(localizedName))")
                    : String(localized: "Auto Tile Selected Windows (\(localizedName))")
            }
            switch self {
            case .close:
                return singleWindow ? String(localized: "Close Selected Window") : String(localized: "Close Selected Windows")
            case .minimize:
                if batchTargetState(for: selected) == false {
                    return singleWindow ? String(localized: "Un-minimize Selected Window") : String(localized: "Un-minimize Selected Windows")
                }
                return singleWindow ? String(localized: "Minimize Selected Window") : String(localized: "Minimize Selected Windows")
            case .hide:
                if batchTargetState(for: selected) == false {
                    return singleApp ? String(localized: "Unhide Selected App") : String(localized: "Unhide Selected Apps")
                }
                return singleApp ? String(localized: "Hide Selected App") : String(localized: "Hide Selected Apps")
            case .quit:
                return singleApp ? String(localized: "Quit Selected App") : String(localized: "Quit Selected Apps")
            case .forceQuit:
                return singleApp ? String(localized: "Force Quit Selected App") : String(localized: "Force Quit Selected Apps")
            case .openNewWindow:
                return singleApp ? String(localized: "Open New Window for Selected App") : String(localized: "Open New Window for Selected Apps")
            case .closeAllWindows:
                return singleApp ? String(localized: "Close All Windows of Selected App") : String(localized: "Close All Windows of Selected Apps")
            case .minimizeAllWindows:
                if batchTargetState(for: selected) == false {
                    return singleApp ? String(localized: "Un-minimize All Windows of Selected App") : String(localized: "Un-minimize All Windows of Selected Apps")
                }
                return singleApp ? String(localized: "Minimize All Windows of Selected App") : String(localized: "Minimize All Windows of Selected Apps")
            case .toggleFullScreen:
                return singleWindow ? String(localized: "Exit Full Screen for Selected Window") : String(localized: "Exit Full Screen for Selected Windows")
            case .maximize:
                return singleWindow ? String(localized: "Maximize Selected Window") : String(localized: "Maximize Selected Windows")
            case .center:
                return singleWindow ? String(localized: "Center Selected Window") : String(localized: "Center Selected Windows")
            case .autoTileSelectedWindows:
                return singleWindow ? String(localized: "Auto Tile Selected Window") : String(localized: "Auto Tile Selected Windows")
            case .bringToCurrentSpace:
                return singleWindow ? String(localized: "Bring Selected Window to Current Space") : String(localized: "Bring Selected Windows to Current Space")
            case .fillLeftHalf:
                return singleWindow ? String(localized: "Fill Left Half for Selected Window") : String(localized: "Fill Left Half for Selected Windows")
            case .fillRightHalf:
                return singleWindow ? String(localized: "Fill Right Half for Selected Window") : String(localized: "Fill Right Half for Selected Windows")
            case .fillTopHalf:
                return singleWindow ? String(localized: "Fill Top Half for Selected Window") : String(localized: "Fill Top Half for Selected Windows")
            case .fillBottomHalf:
                return singleWindow ? String(localized: "Fill Bottom Half for Selected Window") : String(localized: "Fill Bottom Half for Selected Windows")
            case .fillTopLeftQuarter:
                return singleWindow ? String(localized: "Fill Top Left for Selected Window") : String(localized: "Fill Top Left for Selected Windows")
            case .fillTopRightQuarter:
                return singleWindow ? String(localized: "Fill Top Right for Selected Window") : String(localized: "Fill Top Right for Selected Windows")
            case .fillBottomLeftQuarter:
                return singleWindow ? String(localized: "Fill Bottom Left for Selected Window") : String(localized: "Fill Bottom Left for Selected Windows")
            case .fillBottomRightQuarter:
                return singleWindow ? String(localized: "Fill Bottom Right for Selected Window") : String(localized: "Fill Bottom Right for Selected Windows")
            default: break
            }
        }
        if self == .autoTileSelectedWindows { return String(localized: "Auto Tile Window") }
        return switch self {
        case .minimize where window.isMinimized:
            String(localized: "Un-minimize", comment: "Window action for an already minimized window")
        case .minimizeAllWindows where batchTargetState(for: [window]) == false:
            String(localized: "Un-minimize All Windows")
        case .hide where window.isHidden:
            String(localized: "Unhide App", comment: "Window action for an already hidden app")
        default:
            localizedName
        }
    }

    static func spaceMoveMenuTitle(for window: WindowInfo, batchTargets: [WindowInfo]?) -> String {
        guard let selected = bringToCurrentSpace.selectedPreviewTargets(for: window, from: batchTargets) else {
            return String(localized: "Move to Space", comment: "Space destination menu title")
        }
        return bringToCurrentSpace.previewTargets(from: selected).count == 1
            ? String(localized: "Move Selected Window to Space") : String(localized: "Move Selected Windows to Space")
    }

    func menuIcon(for window: WindowInfo, batchTargets: [WindowInfo]? = nil) -> String {
        if self == .minimize || self == .minimizeAllWindows {
            return batchTargetState(for: batchTargets ?? [window]) == false ? "arrow.up.left.and.arrow.down.right.square" : iconName
        }
        if let selected = selectedPreviewTargets(for: window, from: batchTargets) {
            if self == .hide { return batchTargetState(for: selected) == false ? "eye" : iconName }
        }
        return switch self {
        case .hide where window.isHidden:
            "eye"
        default:
            iconName
        }
    }
}
