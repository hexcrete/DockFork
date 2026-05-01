import Defaults
import SwiftUI

// Pure UI state container for window preview presentation
class PreviewStateCoordinator: ObservableObject {
    enum SelectionInputSource {
        case programmatic
        case keyboard
        case mouse
    }

    @Published var currIndex: Int = -1
    @Published private(set) var selectionInputSource: SelectionInputSource = .programmatic
    @Published var windowSwitcherActive: Bool = false {
        didSet { invalidateFilterCache() }
    }

    // MARK: - Keybind Session Tracking

    /// Tracks whether the window switcher was activated via keybind (not just visible)
    private(set) var isKeybindSessionActive: Bool = false

    @MainActor
    func activateKeybindSession() {
        isKeybindSessionActive = true
    }

    @MainActor
    func deactivateKeybindSession() {
        isKeybindSessionActive = false
        searchQuery = ""
    }

    // MARK: - UI State

    var hasMovedSinceOpen: Bool = false
    var initialHoverLocation: CGPoint?
    var fullWindowPreviewActive: Bool = false
    @Published var windows: [WindowInfo] = [] {
        didSet { invalidateFilterCache() }
    }

    var shouldScrollToIndex: Bool = true

    @Published var searchQuery: String = "" {
        didSet {
            invalidateFilterCache()
            if windowSwitcherActive {
                Task { @MainActor in
                    updateIndexForSearch()
                }
            }
        }
    }

