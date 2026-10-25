import ApplicationServices
import Defaults
import SwiftUI

struct PreviewWindowIdentity: Hashable, Sendable {
    let pid: pid_t
    let windowID: CGWindowID

    init(pid: pid_t, windowID: CGWindowID) {
        self.pid = pid
        self.windowID = windowID
    }

    init(_ window: WindowInfo) {
        self.init(pid: window.app.processIdentifier, windowID: window.id)
    }
}

struct OrderedPreviewSelection: Equatable {
    private(set) var identities: [PreviewWindowIdentity] = []
    private(set) var membership: Set<PreviewWindowIdentity> = []

    mutating func toggle(_ identity: PreviewWindowIdentity) {
        if membership.remove(identity) != nil {
            identities.removeAll { $0 == identity }
        } else {
            membership.insert(identity)
            identities.append(identity)
        }
    }

    mutating func remove(_ removed: Set<PreviewWindowIdentity>) {
        guard !membership.isDisjoint(with: removed) else { return }
        membership.subtract(removed)
        identities.removeAll { removed.contains($0) }
    }

    mutating func select(_ added: [PreviewWindowIdentity]) {
        for identity in added where membership.insert(identity).inserted {
            identities.append(identity)
        }
    }

    func actionIdentities(for initiator: PreviewWindowIdentity) -> [PreviewWindowIdentity]? {
        membership.contains(initiator) ? identities : nil
    }
}

struct PreviewSelectionKeyPress: Equatable {
    let keyCode: Int64
    let timestamp: UInt64
}

struct PreviewSelectionRange {
    let order: [PreviewWindowIdentity]
    private let base: OrderedPreviewSelection
    private let anchorIndex: Int
    private let selecting: Bool
    private var endpoint: PreviewWindowIdentity?

    init?(order: [PreviewWindowIdentity], base: OrderedPreviewSelection, anchor: PreviewWindowIdentity, selecting: Bool) {
        guard let anchorIndex = order.firstIndex(of: anchor) else { return nil }
        self.order = order
        self.base = base
        self.anchorIndex = anchorIndex
        self.selecting = selecting
    }

    mutating func selection(through identity: PreviewWindowIdentity) -> OrderedPreviewSelection? {
        guard endpoint != identity, let index = order.firstIndex(of: identity) else { return nil }
        endpoint = identity
        let range = order[min(anchorIndex, index) ... max(anchorIndex, index)]
        var updated = base
        if selecting { updated.select(Array(range)) } else { updated.remove(Set(range)) }
        return updated
    }
}

/// Keeps highlight and checked membership separate from window metadata updates.
final class SwitcherSelectionState: ObservableObject {
    @Published var currIndex: Int = -1
    @Published fileprivate(set) var checkedWindows = OrderedPreviewSelection()
    @Published fileprivate(set) var previewDragTarget: PreviewWindowIdentity?
}

/// Pure UI state container for window preview presentation
class PreviewStateCoordinator: ObservableObject {
    enum SelectionInputSource {
        case programmatic
        case keyboard
        case mouse
    }

    let selection = SwitcherSelectionState()
    var currIndex: Int {
        get { selection.currIndex }
        set {
            let changed = selection.currIndex != newValue
            selection.currIndex = newValue
            if changed {
                tapStateDidChange?()
            }
        }
    }

    var tapStateDidChange: (() -> Void)?
    weak var actionFeedbackGrid: CardGridScrollView.Coordinator?
    weak var spaceDragViewport: SpacesBarScroll.ViewportView?
    @Published var isDraggingPreview = false
    weak var dragTargetGrid: CardGridScrollView.Coordinator?
    weak var selectionGrid: CardGridScrollView.Coordinator?

    private enum SelectionRangeInput: Equatable {
        case pointer
        case keyboard(PreviewSelectionKeyPress)
    }

    private var selectionAnchor: PreviewWindowIdentity?
    private var selectionRange: PreviewSelectionRange?
    private var selectionRangeInput: SelectionRangeInput?
    private var selectionRangeGeneration: UInt = 0
    private var selectionAllowsWindowless = false
    private(set) var selectionPointerLocation: CGPoint?
    @Published private(set) var pointerSelectionOrigin: PreviewWindowIdentity?

    var hasSelectionRange: Bool { selectionRange != nil }
    var isPointerSelecting: Bool { pointerSelectionOrigin != nil }
    var keyboardSelectionPress: PreviewSelectionKeyPress? {
        if case let .keyboard(press) = selectionRangeInput { return press }
        return nil
    }

    @MainActor
    private func displayedSelectionIdentities() -> [PreviewWindowIdentity] {
        filteredWindowIndices().compactMap {
            canSelectWindow(windows[$0]) ? PreviewWindowIdentity(windows[$0]) : nil
        }
    }

    @MainActor
    func endSelectionRange() {
        guard selectionRangeInput != nil else { return }
        selectionRange = nil
        selectionRangeInput = nil
        selectionPointerLocation = nil
        selectionGrid?.stopSelectionScroll()
    }

    @MainActor
    func endKeyboardSelectionRange(keyCode: Int64? = nil, releasedBefore timestamp: UInt64? = nil) {
        guard let press = keyboardSelectionPress,
              keyCode == nil || press.keyCode == keyCode
        else { return }
        if let timestamp, press.timestamp > timestamp { return }
        endSelectionRange()
    }

    @MainActor
    func endPointerSelectionRange(origin: PreviewWindowIdentity? = nil) {
        guard origin == nil || pointerSelectionOrigin == origin else { return }
        pointerSelectionOrigin = nil
        if selectionRangeInput == .pointer { endSelectionRange() }
    }

    @MainActor
    func reconcileSelectionRange() {
        guard let range = selectionRange else { return }
        guard Defaults[.enableMultiWindowSelection] else { endSelectionRange(); return }
        let allowsWindowless = windowSwitcherActive && Defaults[.enableWindowlessAppSelection]
        guard selectionRangeGeneration != filterGeneration || selectionAllowsWindowless != allowsWindowless else { return }
        guard displayedSelectionIdentities() == range.order else { endSelectionRange(); return }
        selectionRangeGeneration = filterGeneration
        selectionAllowsWindowless = allowsWindowless
    }

    @MainActor
    private func beginSelectionRange(at identity: PreviewWindowIdentity, input: SelectionRangeInput) -> Bool {
        guard let range = PreviewSelectionRange(
            order: displayedSelectionIdentities(), base: selection.checkedWindows, anchor: identity,
            selecting: !selection.checkedWindows.membership.contains(identity)
        ) else { return false }
        endSelectionRange()
        if input == .pointer { pointerSelectionOrigin = identity }
        selectionAnchor = identity
        selectionRange = range
        selectionRangeInput = input
        selectionRangeGeneration = filterGeneration
        selectionAllowsWindowless = windowSwitcherActive && Defaults[.enableWindowlessAppSelection]
        extendSelectionRange(through: identity)
        return true
    }

    @MainActor
    private func extendSelectionRange(through identity: PreviewWindowIdentity) {
        if selectionRangeGeneration != filterGeneration { reconcileSelectionRange() }
        guard let updated = selectionRange?.selection(through: identity), updated != selection.checkedWindows else { return }
        selection.checkedWindows = updated
        publishCheckedSelection()
    }

    @MainActor
    func toggleSelectionCheckbox(_ window: WindowInfo, extending: Bool) {
        guard canSelectWindow(window) else { return }
        let identity = PreviewWindowIdentity(window)
        let order = displayedSelectionIdentities()
        guard order.contains(identity) else { return }
        if extending {
            endSelectionRange()
            let anchor = selectionAnchor.flatMap { order.contains($0) ? $0 : nil } ?? identity
            selectionAnchor = anchor
            var range = PreviewSelectionRange(order: order, base: selection.checkedWindows, anchor: anchor, selecting: true)
            if let updated = range?.selection(through: identity), updated != selection.checkedWindows {
                selection.checkedWindows = updated
                publishCheckedSelection()
            }
        } else { toggleCheckedWindow(window) }
    }

    @MainActor
    func updatePointerSelectionRange(from window: WindowInfo, at location: CGPoint) {
        let identity = PreviewWindowIdentity(window)
        if pointerSelectionOrigin == nil {
            guard canSelectWindow(window), beginSelectionRange(at: identity, input: .pointer) else { return }
        }
        guard pointerSelectionOrigin == identity, selectionRangeInput == .pointer else { return }
        selectionPointerLocation = location
        updatePointerSelectionRange()
        selectionGrid?.updateSelectionScroll(at: location)
    }

