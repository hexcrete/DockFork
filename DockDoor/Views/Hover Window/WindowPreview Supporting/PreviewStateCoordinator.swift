import ApplicationServices
import Defaults
import SwiftUI

/// Isolated so index changes only invalidate views that read it, not the entire preview container.
final class SwitcherSelectionState: ObservableObject {
    @Published var currIndex: Int = -1
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
        set { selection.currIndex = newValue }
    }

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

    @Published private(set) var focusedWindowID: CGWindowID?

    var shouldScrollToIndex: Bool = true

    @Published var searchQuery: String = "" {
        didSet {
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
    private func invalidateFilterCache() {
        cachedFilteredIndices = nil
    }

    @MainActor
    func setFocusedWindowID(_ windowID: CGWindowID?) {
        focusedWindowID = windowID
    }

    @MainActor
    func refreshFocusedWindowID(from newWindows: [WindowInfo]? = nil) {
        let sourceWindows = newWindows ?? windows
        if let focusedWindowID,
           sourceWindows.contains(where: { $0.id == focusedWindowID })
        {
            return
        }
        focusedWindowID = nil
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
    private func updateSelectionIndex(_ requestedIndex: Int, source: SelectionInputSource, shouldScroll: Bool? = nil) {
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
    func setIndex(to: Int, shouldScroll: Bool = true, source: SelectionInputSource = .programmatic) {
        updateSelectionIndex(to, source: source, shouldScroll: shouldScroll)
    }

    @MainActor
    func registerMouseMovementSinceOpen(at location: CGPoint = NSEvent.mouseLocation) -> Bool {
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
    func clearSelectionIfMouseSource(shouldScroll: Bool = false) {
        guard selectionInputSource == .mouse else { return }
        updateSelectionIndex(-1, source: .programmatic, shouldScroll: shouldScroll)
    }

    @MainActor
    func setWindows(_ newWindows: [WindowInfo], dockPosition: DockPosition, bestGuessMonitor: NSScreen, isMockPreviewActive: Bool = false) {
        windows = newWindows
        refreshFocusedWindowID(from: newWindows)
        lastKnownBestGuessMonitor = bestGuessMonitor

        if currIndex >= windows.count {
            updateSelectionIndex(windows.isEmpty ? -1 : windows.count - 1, source: .programmatic)
        }

        recomputeAndPublishDimensions(dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor, isMockPreviewActive: isMockPreviewActive)
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
            setIndex(to: restoredIndex, shouldScroll: false, source: previousSelectionSource)
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
        recomputeAndPublishDimensions(dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor)

        if windows.count != previousWindowCount {
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

            // Keep fullscreen cache fresh so hidden-tag semantics remain correct across mixed fullscreen/non-fullscreen apps.
            let liveFullscreen = try? row.axElement.isFullscreen()
            if row.isFullscreen != liveFullscreen {
                row.isFullscreen = liveFullscreen
                hasPublishedChanges = true
            }

            if row.isHidden != isHidden {
                row.isHidden = isHidden
                hasPublishedChanges = true
            }

            updatedWindows[index] = row
            WindowUtil.updateCachedWindowState(row, isHidden: isHidden, isFullscreen: row.isFullscreen)
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
                syncVisibilityState(processIdentifier: pid)
            }

            visibilitySyncTasksByPID.removeValue(forKey: pid)
        }
    }

    @MainActor
    private func syncVisibilityState(processIdentifier pid: pid_t) {
        var updatedWindows = windows
        var hasPublishedChanges = false

        for index in updatedWindows.indices where updatedWindows[index].app.processIdentifier == pid {
            guard !updatedWindows[index].isWindowlessApp else { continue }
            var row = updatedWindows[index]

            if let isMinimized = try? row.axElement.isMinimized(), row.isMinimized != isMinimized {
                row.isMinimized = isMinimized
                hasPublishedChanges = true
            }

            let isHidden = (try? row.appAxElement.attribute(kAXHiddenAttribute, Bool.self)) ?? row.app.isHidden
            if row.isHidden != isHidden {
                row.isHidden = isHidden
                hasPublishedChanges = true
            }

            let isFullscreen = try? row.axElement.isFullscreen()
            if row.isFullscreen != isFullscreen {
                row.isFullscreen = isFullscreen
                hasPublishedChanges = true
            }

            updatedWindows[index] = row
            WindowUtil.updateCachedWindowState(
                row,
                isMinimized: row.isMinimized,
                isHidden: row.isHidden,
                isFullscreen: row.isFullscreen
            )
        }

        if hasPublishedChanges {
            windows = updatedWindows
        }
    }

    @MainActor
    func applyCacheChanges(removed: [WindowInfo], added: [WindowInfo], updated: [WindowInfo]) {
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
            windows.contains(where: { $0.id == windowID }) ? windowID : nil
        } ?? frontmostPID.flatMap { pid in
            windows
                .filter { $0.app.processIdentifier == pid }
                .max(by: { $0.lastAccessedTime < $1.lastAccessedTime })?
                .id
        }
        if focusedWindowID != refreshedWindowID {
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
            totalItems: windows.count
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
        let wouldUseCompactMode = Defaults[.disableImagePreview]
            || (compactThreshold > 0 && windows.count >= compactThreshold)
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

        let spacing = HoverContainerPadding.itemSpacing
        let availableHeight = bestGuessMonitor.visibleFrame.height - HoverContainerPadding.totalPerSide() * 2
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

        let itemSpacing = HoverContainerPadding.itemSpacing
        let padding = HoverContainerPadding.totalPerSide()
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
            currentSpaceNumbers: []
        )
        let measured = NSHostingView(rootView: sample).fittingSize
        guard measured.height > 0 else { return nil }
        return max(0, measured.height - dims.size.height)
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

        let itemSpacing = HoverContainerPadding.itemSpacing
        let padding = HoverContainerPadding.totalPerSide()

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

    /// Initialize a Window Switcher session with its launch-specific initial selection.
    @MainActor
    func initializeForWindowSwitcher(
        with newWindows: [WindowInfo],
        dockPosition: DockPosition,
        bestGuessMonitor: NSScreen,
        startOnSecondWindow: Bool = Defaults[.useClassicWindowOrdering],
        startUnfocused: Bool = false
    ) {
        setWindows(newWindows, dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor)
        searchQuery = ""
        hasMovedSinceOpen = false
        initialHoverLocation = NSEvent.mouseLocation

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