    private var cachedFilteredIndices: [Int]?
    private func invalidateFilterCache() { cachedFilteredIndices = nil }

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
    }

    @MainActor
    private func updateSelectionIndex(_ requestedIndex: Int, source: SelectionInputSource, shouldScroll: Bool? = nil) {
        if let shouldScroll {
            shouldScrollToIndex = shouldScroll
        }

        if requestedIndex >= 0, requestedIndex < windows.count {
            currIndex = requestedIndex
        } else {
            currIndex = -1
        }
        selectionInputSource = source
    }

    @MainActor
    func setIndex(to: Int, shouldScroll: Bool = true, source: SelectionInputSource = .programmatic) {
        updateSelectionIndex(to, source: source, shouldScroll: shouldScroll)
    }

    @MainActor
    func clearSelectionIfMouseSource(shouldScroll: Bool = false) {
        guard selectionInputSource == .mouse else { return }
        updateSelectionIndex(-1, source: .programmatic, shouldScroll: shouldScroll)
    }

    @MainActor
    func setWindows(_ newWindows: [WindowInfo], dockPosition: DockPosition, bestGuessMonitor: NSScreen, isMockPreviewActive: Bool = false) {
        windows = newWindows
        lastKnownBestGuessMonitor = bestGuessMonitor

        if currIndex >= windows.count {
            updateSelectionIndex(windows.isEmpty ? -1 : windows.count - 1, source: .programmatic)
        }

        recomputeAndPublishDimensions(dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor, isMockPreviewActive: isMockPreviewActive)
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
        let selectedWindowID: CGWindowID? = (currIndex >= 0 && currIndex < windows.count) ? windows[currIndex].id : nil

        let freshWindowsByID: [CGWindowID: WindowInfo] = Dictionary(
            freshWindows.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let freshIDs = Set(freshWindowsByID.keys)
        let existingIDs = Set(windows.map(\.id))

        // Update existing windows in place
        for index in windows.indices {
            if let fresh = freshWindowsByID[windows[index].id] {
                windows[index] = fresh
            }
        }

        // Add new windows at the end
        for freshWindow in freshWindows where !existingIDs.contains(freshWindow.id) {
            windows.append(freshWindow)
        }

        // Remove stale windows
        let staleIDs = existingIDs.subtracting(freshIDs)
        if !staleIDs.isEmpty {
            windows.removeAll { staleIDs.contains($0.id) }
        }

        // Restore selection to the same window, or clamp if it was removed
        if let selectedID = selectedWindowID, let newIndex = windows.firstIndex(where: { $0.id == selectedID }) {
            updateSelectionIndex(newIndex, source: .programmatic)
        } else if currIndex >= windows.count {
            updateSelectionIndex(windows.isEmpty ? -1 : windows.count - 1, source: .programmatic)
        }

        lastKnownBestGuessMonitor = bestGuessMonitor
        recomputeAndPublishDimensions(dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor)

        if windows.count != previousWindowCount {
            onFrameRefreshNeeded?()
        }
    }

    @MainActor
    func updateWindow(at index: Int, with newInfo: WindowInfo) {
        guard index >= 0, index < windows.count else { return }
        windows[index] = newInfo
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
               let windowlessEntry = WindowUtil.getWindowlessRunningApps(existingWindows: windows)
               .first(where: { $0.app.processIdentifier == removedPID })
            {
                windows.append(windowlessEntry)
                insertedWindowlessIndex = windows.count - 1
            }
        }

        if windows.isEmpty {
            updateSelectionIndex(-1, source: .programmatic)
            SharedPreviewWindowCoordinator.activeInstance?.hideWindow()
            return
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
        // Gate additions by PID of the currently displayed windows (if any)
        guard let currentPid = windows.first?.app.processIdentifier else {
            // No active windows context; ignore additions to avoid cross-app injection
            return
        }
        let gated: [WindowInfo] = newWindowsToAdd.filter { $0.app.processIdentifier == currentPid }

        var windowsWereAdded = false
        for newWin in gated {
            if !windows.contains(where: { $0.id == newWin.id }) {
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
    }

    @MainActor
    func removeAllWindows() {
        windows.removeAll()
        updateSelectionIndex(-1, source: .programmatic)
        SharedPreviewWindowCoordinator.activeInstance?.hideWindow()
    }

    @MainActor
    func recomputeAndPublishDimensions(dockPosition: DockPosition, bestGuessMonitor: NSScreen, isMockPreviewActive: Bool = false) {
        let panelSize = getWindowSize()

        let newOverallMaxDimension = WindowPreviewHoverContainer.calculateOverallMaxDimensions(
            windows: windows,
            dockPosition: dockPosition,
            isWindowSwitcherActive: windowSwitcherActive,
            isMockPreviewActive: isMockPreviewActive,
            sharedPanelWindowSize: panelSize
        )

        let (cols, rows) = WindowPreviewHoverContainer.calculateEffectiveMaxColumnsAndRows(
            bestGuessMonitor: bestGuessMonitor,
            overallMaxDimensions: newOverallMaxDimension,
            dockPosition: dockPosition,
            isWindowSwitcherActive: windowSwitcherActive,
            previewMaxColumns: Defaults[.previewMaxColumns],
            previewMaxRows: Defaults[.previewMaxRows],
            switcherMaxRows: Defaults[.switcherMaxRows],
            totalItems: windows.count
        )

        let newDimensionsMap = WindowPreviewHoverContainer.precomputeWindowDimensions(
            windows: windows,
            overallMaxDimensions: newOverallMaxDimension,
            bestGuessMonitor: bestGuessMonitor,
            dockPosition: dockPosition,
            isWindowSwitcherActive: windowSwitcherActive,
            effectiveMaxColumns: cols,
            effectiveMaxRows: rows
        )

        dimensionState = DimensionState(
            overallMaxPreviewDimension: newOverallMaxDimension,
            windowDimensionsMap: newDimensionsMap,
            effectiveGridColumns: cols,
            effectiveGridRows: rows
        )

        let compactThreshold = Defaults[.dockPreviewCompactThreshold]
        let wouldUseCompactMode = Defaults[.disableImagePreview]
            || (compactThreshold > 0 && windows.count >= compactThreshold)

        if Defaults[.allowDynamicImageSizing], !windowSwitcherActive, !wouldUseCompactMode {
            expectedContentSize = Self.computeExpectedContentSize(
                windowCount: windows.count,
                dimensionsMap: newDimensionsMap,
                isHorizontal: dockPosition.isHorizontalFlow,
                maxColumns: cols,
                maxRows: rows,
                hasEmbeddedContent: hasEmbeddedContent
            )
        } else {
            expectedContentSize = .zero
        }
    }

    private static let estimatedEmbeddedWidgetHeight: CGFloat = 100

    private static func computeExpectedContentSize(
        windowCount: Int,
        dimensionsMap: [Int: WindowPreviewHoverContainer.WindowDimensions],
        isHorizontal: Bool,
        maxColumns: Int,
        maxRows: Int,
        hasEmbeddedContent: Bool = false
    ) -> CGSize {
        guard windowCount > 0 else { return .zero }

        let itemSpacing = HoverContainerPadding.itemSpacing
        let padding = HoverContainerPadding.totalPerSide()

        let chunks = WindowPreviewHoverContainer.chunkArray(
            items: Array(0 ..< windowCount),
            isHorizontal: isHorizontal,
            maxColumns: maxColumns,
            maxRows: maxRows
        )

        // Collect both flow-axis total and cross-axis max from all windows
        var maxItemWidth: CGFloat = 0
        var maxItemHeight: CGFloat = 0
        for dim in dimensionsMap.values {
            maxItemWidth = max(maxItemWidth, dim.size.width)
            maxItemHeight = max(maxItemHeight, dim.size.height)
        }

        if isHorizontal {
            var maxRowWidth: CGFloat = 0

            for row in chunks {
                var rowWidth: CGFloat = 0
                for windowIndex in row {
                    let dims = dimensionsMap[windowIndex]
                    rowWidth += dims?.size.width ?? dims?.maxDimensions.width ?? 0
                }
                rowWidth += CGFloat(max(0, row.count - 1)) * itemSpacing
                maxRowWidth = max(maxRowWidth, rowWidth)
            }

            if hasEmbeddedContent, let firstDims = dimensionsMap[0] {
                maxRowWidth += firstDims.size.width + itemSpacing
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
        guard !windows.isEmpty else { return }

        if hasActiveSearch {
            cycleFilteredForward()
            return
        }

        if currIndex < 0 {
            setIndex(to: 0, source: .keyboard)
            return
        }

        let forwardDirection: ArrowDirection = .right
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
        guard !windows.isEmpty else { return }

        if hasActiveSearch {
            cycleFilteredBackward()
            return
        }

        if currIndex < 0 {
            setIndex(to: windows.count - 1, source: .keyboard)
            return
        }

        let backwardDirection: ArrowDirection = .left
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
    func navigateFiltered(direction: ArrowDirection) {
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
            isWindowSwitcherActive: true
        )

        setIndex(to: filtered[newFilteredPos], source: .keyboard)
    }

    // MARK: - Window Switcher Initialization

    /// Initialize for window switcher keybind activation
    @MainActor
    func initializeForWindowSwitcher(with newWindows: [WindowInfo], dockPosition: DockPosition, bestGuessMonitor: NSScreen) {
        setWindows(newWindows, dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor)
        searchQuery = ""

        if !windows.isEmpty {
            if Defaults[.useClassicWindowOrdering], windows.count >= 2 {
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