    @MainActor
    func updatePointerSelectionRange() {
        guard selectionRangeInput == .pointer, let location = selectionPointerLocation,
              let window = selectionGrid?.windowForDrop(at: location), canSelectWindow(window)
        else { return }
        let identity = PreviewWindowIdentity(window)
        extendSelectionRange(through: identity)
        if windows.indices.contains(currIndex), PreviewWindowIdentity(windows[currIndex]) == identity { return }
        if selectionRange != nil, let index = windows.firstIndex(where: { PreviewWindowIdentity($0) == identity }) {
            setIndex(to: index, shouldScroll: false, source: .mouse, extendingSelection: true)
        }
    }

    @MainActor
    func setPreviewDragTarget(_ target: PreviewWindowIdentity?) {
        if selection.previewDragTarget != target { selection.previewDragTarget = target }
    }

    @Published private(set) var checkedWindowCount = 0
    private var selectionPinned = false
    var selectionSuppressesRelease: Bool {
        Defaults[.keepWindowSwitcherOpenWhenSelected] && selectionPinned
    }

    var onSelectionPinned: (() -> Void)?
    private var selectionLayoutGeneration: UInt = 0

    @MainActor
    func canSelectWindow(_ window: WindowInfo) -> Bool {
        Defaults[.enableMultiWindowSelection] && !window.app.isTerminated &&
            (!window.isWindowlessApp || (windowSwitcherActive && Defaults[.enableWindowlessAppSelection]))
    }

    @MainActor
    func toggleCheckedWindow(_ window: WindowInfo, keyboardPress: PreviewSelectionKeyPress? = nil) {
        guard canSelectWindow(window) else { return }
        let identity = PreviewWindowIdentity(window)
        guard windows.contains(where: { PreviewWindowIdentity($0) == identity }) else { return }
        if let keyboardPress, beginSelectionRange(at: identity, input: .keyboard(keyboardPress)) { return }
        endSelectionRange()
        selectionAnchor = identity
        selection.checkedWindows.toggle(identity)
        publishCheckedSelection()
    }

    @MainActor
    func selectAllDisplayedWindows() {
        selectWindows(filteredWindowIndices().map { windows[$0] })
    }

    @MainActor
    func selectWindows(_ candidates: [WindowInfo]) {
        endSelectionRange()
        guard Defaults[.enableMultiWindowSelection] else { return }
        let identities = candidates.filter { canSelectWindow($0) }.map(PreviewWindowIdentity.init)
        var updated = selection.checkedWindows
        updated.select(identities)
        guard updated != selection.checkedWindows else { return }
        selection.checkedWindows = updated
        publishCheckedSelection()
    }

    @MainActor
    private func pinCheckedSelectionIfNeeded() {
        if Defaults[.keepWindowSwitcherOpenWhenSelected], windowSwitcherActive,
           !selectionPinned, !selection.checkedWindows.identities.isEmpty
        {
            selectionPinned = true
            onSelectionPinned?()
        }
    }

    @MainActor
    func clearCheckedWindows(resetOwnership: Bool = false) {
        endSelectionRange()
        pointerSelectionOrigin = nil
        selectionAnchor = nil
        if resetOwnership { selectionPinned = false }
        guard checkedWindowCount > 0 else {
            tapStateDidChange?()
            return
        }
        selection.checkedWindows = OrderedPreviewSelection()
        publishCheckedSelection()
    }

    @MainActor
    private func publishCheckedSelection() {
        pinCheckedSelectionIfNeeded()
        let newCount = selection.checkedWindows.identities.count
        let changedSize = (checkedWindowCount == 0) != (newCount == 0)
        checkedWindowCount = newCount
        tapStateDidChange?()
        if changedSize {
            refreshSelectionLayout()
        }
    }

    @MainActor
    func consumeWindowlessSelection(in targets: [WindowInfo]) {
        guard checkedWindowCount > 0 else { return }
        let removed = Set(targets.filter(\.isWindowlessApp).map(PreviewWindowIdentity.init))
        guard !selection.checkedWindows.membership.isDisjoint(with: removed) else { return }
        endSelectionRange()
        selection.checkedWindows.remove(removed)
        publishCheckedSelection()
    }

    @MainActor
    func removeCheckedWindows(forProcessIdentifier pid: pid_t) {
        let removed = Set(selection.checkedWindows.identities.filter { $0.pid == pid })
        if !removed.isEmpty || selectionRange?.order.contains(where: { $0.pid == pid }) == true { endSelectionRange() }
        guard !removed.isEmpty else { return }
        selection.checkedWindows.remove(removed)
        publishCheckedSelection()
    }

    @MainActor
    func reconcileCheckedWindows() {
        guard checkedWindowCount > 0 else { return }
        let identities = selection.checkedWindows.identities
        var live = Set(Set(identities.map(\.pid)).flatMap {
            WindowUtil.readCachedWindows(for: $0).map(PreviewWindowIdentity.init)
        })
        if identities.contains(where: { $0.windowID == 0 }) {
            let appsWithWindows = Set(live.filter { $0.windowID != 0 }.map(\.pid))
            live.formUnion((windows + retainedWindowlessSelectionRows).filter {
                $0.isWindowlessApp && canSelectWindow($0) && !appsWithWindows.contains($0.app.processIdentifier)
            }.map(PreviewWindowIdentity.init))
        }
        let removed = selection.checkedWindows.membership.subtracting(live)
        guard !removed.isEmpty else { return }
        endSelectionRange()
        selection.checkedWindows.remove(removed)
        publishCheckedSelection()
    }

    @MainActor
    func checkedActionTargets(for initiator: WindowInfo? = nil, includingWindowlessApps: Bool = false) -> [WindowInfo]? {
        guard Defaults[.enableMultiWindowSelection] else { return nil }
        let identities: [PreviewWindowIdentity]
        if let initiator {
            guard let checked = selection.checkedWindows.actionIdentities(for: PreviewWindowIdentity(initiator)) else { return nil }
            identities = checked
        } else { identities = selection.checkedWindows.identities }
        guard !identities.isEmpty else { return nil }
        let cached = Set(identities.map(\.pid)).flatMap { WindowUtil.readCachedWindows(for: $0) }
        var windowless: [WindowInfo] = []
        if includingWindowlessApps, identities.contains(where: { $0.windowID == 0 }) {
            let appsWithWindows = Set(cached.filter { !$0.isWindowlessApp }.map(\.app.processIdentifier))
            windowless = (windows + retainedWindowlessSelectionRows).filter {
                $0.isWindowlessApp && canSelectWindow($0) && !appsWithWindows.contains($0.app.processIdentifier)
            }
        }
        let byIdentity = Dictionary((cached + windowless).map { (PreviewWindowIdentity($0), $0) }, uniquingKeysWith: { first, _ in first })
        return identities.compactMap { byIdentity[$0] }.filter { (includingWindowlessApps || !$0.isWindowlessApp) && !$0.app.isTerminated }
    }

    @MainActor
    func refreshSelectionLayout() {
        selectionLayoutGeneration &+= 1
        let generation = selectionLayoutGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, selectionLayoutGeneration == generation,
                  !windows.isEmpty || checkedWindowCount > 0
            else { return }
            if let monitor = lastKnownBestGuessMonitor {
                recomputeAndPublishDimensions(dockPosition: lastKnownDockPosition, bestGuessMonitor: monitor)
            }
            onFrameRefreshNeeded?()
        }
    }

    var selectionSummaryStyle: AppNameStyle {
        if windowSwitcherActive { return .default }
        return lastKnownDockPosition == .cmdTab ? Defaults[.cmdTabAppNameStyle] : Defaults[.appNameStyle]
    }

    enum SpaceNavigationRequest: Equatable {
        case current
        case cycle(backward: Bool)

        func targetIndex(ids: [CGSSpaceID], current: CGSSpaceID?, highlighted: CGSSpaceID?, startNext: Bool) -> Int? {
            guard !ids.isEmpty else { return nil }
            let index = ids.firstIndex(of: highlighted ?? current ?? 0) ?? 0
            let delta: Int = switch self {
            case .current: 0
            case let .cycle(backward): highlighted == nil && !startNext ? 0 : (backward ? -1 : 1)
            }
            return (index + delta + ids.count) % ids.count
        }
    }

    var pendingSpaceNavigation: (request: SpaceNavigationRequest, screen: NSScreen)?
    enum NavigationTarget: Equatable { case windows, space(CGSSpaceID) }
    @Published var navigationTarget: NavigationTarget = .windows {
        didSet {
            guard oldValue != navigationTarget else { return }
            if navigationTarget == .windows { spaceNavigationInputSource = .programmatic }
            tapStateDidChange?()
            onNavigationTargetChanged?()
        }
    }

    var onNavigationTargetChanged: (() -> Void)?
    var onSpaceFilterChanged: (() -> Void)?
    private(set) var activeSpaceFilterID: CGSSpaceID?
    private(set) var activeSpaceMembers: Set<PreviewWindowIdentity>?
    var retainedWindowlessSelectionRows: [WindowInfo] = []

    @MainActor
    func setSpaceFilter(_ id: CGSSpaceID?, members: Set<PreviewWindowIdentity>? = nil) {
        guard activeSpaceFilterID != id || activeSpaceMembers != members else { return }
        endSelectionRange()
        if activeSpaceFilterID == nil, id != nil {
            retainedWindowlessSelectionRows = windows.filter(\.isWindowlessApp)
        }
        activeSpaceFilterID = id
        activeSpaceMembers = id == nil ? nil : members
        updateSelectionIndex(-1, source: .programmatic)
        onSpaceFilterChanged?()
        if id == nil { retainedWindowlessSelectionRows = [] }
    }

    var spaceNavigationInputSource: SelectionInputSource = .programmatic
    var mouseHighlightedSpaceID: CGSSpaceID?

    @MainActor
    func hoverSpace(_ id: CGSSpaceID, hovering: Bool) {
        if !hovering, mouseHighlightedSpaceID == id { mouseHighlightedSpaceID = nil }
        guard windowSwitcherActive, Defaults[.enableSpacesBar] else { return }
        guard Defaults[.enableMouseHoverInSwitcher] else {
            if spaceNavigationInputSource == .mouse { navigationTarget = .windows }
            return
        }
        if hovering {
            guard mouseHighlightedSpaceID != id else { return }
            guard !isDraggingPreview, !isPointerSelecting, registerMouseMovementSinceOpen() else { return }
            mouseHighlightedSpaceID = id
            guard navigationTarget != .space(id) || spaceNavigationInputSource != .mouse else { return }
            setIndex(to: -1, shouldScroll: false, source: .programmatic)
            spaceNavigationInputSource = .mouse
            navigationTarget = .space(id)
        } else {
            if spaceNavigationInputSource == .mouse, navigationTarget == .space(id) { navigationTarget = .windows }
        }
    }

    @Published var switcherTopAccessoryHeight: CGFloat = 0

    var selectionAccessoryHeight: CGFloat {
        guard checkedWindowCount > 0, Defaults[.showWindowSelectionSummary] else { return 0 }
        return PreviewHeaderLayout.contentReservation(for: selectionSummaryStyle)
    }

    @Published private(set) var selectionInputSource: SelectionInputSource = .programmatic

    @Published var windowSwitcherActive: Bool = false {
        didSet {
            invalidateFilterCache()
            if oldValue != windowSwitcherActive {
                tapStateDidChange?()
            }
        }
    }

    // MARK: - Keybind Session Tracking

    /// Tracks whether the window switcher was activated via keybind (not just visible)
    private(set) var isKeybindSessionActive: Bool = false

    @MainActor
    func activateKeybindSession() {
        let changed = !isKeybindSessionActive
        isKeybindSessionActive = true
        if changed {
            tapStateDidChange?()
        }
    }

    @MainActor
    func deactivateKeybindSession() {
        mouseHighlightedSpaceID = nil
        pendingSpaceNavigation = nil
        onSpaceFilterChanged = nil
        activeSpaceFilterID = nil
        activeSpaceMembers = nil
        retainedWindowlessSelectionRows = []
        let changed = isKeybindSessionActive
        isKeybindSessionActive = false
        if changed {
            tapStateDidChange?()
        }
        searchQuery = ""
    }

    // MARK: - UI State

    var hasMovedSinceOpen: Bool = false
    var initialHoverLocation: CGPoint?
    @Published private(set) var pointerInteractionSessionID: UInt = 0
    private var pointerInteractionReady = true
    var fullWindowPreviewActive: Bool = false
    @Published private var storedWindows: [WindowInfo] = []
    var windows: [WindowInfo] {
        get { storedWindows }
        set {
            if let activeSpaceMembers {
                storedWindows = newValue.filter { !$0.isWindowlessApp && activeSpaceMembers.contains(PreviewWindowIdentity($0)) }
            } else {
                storedWindows = newValue
            }
            invalidateFilterCache()
        }
    }

    var hasRealWindows: Bool {
        windows.contains { !$0.isWindowlessApp }
    }

    @Published private(set) var focusedWindowID: CGWindowID?
    @Published private(set) var desktopNumbers: [Int: Int] = [:]

    var shouldScrollToIndex: Bool = true

    @Published var searchQuery: String = "" {
        didSet {
            navigationTarget = .windows
            invalidateFilterCache()
            if windowSwitcherActive {
                Task { @MainActor in
                    updateIndexForSearch()
                    onFrameRefreshNeeded?()
                }
            }
        }
    }

    private var cachedFilteredIndices: [Int]?
    private var filterGeneration: UInt = 0
    private func invalidateFilterCache() {
        cachedFilteredIndices = nil
        filterGeneration &+= 1
    }

    @MainActor
    func updateActiveFocusedWindowID(_ windowID: CGWindowID?, for processIdentifier: pid_t) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processIdentifier else { return }
        applyActiveFocusedWindowID(windowID, frontmostPID: processIdentifier)
    }

    @MainActor
    func refreshFocusedWindowID(from newWindows: [WindowInfo]? = nil) {
        let sourceWindows = newWindows ?? windows
        if let focusedWindowID,
           sourceWindows.contains(where: { $0.id == focusedWindowID })
        {
            return
        }
        focusedWindowID = Self.currentFocusedWindowID(in: sourceWindows)
    }

    @MainActor
    private func refreshDesktopNumbers() {
        let numbers = Defaults[.showSpaceNumber] ? WindowSpaces.desktopNumbers() : [:]
        if numbers != desktopNumbers {
            desktopNumbers = numbers
        }
    }

    func desktopNumber(for window: WindowInfo) -> Int? {
        window.spaceID.flatMap { desktopNumbers[$0] }
    }

    private static func currentFocusedWindowID(in windows: [WindowInfo]) -> CGWindowID? {
        guard let activeApp = windows.first(where: { $0.app.isActive })?.app else { return nil }
        let candidateIDs = Set(windows.filter { $0.app.processIdentifier == activeApp.processIdentifier }.map(\.id))
        guard !candidateIDs.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        for entry in list {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let id = entry[kCGWindowNumber as String] as? CGWindowID,
                  candidateIDs.contains(id)
            else { continue }
            return id
        }
        return nil
    }

    var hasActiveSearch: Bool {
        !searchQuery.isEmpty
    }

    struct DimensionState: Equatable {
        var overallMaxPreviewDimension: CGPoint = .zero
        var windowDimensionsMap: [Int: WindowPreviewHoverContainer.WindowDimensions] = [:]
        var effectiveGridColumns: Int = 1
        var effectiveGridRows: Int = 1

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.overallMaxPreviewDimension == rhs.overallMaxPreviewDimension
                && lhs.effectiveGridColumns == rhs.effectiveGridColumns
                && lhs.effectiveGridRows == rhs.effectiveGridRows
                && lhs.windowDimensionsMap.count == rhs.windowDimensionsMap.count
        }
    }

    @Published var dimensionState = DimensionState()
    var expectedContentSize: CGSize = .zero
    var hasEmbeddedContent: Bool = false

    var onFrameRefreshNeeded: (() -> Void)?
    private var lastKnownBestGuessMonitor: NSScreen?
    private var lastKnownDockPosition: DockPosition = .bottom
    private var visibilitySyncTasksByPID: [pid_t: Task<Void, Never>] = [:]
    private var activeFocusRefreshTask: Task<Void, Never>?
    private var pendingActiveFocusRefreshRequest = false

    enum WindowState {
        case windowSwitcher
        case fullWindowPreview
        case both
    }

    @MainActor
    func setShowing(_ state: WindowState? = .both, toState: Bool) {
        let oldSwitcherState = windowSwitcherActive
        switch state {
        case .windowSwitcher:
            windowSwitcherActive = toState
        case .fullWindowPreview:
            fullWindowPreviewActive = toState
        case .both:
            windowSwitcherActive = toState
            fullWindowPreviewActive = toState
        case .none:
            return
        }

        if !oldSwitcherState, windowSwitcherActive {
            hasMovedSinceOpen = false
            initialHoverLocation = nil
        }

        // If window switcher state changed and we have windows, recalculate dimensions
        if oldSwitcherState != windowSwitcherActive, !windows.isEmpty {
            if let monitor = lastKnownBestGuessMonitor {
                let dockPosition = DockUtils.getDockPosition()
                recomputeAndPublishDimensions(dockPosition: dockPosition, bestGuessMonitor: monitor)
            }
        }

        if windowSwitcherActive || fullWindowPreviewActive {
            scheduleActiveFocusedWindowRefresh()
        }
    }

    @MainActor
    func updateSelectionIndex(_ requestedIndex: Int, source: SelectionInputSource, shouldScroll: Bool? = nil) {
        if source == .mouse { navigationTarget = .windows }
        if let shouldScroll {
            shouldScrollToIndex = shouldScroll
        }

        if requestedIndex >= 0, requestedIndex < windows.count {
            currIndex = requestedIndex
        } else {
            currIndex = -1
        }
        if selectionInputSource != source {
            selectionInputSource = source
        }
    }

    @MainActor
    func setIndex(to: Int, shouldScroll: Bool = true, source: SelectionInputSource = .programmatic, extendingSelection: Bool = false) {
        if !extendingSelection { endSelectionRange() }
        updateSelectionIndex(to, source: source, shouldScroll: shouldScroll)
        if extendingSelection, windows.indices.contains(to) { extendSelectionRange(through: PreviewWindowIdentity(windows[to])) }
    }

    @MainActor
    func registerMouseMovementSinceOpen(at location: CGPoint = NSEvent.mouseLocation) -> Bool {
        guard pointerInteractionReady else { return false }
        if hasMovedSinceOpen { return true }

        guard let initialHoverLocation else {
            self.initialHoverLocation = location
            return false
        }

        guard hypot(location.x - initialHoverLocation.x, location.y - initialHoverLocation.y) > 1 else {
            return false
        }

        hasMovedSinceOpen = true
        return true
    }

    @MainActor
    @discardableResult
    func beginPointerInteractionSession(at location: CGPoint = NSEvent.mouseLocation) -> UInt {
        endSelectionRange()
        endPointerSelectionRange()
        pointerInteractionSessionID &+= 1
        pointerInteractionReady = false
        hasMovedSinceOpen = false
        initialHoverLocation = location
        return pointerInteractionSessionID
    }

    @MainActor
    func armPointerInteractionSession(_ sessionID: UInt, at location: CGPoint = NSEvent.mouseLocation) {
        guard sessionID == pointerInteractionSessionID else { return }
        hasMovedSinceOpen = false
        initialHoverLocation = location
        pointerInteractionReady = true
    }

    @MainActor
    func clearSelectionIfMouseSource(shouldScroll: Bool = false) {
        guard selectionInputSource == .mouse else { return }
        updateSelectionIndex(-1, source: .programmatic, shouldScroll: shouldScroll)
    }

    @MainActor
    func setWindows(_ newWindows: [WindowInfo], dockPosition: DockPosition, bestGuessMonitor: NSScreen, isMockPreviewActive: Bool = false) {
        let changesWindowlessPresentation = !windows.isEmpty && !newWindows.isEmpty &&
            hasRealWindows != newWindows.contains { !$0.isWindowlessApp }
        windows = newWindows
        reconcileCheckedWindows()
        reconcileSelectionRange()
        refreshFocusedWindowID(from: newWindows)
        refreshDesktopNumbers()
        lastKnownBestGuessMonitor = bestGuessMonitor

        if currIndex >= windows.count {
            updateSelectionIndex(windows.isEmpty ? -1 : windows.count - 1, source: .programmatic)
        }

        recomputeAndPublishDimensions(dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor, isMockPreviewActive: isMockPreviewActive)
        if changesWindowlessPresentation {
            onFrameRefreshNeeded?()
        }
        scheduleActiveFocusedWindowRefresh()
    }

    /// Merge refreshed rows for one app PID while preserving global row order and selected-row identity.
    @MainActor
    func mergeRefreshedRowsForPID(
        _ processIdentifier: pid_t,
        replacementRows: [WindowInfo],
        dockPosition: DockPosition,
        bestGuessMonitor: NSScreen?,
        isMockPreviewActive: Bool = false
    ) -> (mergedWindows: [WindowInfo], didPublish: Bool) {
        let before = windows
        let beforeSnapshots = before.map(\.viewSnapshot)
        let previousSelectionSource = selectionInputSource
        let selectedWindowIdentity: String? = if currIndex >= 0, currIndex < before.count {
            mergeIdentity(for: before[currIndex])
        } else {
            nil
        }

        let replacementByIdentity: [String: WindowInfo] = Dictionary(
            replacementRows.map { (mergeIdentity(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var consumedReplacementIdentities = Set<String>()
        var merged: [WindowInfo] = []
        merged.reserveCapacity(max(before.count, replacementRows.count))
        var firstAppSlotInMerged: Int?

        for window in before {
            if window.app.processIdentifier != processIdentifier {
                merged.append(window)
                continue
            }

            if firstAppSlotInMerged == nil {
                firstAppSlotInMerged = merged.count
            }

            let key = mergeIdentity(for: window)
            if let updated = replacementByIdentity[key] {
                merged.append(updated)
                consumedReplacementIdentities.insert(key)
            }
        }

        let remainingReplacement = replacementRows.filter {
            !consumedReplacementIdentities.contains(mergeIdentity(for: $0))
        }
        if !remainingReplacement.isEmpty {
            let insertionIndex = min(firstAppSlotInMerged ?? merged.count, merged.count)
            merged.insert(contentsOf: remainingReplacement, at: insertionIndex)
        }

        let mergedSnapshots = merged.map(\.viewSnapshot)
        guard mergedSnapshots != beforeSnapshots else {
            return (merged, false)
        }

        guard let resolvedMonitor = bestGuessMonitor ?? lastKnownBestGuessMonitor ?? NSScreen.main ?? NSScreen.screens.first else {
            return (windows, false)
        }

        setWindows(
            merged,
            dockPosition: dockPosition,
            bestGuessMonitor: resolvedMonitor,
            isMockPreviewActive: isMockPreviewActive
        )

        if let selectedWindowIdentity,
           let restoredIndex = windows.firstIndex(where: { mergeIdentity(for: $0) == selectedWindowIdentity }),
           restoredIndex != currIndex
        {
            updateSelectionIndex(restoredIndex, source: previousSelectionSource, shouldScroll: false)
        }

        return (windows, true)
    }

    /// Merges fresh windows into the current display without jarring replacement.
    /// Preserves window order and selected index where possible.
    @MainActor
    func mergeWindows(_ freshWindows: [WindowInfo], dockPosition: DockPosition, bestGuessMonitor: NSScreen) {
        guard !windows.isEmpty else {
            setWindows(freshWindows, dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor)
            return
        }

        let previousWindowCount = windows.count
        let hadRealWindows = hasRealWindows
        let previousSelectionSource = selectionInputSource
        let selectedWindowIdentity: String? = if currIndex >= 0, currIndex < windows.count {
            mergeIdentity(for: windows[currIndex])
        } else {
            nil
        }

        let freshWindowsByIdentity: [String: WindowInfo] = Dictionary(
            freshWindows.map { (mergeIdentity(for: $0), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let freshIdentities = Set(freshWindowsByIdentity.keys)
        let existingIdentities = Set(windows.map(mergeIdentity(for:)))

        // Update existing windows in place
        for index in windows.indices {
            let identity = mergeIdentity(for: windows[index])
            if let fresh = freshWindowsByIdentity[identity] {
                windows[index] = fresh
            }
        }

        // Add new windows at the end
        for freshWindow in freshWindows where !existingIdentities.contains(mergeIdentity(for: freshWindow)) {
            windows.append(freshWindow)
        }

        // Remove stale windows
        let staleIdentities = existingIdentities.subtracting(freshIdentities)
        if !staleIdentities.isEmpty {
            windows.removeAll { staleIdentities.contains(mergeIdentity(for: $0)) }
        }

        // Restore selection to the same window, or clamp if it was removed
        reconcileCheckedWindows()
        if let selectedWindowIdentity,
           let newIndex = windows.firstIndex(where: { mergeIdentity(for: $0) == selectedWindowIdentity })
        {
            // Keep user-driven source across async merges so highlight actions don't get canceled.
            updateSelectionIndex(newIndex, source: previousSelectionSource)
        } else if currIndex >= windows.count {
            updateSelectionIndex(windows.isEmpty ? -1 : windows.count - 1, source: .programmatic)
        }

        lastKnownBestGuessMonitor = bestGuessMonitor
        refreshFocusedWindowID()
        refreshDesktopNumbers()
        recomputeAndPublishDimensions(dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor)

        if windows.count != previousWindowCount || hadRealWindows != hasRealWindows {
            onFrameRefreshNeeded?()
        }
        scheduleActiveFocusedWindowRefresh()
    }

    private func mergeIdentity(for window: WindowInfo) -> String {
        "\(window.app.processIdentifier)-\(window.id)"
    }

    @MainActor
    func updateWindow(at index: Int, with newInfo: WindowInfo) {
        guard index >= 0, index < windows.count else { return }
        windows[index] = newInfo
        scheduleActiveFocusedWindowRefresh()
    }

    @MainActor
    func updateHiddenStateForApp(processIdentifier pid: pid_t, isHidden: Bool) {
        var updatedWindows = windows
        var hasPublishedChanges = false

        for index in updatedWindows.indices where updatedWindows[index].app.processIdentifier == pid {
            var row = updatedWindows[index]

            if row.isHidden != isHidden {
                row.isHidden = isHidden
                hasPublishedChanges = true
            }

            updatedWindows[index] = row
            WindowUtil.updateCachedWindowState(row, isHidden: isHidden)
        }

        if hasPublishedChanges {
            windows = updatedWindows
        }
    }

    @MainActor
    func scheduleVisibilityStateSync(processIdentifier pid: pid_t) {
        visibilitySyncTasksByPID[pid]?.cancel()
        visibilitySyncTasksByPID[pid] = Task { @MainActor [weak self] in
            guard let self else { return }
            let delays: [UInt64] = [80_000_000, 220_000_000]

            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await syncVisibilityState(processIdentifier: pid)
                guard !Task.isCancelled else { return }
            }

            visibilitySyncTasksByPID.removeValue(forKey: pid)
        }
    }

    @MainActor
    private func syncVisibilityState(processIdentifier pid: pid_t) async {
        let sessionID = pointerInteractionSessionID
        let targets = windows.filter { $0.app.processIdentifier == pid && !$0.isWindowlessApp }
        var states: [PreviewWindowIdentity: (minimized: Bool?, hidden: Bool?, fullscreen: Bool?)] = [:]
        for target in targets {
            guard !Task.isCancelled, pointerInteractionSessionID == sessionID else { return }
            let state = await target.readVisibilityState()
            guard !Task.isCancelled, pointerInteractionSessionID == sessionID else { return }
            states[PreviewWindowIdentity(target)] = state
        }
        var updatedWindows = windows
        var hasPublishedChanges = false
        for index in updatedWindows.indices {
            guard let state = states[PreviewWindowIdentity(updatedWindows[index])] else { continue }
            var row = updatedWindows[index]

            if let isMinimized = state.minimized {
                row.isMinimized = isMinimized
            }
            row.isHidden = state.hidden ?? row.app.isHidden
            row.isFullscreen = state.fullscreen
            if row.viewSnapshot != updatedWindows[index].viewSnapshot { hasPublishedChanges = true }
            updatedWindows[index] = row
            WindowUtil.updateCachedWindowState(
                row,
                isMinimized: row.isMinimized,
                isHidden: row.isHidden,
                isFullscreen: row.isFullscreen
            )
        }
        if hasPublishedChanges { windows = updatedWindows }
    }

    @MainActor
    func applyCacheChanges(removed: [WindowInfo], added: [WindowInfo], updated: [WindowInfo]) {
        if !removed.isEmpty { reconcileCheckedWindows() }
        guard !windows.isEmpty else { return }

        if !updated.isEmpty {
            var merged = windows
            var changed = false
            for fresh in updated {
                guard let index = merged.firstIndex(where: { $0.id == fresh.id && $0.app.processIdentifier == fresh.app.processIdentifier }),
                      merged[index].viewSnapshot != fresh.viewSnapshot || merged[index] != fresh
                else { continue }
                merged[index] = fresh
                changed = true
            }
            if changed {
                windows = merged
            }
        }

        for window in removed {
            removeWindow(byAx: window.axElement)
        }

        if !added.isEmpty {
            addWindows(added)
        }
    }

    @MainActor
    func removeWindow(at indexToRemove: Int) {
        guard indexToRemove >= 0, indexToRemove < windows.count else { return }

        let removedWindow = windows[indexToRemove]
        let oldCurrIndex = currIndex
        windows.remove(at: indexToRemove)
        var insertedWindowlessIndex: Int?

        if windowSwitcherActive, Defaults[.showWindowlessAppsInSwitcher], !removedWindow.isWindowlessApp {
            let removedPID = removedWindow.app.processIdentifier
            let appStillRepresented = windows.contains { $0.app.processIdentifier == removedPID }

            if !appStillRepresented,
               let windowlessEntry = WindowUtil.windowlessEntryIfEligible(for: removedWindow.app, existingWindows: windows)
            {
                windows.append(windowlessEntry)
                insertedWindowlessIndex = windows.count - 1
            }
        }

        if windows.isEmpty {
            updateSelectionIndex(-1, source: .programmatic)
            if SharedPreviewWindowCoordinator.activeInstance?.hasVisibleSpacesBar != true {
                SharedPreviewWindowCoordinator.activeInstance?.hideWindow()
                return
            }
        }

        if oldCurrIndex == indexToRemove {
            if let insertedWindowlessIndex {
                updateSelectionIndex(insertedWindowlessIndex, source: .programmatic)
            } else {
                updateSelectionIndex(min(indexToRemove, windows.count - 1), source: .programmatic)
            }
        } else if oldCurrIndex > indexToRemove {
            updateSelectionIndex(oldCurrIndex - 1, source: .programmatic)
        }

        if currIndex >= windows.count {
            updateSelectionIndex(windows.count - 1, source: .programmatic)
        }

        // Recompute dimensions and request frame refresh
        if let monitor = lastKnownBestGuessMonitor {
            let dockPosition = DockUtils.getDockPosition()
            recomputeAndPublishDimensions(dockPosition: dockPosition, bestGuessMonitor: monitor)
            onFrameRefreshNeeded?()
        }
        scheduleActiveFocusedWindowRefresh()
    }

    @MainActor
    func removeWindow(byAx ax: AXUIElement) {
        guard let indexToRemove = windows.firstIndex(where: { $0.axElement == ax }) else {
            return // Window not found
        }
        removeWindow(at: indexToRemove)
    }

    @MainActor
    func addWindows(_ newWindowsToAdd: [WindowInfo]) {
        guard !newWindowsToAdd.isEmpty else { return }
        let gated: [WindowInfo]
        if isKeybindSessionActive {
            // The switcher shows every app, so cache discoveries from any PID belong here.
            gated = newWindowsToAdd
        } else {
            // Dock previews are single-app: gate by the displayed PID to avoid cross-app injection.
            guard let currentPid = windows.first?.app.processIdentifier else { return }
            gated = newWindowsToAdd.filter { $0.app.processIdentifier == currentPid }
        }

        var windowsWereAdded = false
        for newWin in gated {
            if let placeholderIndex = windows.firstIndex(where: {
                $0.isWindowlessApp && $0.app.processIdentifier == newWin.app.processIdentifier
            }) {
                consumeWindowlessSelection(in: [windows[placeholderIndex]])
                windows[placeholderIndex] = newWin
                windowsWereAdded = true
                continue
            }
            if !windows.contains(where: { $0.id == newWin.id && $0.app.processIdentifier == newWin.app.processIdentifier }) {
                windows.append(newWin)
                windowsWereAdded = true
            }
        }

        // Recompute dimensions if any windows were added
        if windowsWereAdded, let monitor = lastKnownBestGuessMonitor {
            let dockPosition = DockUtils.getDockPosition()
            recomputeAndPublishDimensions(dockPosition: dockPosition, bestGuessMonitor: monitor)
            onFrameRefreshNeeded?()
        }
        if windowsWereAdded {
            scheduleActiveFocusedWindowRefresh()
        }
    }

    @MainActor
    func removeAllWindows() {
        activeFocusRefreshTask?.cancel()
        activeFocusRefreshTask = nil
        pendingActiveFocusRefreshRequest = false
        focusedWindowID = nil
        windows.removeAll()
        updateSelectionIndex(-1, source: .programmatic)
        SharedPreviewWindowCoordinator.activeInstance?.hideWindow()
    }

    @MainActor
    private func applyActiveFocusedWindowID(_ resolvedWindowID: CGWindowID?, frontmostPID: pid_t?) {
        guard Defaults[.showActiveWindowBorder] else {
            if focusedWindowID != nil {
                focusedWindowID = nil
            }
            return
        }

        let refreshedWindowID = resolvedWindowID.flatMap { windowID in
            windows.contains(where: { $0.id == windowID && $0.app.processIdentifier == frontmostPID }) ? windowID : nil
        } ?? frontmostPID.flatMap { pid in
            windows
                .filter { $0.app.processIdentifier == pid }
                .max(by: { $0.lastAccessedTime < $1.lastAccessedTime })?
                .id
        }
        if focusedWindowID != refreshedWindowID {
            if Defaults[.debugMode] {
                DebugLogger.log("PreviewFocus", details: "frontmostPID=\(String(describing: frontmostPID)), AX=\(String(describing: resolvedWindowID)), border=\(String(describing: focusedWindowID))->\(String(describing: refreshedWindowID))")
            }
            focusedWindowID = refreshedWindowID
        }
    }

    @MainActor
    func scheduleActiveFocusedWindowRefresh() {
        guard Defaults[.showActiveWindowBorder] else {
            activeFocusRefreshTask?.cancel()
            activeFocusRefreshTask = nil
            pendingActiveFocusRefreshRequest = false
            focusedWindowID = nil
            return
        }
        guard activeFocusRefreshTask == nil else {
            pendingActiveFocusRefreshRequest = true
            return
        }
        pendingActiveFocusRefreshRequest = false
        activeFocusRefreshTask = Task { [weak self] in
            let delays: [UInt64] = [0, 90_000_000, 240_000_000]
            for delay in delays {
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: delay)
                }
                guard !Task.isCancelled else { return }
                guard Defaults[.showActiveWindowBorder] else { break }
                let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let resolvedWindowID: CGWindowID? = if let frontmostPID {
                    await Task.detached(priority: .userInitiated) {
                        WindowUtil.focusedWindowID(processIdentifier: frontmostPID)
                    }.value
                } else {
                    nil
                }
                guard !Task.isCancelled else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID else {
                    pendingActiveFocusRefreshRequest = true
                    continue
                }
                self?.applyActiveFocusedWindowID(resolvedWindowID, frontmostPID: frontmostPID)
            }
            guard let self else { return }
            activeFocusRefreshTask = nil
            if pendingActiveFocusRefreshRequest {
                pendingActiveFocusRefreshRequest = false
                scheduleActiveFocusedWindowRefresh()
            }
        }
    }

    @MainActor
    func recomputeAndPublishDimensions(dockPosition: DockPosition, bestGuessMonitor: NSScreen, isMockPreviewActive: Bool = false) {
        lastKnownDockPosition = dockPosition
        let panelSize = getWindowSize()

        let newOverallMaxDimension = WindowPreviewHoverContainer.calculateOverallMaxDimensions(
            windows: windows,
            dockPosition: dockPosition,
            isWindowSwitcherActive: windowSwitcherActive,
            isMockPreviewActive: isMockPreviewActive,
            sharedPanelWindowSize: panelSize
        )

        let (initialColumns, initialRows) = WindowPreviewHoverContainer.calculateEffectiveMaxColumnsAndRows(
            bestGuessMonitor: bestGuessMonitor,
            overallMaxDimensions: newOverallMaxDimension,
            dockPosition: dockPosition,
            isWindowSwitcherActive: windowSwitcherActive,
            previewMaxColumns: Defaults[.previewMaxColumns],
            previewMaxRows: Defaults[.previewMaxRows],
            switcherMaxRows: Defaults[.switcherMaxRows],
            totalItems: windows.count,
            accessoryHeight: selectionAccessoryHeight + switcherTopAccessoryHeight
        )

        var newDimensionsMap = WindowPreviewHoverContainer.precomputeWindowDimensions(
            windows: windows,
            overallMaxDimensions: newOverallMaxDimension,
            bestGuessMonitor: bestGuessMonitor,
            dockPosition: dockPosition,
            isWindowSwitcherActive: windowSwitcherActive,
            effectiveMaxColumns: initialColumns,
            effectiveMaxRows: initialRows
        )

        let compactThreshold = if windowSwitcherActive {
            Defaults[.windowSwitcherCompactThreshold]
        } else if dockPosition == .cmdTab {
            Defaults[.cmdTabCompactThreshold]
        } else {
            Defaults[.dockPreviewCompactThreshold]
        }
        let wouldUseCompactMode = WindowPreviewHoverContainer.usesCompactRows(
            isMockPreviewActive: isMockPreviewActive,
            forceCompact: Defaults[.disableImagePreview],
            windowCount: windows.count,
            threshold: compactThreshold
        )
        let needsSwitcherChromeMeasurement = windowSwitcherActive && !wouldUseCompactMode && (
            Defaults[.allowDynamicImageSizing] ||
                (Defaults[.windowSwitcherScrollDirection] == .horizontal &&
                    !Defaults[.switcherIgnoreScreenLimit] && initialRows > 1)
        )
        let measuredChromeHeight = needsSwitcherChromeMeasurement
            ? measureSwitcherCardChromeHeight(
                dimensionsMap: newDimensionsMap,
                dockPosition: dockPosition,
                bestGuessMonitor: bestGuessMonitor
            )
            : nil
        let resolvedRows = resolvedSwitcherRowLimit(
            initialRows: initialRows,
            dimensionsMap: newDimensionsMap,
            chromeHeight: measuredChromeHeight,
            bestGuessMonitor: bestGuessMonitor
        )
        if resolvedRows != initialRows {
            newDimensionsMap = WindowPreviewHoverContainer.precomputeWindowDimensions(
                windows: windows,
                overallMaxDimensions: newOverallMaxDimension,
                bestGuessMonitor: bestGuessMonitor,
                dockPosition: dockPosition,
                isWindowSwitcherActive: windowSwitcherActive,
                effectiveMaxColumns: initialColumns,
                effectiveMaxRows: resolvedRows
            )
        }

        dimensionState = DimensionState(
            overallMaxPreviewDimension: newOverallMaxDimension,
            windowDimensionsMap: newDimensionsMap,
            effectiveGridColumns: initialColumns,
            effectiveGridRows: resolvedRows
        )

        if Defaults[.allowDynamicImageSizing], !wouldUseCompactMode {
            if windowSwitcherActive {
                expectedContentSize = computeSwitcherContentSize(
                    dimensionsMap: newDimensionsMap,
                    maxColumns: initialColumns,
                    maxRows: resolvedRows,
                    minimumItemWidth: min(newOverallMaxDimension.x, WindowPreviewHoverContainer.dynamicSwitcherMinimumCardWidth),
                    dockPosition: dockPosition,
                    bestGuessMonitor: bestGuessMonitor,
                    measuredChromeHeight: measuredChromeHeight
                )
            } else {
                expectedContentSizeIsExact = false
                expectedContentSize = Self.computeExpectedContentSize(
                    windowCount: windows.count,
                    dimensionsMap: newDimensionsMap,
                    isHorizontal: dockPosition.isHorizontalFlow,
                    maxColumns: initialColumns,
                    maxRows: resolvedRows,
                    hasEmbeddedContent: hasEmbeddedContent,
                    fillToLimit: false,
                    minimumItemWidth: 0
                )
            }
        } else {
            expectedContentSizeIsExact = false
            expectedContentSize = .zero
        }
        if expectedContentSize != .zero { expectedContentSize.height += selectionAccessoryHeight }
    }

    private func resolvedSwitcherRowLimit(
        initialRows: Int,
        dimensionsMap: [Int: WindowPreviewHoverContainer.WindowDimensions],
        chromeHeight: CGFloat?,
        bestGuessMonitor: NSScreen
    ) -> Int {
        guard windowSwitcherActive,
              Defaults[.windowSwitcherScrollDirection] == .horizontal,
              !Defaults[.switcherIgnoreScreenLimit],
              initialRows > 1,
              let chromeHeight
        else { return initialRows }

        let tallestImage = dimensionsMap.values.map(\.size.height).max() ?? 0
        let itemHeight = tallestImage + chromeHeight
        guard itemHeight > 0 else { return initialRows }

        let metrics = WindowPreviewHoverContainer.PreviewLayoutMetrics.regular(
            paddingMultiplier: Defaults[.globalPaddingMultiplier]
        )
        let spacing = metrics.itemSpacing
        let availableHeight = bestGuessMonitor.visibleFrame.height - metrics.totalPanelInset * 2 - selectionAccessoryHeight - switcherTopAccessoryHeight
        let rowsThatFit = max(1, Int((availableHeight + spacing) / (itemHeight + spacing)))
        return min(initialRows, rowsThatFit)
    }

    /// True when `expectedContentSize` faithfully predicts the laid-out size, letting the panel skip the synchronous fittingSize pass.
    private(set) var expectedContentSizeIsExact: Bool = false

    @MainActor
    private func computeSwitcherContentSize(
        dimensionsMap: [Int: WindowPreviewHoverContainer.WindowDimensions],
        maxColumns: Int,
        maxRows: Int,
        minimumItemWidth: CGFloat,
        dockPosition: DockPosition,
        bestGuessMonitor: NSScreen,
        measuredChromeHeight: CGFloat?
    ) -> CGSize {
        expectedContentSizeIsExact = false
        let gridFlow = WindowPreviewHoverContainer.GridFlow.resolve(
            compact: false,
            windowSwitcherActive: true,
            dockPosition: dockPosition
        )

        guard !windows.isEmpty, maxColumns > 0, maxRows > 0,
              windows.allSatisfy({ !$0.isWindowlessApp && $0.image != nil }),
              dimensionsMap.count == windows.count,
              let chromeHeight = measuredChromeHeight ?? measureSwitcherCardChromeHeight(
                  dimensionsMap: dimensionsMap,
                  dockPosition: dockPosition,
                  bestGuessMonitor: bestGuessMonitor
              )
        else {
            return Self.computeExpectedContentSize(
                windowCount: windows.count,
                dimensionsMap: dimensionsMap,
                isHorizontal: gridFlow.laysOutItemsInRows,
                maxColumns: maxColumns,
                maxRows: maxRows,
                hasEmbeddedContent: hasEmbeddedContent,
                fillToLimit: gridFlow.fillsLinesToLimit,
                minimumItemWidth: minimumItemWidth
            )
        }

        let metrics = WindowPreviewHoverContainer.PreviewLayoutMetrics.regular(
            paddingMultiplier: Defaults[.globalPaddingMultiplier]
        )
        let itemSpacing = metrics.itemSpacing
        let padding = metrics.totalPanelInset
        let chunks = WindowPreviewHoverContainer.chunkArray(
            items: Array(windows.indices),
            isHorizontal: gridFlow.laysOutItemsInRows,
            maxColumns: maxColumns,
            maxRows: maxRows,
            fillToLimit: gridFlow.fillsLinesToLimit
        )

        let contentSize: CGSize
        if gridFlow.laysOutItemsInRows {
            var maxRowWidth: CGFloat = 0
            var totalHeight: CGFloat = 0
            for row in chunks {
                let cardSizes = row.compactMap { index -> CGSize? in
                    guard let dims = dimensionsMap[index] else { return nil }
                    return CGSize(width: max(dims.size.width, minimumItemWidth), height: dims.size.height + chromeHeight)
                }
                let rowWidth = cardSizes.map(\.width).reduce(0, +) + CGFloat(max(0, cardSizes.count - 1)) * itemSpacing
                maxRowWidth = max(maxRowWidth, rowWidth)
                totalHeight += cardSizes.map(\.height).max() ?? 0
            }
            totalHeight += CGFloat(max(0, chunks.count - 1)) * itemSpacing
            contentSize = CGSize(width: maxRowWidth, height: totalHeight)
        } else {
            var totalWidth: CGFloat = 0
            var maxColumnHeight: CGFloat = 0
            for column in chunks {
                let cardSizes = column.compactMap { index -> CGSize? in
                    guard let dims = dimensionsMap[index] else { return nil }
                    return CGSize(width: max(dims.size.width, minimumItemWidth), height: dims.size.height + chromeHeight)
                }
                totalWidth += cardSizes.map(\.width).max() ?? 0
                let columnHeight = cardSizes.map(\.height).reduce(0, +) + CGFloat(max(0, cardSizes.count - 1)) * itemSpacing
                maxColumnHeight = max(maxColumnHeight, columnHeight)
            }
            totalWidth += CGFloat(max(0, chunks.count - 1)) * itemSpacing
            contentSize = CGSize(width: totalWidth, height: maxColumnHeight)
        }

        expectedContentSizeIsExact = true
        return CGSize(width: contentSize.width + padding * 2, height: contentSize.height + padding * 2)
    }

    /// Measures one skeleton card in the selected state (the tallest case) to learn how much vertical chrome cards add around their image.
    @MainActor
    private func measureSwitcherCardChromeHeight(
        dimensionsMap: [Int: WindowPreviewHoverContainer.WindowDimensions],
        dockPosition: DockPosition,
        bestGuessMonitor: NSScreen
    ) -> CGFloat? {
        let sampleIndex = windows.indices.first(where: { i in
            let title = windows[i].windowName
            return title?.isEmpty == false && title != windows[i].app.localizedName
        }) ?? 0
        var sampleIndices = [sampleIndex]
        if Defaults[.enableMultiWindowSelection], !Defaults[.showUncheckedSelectionCheckboxes],
           let checkedIndex = windows.indices.first(where: { selection.checkedWindows.membership.contains(PreviewWindowIdentity(windows[$0])) }),
           checkedIndex != sampleIndex
        { sampleIndices.append(checkedIndex) }

        return sampleIndices.compactMap { sampleIndex -> CGFloat? in
            guard let dims = dimensionsMap[sampleIndex] else { return nil }
            let sample = WindowPreview(
                windowInfo: windows[sampleIndex],
                onTap: nil,
                index: sampleIndex,
                dockPosition: dockPosition,
                bestGuessMonitor: bestGuessMonitor,
                uniformCardRadius: Defaults[.uniformCardRadius],
                handleWindowAction: { _ in },
                isSelected: true,
                windowSwitcherActive: true,
                dimensions: dims,
                showAppIconOnly: Defaults[.showAppIconOnly],
                mockPreviewActive: false,
                onHoverIndexChange: nil,
                onDragHoverIndexChange: nil,
                useLivePreview: false,
                skeletonMode: true,
                appearance: PreviewAppearanceSettings.resolve(windowSwitcherActive: true, dockPosition: dockPosition),
                backgroundAppearance: BackgroundAppearance.resolve(),
                focusedWindowID: nil,
                currentSpaceNumbers: [],
                isChecked: selection.checkedWindows.membership.contains(PreviewWindowIdentity(windows[sampleIndex]))
            )
            let measured = NSHostingView(rootView: sample).fittingSize
            guard measured.height > 0 else { return nil }
            return max(0, measured.height - dims.size.height)
        }.max()
    }

    private static let estimatedEmbeddedWidgetHeight: CGFloat = 100

    private static func computeExpectedContentSize(
        windowCount: Int,
        dimensionsMap: [Int: WindowPreviewHoverContainer.WindowDimensions],
        isHorizontal: Bool,
        maxColumns: Int,
        maxRows: Int,
        hasEmbeddedContent: Bool = false,
        fillToLimit: Bool = false,
        minimumItemWidth: CGFloat = 0
    ) -> CGSize {
        guard windowCount > 0 else { return .zero }

        let metrics = WindowPreviewHoverContainer.PreviewLayoutMetrics.regular(
            paddingMultiplier: Defaults[.globalPaddingMultiplier]
        )
        let itemSpacing = metrics.itemSpacing
        let padding = metrics.totalPanelInset

        let chunks = WindowPreviewHoverContainer.chunkArray(
            items: Array(0 ..< windowCount),
            isHorizontal: isHorizontal,
            maxColumns: maxColumns,
            maxRows: maxRows,
            fillToLimit: fillToLimit
        )

        // Collect both flow-axis total and cross-axis max from all windows
        var maxItemWidth: CGFloat = 0
        var maxItemHeight: CGFloat = 0
        for dim in dimensionsMap.values {
            maxItemWidth = max(maxItemWidth, max(dim.size.width, minimumItemWidth))
            maxItemHeight = max(maxItemHeight, dim.size.height)
        }

        if isHorizontal {
            var maxRowWidth: CGFloat = 0

            for row in chunks {
                var rowWidth: CGFloat = 0
                for windowIndex in row {
                    let dims = dimensionsMap[windowIndex]
                    let itemWidth = dims?.size.width ?? dims?.maxDimensions.width ?? 0
                    rowWidth += max(itemWidth, minimumItemWidth)
                }
                rowWidth += CGFloat(max(0, row.count - 1)) * itemSpacing
                maxRowWidth = max(maxRowWidth, rowWidth)
            }

            if hasEmbeddedContent, let firstDims = dimensionsMap[0] {
                maxRowWidth += max(firstDims.size.width, minimumItemWidth) + itemSpacing
            }

            // Provide both axes: flow width from item sum, cross height from tallest preview
            return CGSize(width: maxRowWidth + padding * 2, height: maxItemHeight + padding * 2)
        } else {
            var maxColHeight: CGFloat = 0

            for col in chunks {
                var colHeight: CGFloat = 0
                for windowIndex in col {
                    let dims = dimensionsMap[windowIndex]
                    colHeight += dims?.size.height ?? dims?.maxDimensions.height ?? 0
                }
                colHeight += CGFloat(max(0, col.count - 1)) * itemSpacing
                maxColHeight = max(maxColHeight, colHeight)
            }

            if hasEmbeddedContent {
                maxColHeight += estimatedEmbeddedWidgetHeight + itemSpacing
            }

            // Provide both axes: flow height from item sum, cross width from widest preview
            return CGSize(width: maxItemWidth + padding * 2, height: maxColHeight + padding * 2)
        }
    }

    @MainActor
    private func updateIndexForSearch() {
        if !hasActiveSearch {
            if currIndex >= windows.count {
                updateSelectionIndex(windows.isEmpty ? -1 : 0, source: .programmatic)
            }
        } else {
            let filtered = filteredWindowIndices()
            updateSelectionIndex(filtered.first ?? -1, source: .programmatic)
        }
    }

    /// Returns the indices of windows that match the current search query.
    /// If no search is active, returns all window indices.
    func filteredWindowIndices() -> [Int] {
        if let cached = cachedFilteredIndices { return cached }

        let result: [Int]
        if !windowSwitcherActive || searchQuery.isEmpty {
            result = Array(windows.indices)
        } else {
            let query = searchQuery.lowercased()
            let fuzziness = Defaults[.searchFuzziness]
            result = windows.enumerated().compactMap { idx, win in
                let appName = win.app.localizedName?.lowercased() ?? ""
                let windowTitle = (win.windowName ?? "").lowercased()
                return (StringMatchingUtil.fuzzyMatch(query: query, target: appName, fuzziness: fuzziness) ||
                    StringMatchingUtil.fuzzyMatch(query: query, target: windowTitle, fuzziness: fuzziness)) ? idx : nil
            }
        }
        cachedFilteredIndices = result
        return result
    }

    // MARK: - Keyboard Navigation

    /// Cycle to the next window in the grid
    @MainActor
    func cycleForward() {
        pendingSpaceNavigation = nil
        navigationTarget = .windows
        guard !windows.isEmpty else { return }

        if hasActiveSearch {
            cycleFilteredForward()
            return
        }

        if currIndex < 0 {
            setIndex(to: 0, source: .keyboard)
            return
        }

        let forwardDirection: ArrowDirection = windowSwitcherActive && Defaults[.windowSwitcherScrollDirection] == .horizontal
            ? .down
            : .right
        let newIndex = WindowPreviewHoverContainer.navigateWindowSwitcher(
            from: currIndex,
            direction: forwardDirection,
            totalItems: windows.count,
            dockPosition: .bottom,
            isWindowSwitcherActive: true
        )
        setIndex(to: newIndex, source: .keyboard)
    }

    /// Cycle to the previous window in the grid
    @MainActor
    func cycleBackward() {
        pendingSpaceNavigation = nil
        navigationTarget = .windows
        guard !windows.isEmpty else { return }

        if hasActiveSearch {
            cycleFilteredBackward()
            return
        }

        if currIndex < 0 {
            setIndex(to: windows.count - 1, source: .keyboard)
            return
        }

        let backwardDirection: ArrowDirection = windowSwitcherActive && Defaults[.windowSwitcherScrollDirection] == .horizontal
            ? .up
            : .left
        let newIndex = WindowPreviewHoverContainer.navigateWindowSwitcher(
            from: currIndex,
            direction: backwardDirection,
            totalItems: windows.count,
            dockPosition: .bottom,
            isWindowSwitcherActive: true
        )
        setIndex(to: newIndex, source: .keyboard)
    }

    @MainActor
    private func cycleFilteredForward() {
        let filtered = filteredWindowIndices()
        guard !filtered.isEmpty else { return }

        if currIndex < 0 {
            setIndex(to: filtered.first ?? 0, source: .keyboard)
            return
        }

        if let currentPos = filtered.firstIndex(of: currIndex) {
            let nextPos = (currentPos + 1) % filtered.count
            setIndex(to: filtered[nextPos], source: .keyboard)
        } else {
            setIndex(to: filtered.first ?? 0, source: .keyboard)
        }
    }

    @MainActor
    private func cycleFilteredBackward() {
        let filtered = filteredWindowIndices()
        guard !filtered.isEmpty else { return }

        if currIndex < 0 {
            setIndex(to: filtered.last ?? 0, source: .keyboard)
            return
        }

        if let currentPos = filtered.firstIndex(of: currIndex) {
            let prevPos = (currentPos - 1 + filtered.count) % filtered.count
            setIndex(to: filtered[prevPos], source: .keyboard)
        } else {
            setIndex(to: filtered.last ?? 0, source: .keyboard)
        }
    }

    /// Navigate within filtered results using arrow direction
    @MainActor
    func navigateFiltered(direction: ArrowDirection, extendingSelection: Bool = false) {
        let filtered = filteredWindowIndices()
        guard !filtered.isEmpty else { return }

        guard let currentFilteredPos = filtered.firstIndex(of: currIndex) else {
            setIndex(to: filtered.first ?? 0, source: .keyboard)
            return
        }

        let newFilteredPos = WindowPreviewHoverContainer.navigateWindowSwitcher(
            from: currentFilteredPos,
            direction: direction,
            totalItems: filtered.count,
            dockPosition: .bottom,
            isWindowSwitcherActive: true,
            wraps: !extendingSelection
        )

        setIndex(to: filtered[newFilteredPos], source: .keyboard, extendingSelection: extendingSelection)
    }

    // MARK: - Window Switcher Initialization

    /// Initialize a Window Switcher session with its launch-specific initial selection.
    @MainActor
    func initializeForWindowSwitcher(
        with newWindows: [WindowInfo],
        dockPosition: DockPosition,
        bestGuessMonitor: NSScreen,
        startOnSecondWindow: Bool = Defaults[.useClassicWindowOrdering],
        startUnfocused: Bool = false
    ) {
        pendingSpaceNavigation = nil
        setWindows(newWindows, dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor)
        searchQuery = ""

        if startUnfocused {
            setIndex(to: -1, shouldScroll: false, source: .programmatic)
        } else if !windows.isEmpty {
            if startOnSecondWindow, windows.count >= 2 {
                setIndex(to: 1, shouldScroll: false, source: .keyboard)
            } else {
                setIndex(to: 0, shouldScroll: false, source: .keyboard)
            }
        } else {
            setIndex(to: -1, shouldScroll: false, source: .programmatic)
        }
    }

    /// Get the currently selected window
    func getCurrentWindow() -> WindowInfo? {
        guard currIndex >= 0, currIndex < windows.count else { return nil }
        return windows[currIndex]
    }
}
