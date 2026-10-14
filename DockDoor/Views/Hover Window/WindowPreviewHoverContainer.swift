import AppKit
import Defaults
import ScreenCaptureKit
import SwiftUI

enum FlowItem: Hashable, Identifiable {
    case embedded
    case window(Int)

    var id: String {
        switch self {
        case .embedded:
            "embedded"
        case let .window(index):
            "window-\(index)"
        }
    }
}

class MockPreviewWindow: WindowPropertiesProviding {
    var windowID: CGWindowID
    var frame: CGRect
    var title: String?
    var owningApplicationBundleIdentifier: String?
    var owningApplicationProcessID: pid_t?
    var isOnScreen: Bool
    var windowLayer: Int

    init(windowID: CGWindowID, frame: CGRect, title: String?, owningApplicationBundleIdentifier: String?, owningApplicationProcessID: pid_t?, isOnScreen: Bool, windowLayer: Int) {
        self.windowID = windowID
        self.frame = frame
        self.title = title
        self.owningApplicationBundleIdentifier = owningApplicationBundleIdentifier
        self.owningApplicationProcessID = owningApplicationProcessID
        self.isOnScreen = isOnScreen
        self.windowLayer = windowLayer
    }
}

/// Observes selection in isolation so index changes re-evaluate only the wrapped card, not the container body.
private struct SelectionReader<Content: View>: View {
    @ObservedObject var selection: SwitcherSelectionState
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        content(selection.currIndex)
    }
}

struct WindowPreviewHoverContainer: View {
    private struct DeferredActionWatcher {
        let token: UUID
        let task: Task<Void, Never>
    }

    private struct DeferredRefreshTask {
        let token: UUID
        let task: Task<Void, Never>
    }

    let appName: String
    let onWindowTap: (() -> Void)?
    let dockPosition: DockPosition
    let mouseLocation: CGPoint?
    let bestGuessMonitor: NSScreen
    let dockItemElement: AXUIElement?
    let dockItemFrameOverride: CGRect?
    var mockPreviewActive: Bool
    let updateAvailable: Bool
    let embeddedContentType: EmbeddedContentType
    let hasScreenRecordingPermission: Bool
    let appearanceOverride: PreviewAppearanceSettings?

    @ObservedObject var previewStateCoordinator: PreviewStateCoordinator

    @Default(.uniformCardRadius) var uniformCardRadius

    // MARK: - Dock Preview Header Settings

    @Default(.showAppName) var showAppTitleData
    @Default(.showAppIconOnly) var showAppIconOnly
    @Default(.appNameStyle) var appNameStyle

    // MARK: - Cmd+Tab Header Settings

    @Default(.cmdTabShowAppName) var cmdTabShowAppName
    @Default(.cmdTabAppNameStyle) var cmdTabAppNameStyle
    @Default(.cmdTabShowAppIconOnly) var cmdTabShowAppIconOnly

    @Default(.windowTitlePosition) var windowTitlePosition
    @Default(.aeroShakeAction) var aeroShakeAction
    @Default(.previewMaxColumns) var previewMaxColumns
    @Default(.previewMaxRows) var previewMaxRows
    @Default(.switcherMaxRows) var switcherMaxRows
    @Default(.gradientColorPalette) var gradientColorPalette
    @Default(.showAnimations) var showAnimations
    @Default(.enableMouseHoverInSwitcher) var enableMouseHoverInSwitcher
    @Default(.enableWindowSwitcherEdgeAutoScroll) var enableWindowSwitcherEdgeAutoScroll
    @Default(.mouseHoverAutoScrollSpeed) var mouseHoverAutoScrollSpeed
    @Default(.enableDockPreviewEdgeAutoScroll) var enableDockPreviewEdgeAutoScroll
    @Default(.dockPreviewEdgeAutoScrollSpeed) var dockPreviewEdgeAutoScrollSpeed
    @Default(.enableCmdTabEdgeAutoScroll) var enableCmdTabEdgeAutoScroll
    @Default(.cmdTabEdgeAutoScrollSpeed) var cmdTabEdgeAutoScrollSpeed
    @Default(.windowSwitcherLivePreviewScope) var windowSwitcherLivePreviewScope

    // Live preview settings for compact fallback computation
    @Default(.enableLivePreview) var enableLivePreview
    @Default(.enableLivePreviewForDock) var enableLivePreviewForDock
    @Default(.enableLivePreviewForWindowSwitcher) var enableLivePreviewForWindowSwitcher

    // Compact mode thresholds (0 = disabled, 1+ = enable when window count >= threshold)
    @Default(.windowSwitcherCompactThreshold) var windowSwitcherCompactThreshold
    @Default(.dockPreviewCompactThreshold) var dockPreviewCompactThreshold
    @Default(.cmdTabCompactThreshold) var cmdTabCompactThreshold

    // Force list view settings
    @Default(.showMassActionButtons) var showMassActionButtons
    @Default(.disableImagePreview) var disableImagePreview
    @Default(.previewWidth) var previewWidth
    @Default(.compactModeWidth) var compactModeWidth
    @Default(.enableHoverActionsInCompactMode) var enableHoverActionsInCompactMode

    private struct PreviewDragSession {
        let token = UUID()
        let identity: PreviewWindowIdentity
        let window: WindowInfo
        let targets: [PreviewDragTarget]
        let draggedIdentities: Set<PreviewWindowIdentity>
        var consumedByShake = false
        var isCompletingDrop = false
    }

    @State private var dragSession: PreviewDragSession?
    @State private var dragCompletionTask: Task<Void, Never>?
    @State private var isDragging = false

    @State private var hasAppeared: Bool = false
    @State private var appIcon: NSImage? = nil
    @State private var hoveringAppIcon: Bool = false

    @State private var dragPoints: [CGPoint] = []
    @State private var lastShakeCheck: Date = .init()
    @State private var edgeScrollRequest: CardGridScrollView.EdgeScrollRequest?
    @State private var edgeScrollHoverSize: CGSize = .zero
    @State private var scrolledFromStart = false
    @State private var scrolledToEnd = true
    @State private var dynamicFadeEnabled = false
    @State private var cachedAppearance: PreviewAppearanceSettings? = nil
    @State private var backgroundAppearance: BackgroundAppearance = .resolve()
    @State private var dockHighlightActionTimer: Timer?
    @State private var dockHighlightActionID: UUID?
    @State private var fullPreviewHoverID: UUID?
    @State private var deferredActionWatchersByKey: [String: DeferredActionWatcher] = [:]
    @State private var deferredRefreshTasksByKey: [String: DeferredRefreshTask] = [:]

    init(appName: String,
         onWindowTap: (() -> Void)?,
         dockPosition: DockPosition,
         mouseLocation: CGPoint?,
         bestGuessMonitor: NSScreen,
         dockItemElement: AXUIElement?,
         dockItemFrameOverride: CGRect? = nil,
         windowSwitcherCoordinator: PreviewStateCoordinator,
         mockPreviewActive: Bool,
         updateAvailable: Bool,
         embeddedContentType: EmbeddedContentType = .none,
         hasScreenRecordingPermission: Bool,
         appearanceOverride: PreviewAppearanceSettings? = nil)
    {
        self.appName = appName
        self.onWindowTap = onWindowTap
        self.dockPosition = dockPosition
        self.mouseLocation = mouseLocation
        self.bestGuessMonitor = bestGuessMonitor
        self.dockItemElement = dockItemElement
        self.dockItemFrameOverride = dockItemFrameOverride
        previewStateCoordinator = windowSwitcherCoordinator
        self.mockPreviewActive = mockPreviewActive
        self.updateAvailable = updateAvailable
        self.embeddedContentType = embeddedContentType
        self.hasScreenRecordingPermission = hasScreenRecordingPermission
        self.appearanceOverride = appearanceOverride
    }

    private var embeddedContentWidth: CGFloat {
        let calculatedDimensionsMap = previewStateCoordinator.dimensionState.windowDimensionsMap

        guard !calculatedDimensionsMap.isEmpty else {
            let fallback = MediaControlsLayout.embeddedArtworkSize + MediaControlsLayout.artworkTextSpacing + 165
            return usesCompactRows ? compactModeWidth + compactEmbeddedContentOverflow : fallback
        }

        var minWidth = 0.0

        for dimension in calculatedDimensionsMap {
            let width = dimension.value.size.width
            if minWidth == 0 || width < minWidth {
                minWidth = width
            }
        }

        if usesCompactRows {
            return compactModeWidth + compactEmbeddedContentOverflow
        }

        return minWidth
    }

    private var compactEmbeddedContentOverflow: CGFloat {
        2 * CardRadius.innerPadding
    }

    private var usesCompactRows: Bool {
        Self.usesCompactRows(
            isMockPreviewActive: mockPreviewActive,
            forceCompact: disableImagePreview || !hasScreenRecordingPermission,
            windowCount: previewStateCoordinator.windows.count,
            threshold: compactModeThreshold
        )
    }

    private var compactModeThreshold: Int {
        if previewStateCoordinator.windowSwitcherActive {
            windowSwitcherCompactThreshold
        } else if dockPosition == .cmdTab {
            cmdTabCompactThreshold
        } else {
            dockPreviewCompactThreshold
        }
    }

    // MARK: - Context-based header settings

    private var effectiveShowAppName: Bool {
        if dockPosition == .cmdTab {
            cmdTabShowAppName
        } else {
            showAppTitleData
        }
    }

    private var effectiveAppNameStyle: AppNameStyle {
        if dockPosition == .cmdTab {
            cmdTabAppNameStyle
        } else {
            appNameStyle
        }
    }

    private var effectiveShowAppIconOnly: Bool {
        if dockPosition == .cmdTab {
            cmdTabShowAppIconOnly
        } else {
            showAppIconOnly
        }
    }

    private var effectiveShouldShowHeader: Bool {
        if previewStateCoordinator.windowSwitcherActive {
            return false
        }
        return effectiveShowAppName
    }

    private var resolvedAppearance: PreviewAppearanceSettings {
        appearanceOverride ?? cachedAppearance ?? PreviewAppearanceSettings.resolve(
            windowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
            dockPosition: dockPosition
        )
    }

    private var usesHighlightAction: Bool {
        !mockPreviewActive && hoverActionEnabled
    }

    private var hoverActionEnabled: Bool {
        let action = resolvedAppearance.previewHoverAction
        let isCompact = usesCompactRows
        let permissionAllowsIt = !isCompact || hasScreenRecordingPermission
        return action != .none &&
            (!isCompact || enableHoverActionsInCompactMode) &&
            permissionAllowsIt
    }

    private func cancelDockHighlightAction() {
        dockHighlightActionTimer?.invalidate()
        dockHighlightActionTimer = nil
        dockHighlightActionID = nil
        if let fullPreviewHoverID {
            SharedPreviewWindowCoordinator.activeInstance?.cancelFullPreviewHover(fullPreviewHoverID)
            self.fullPreviewHoverID = nil
        } else {
            SharedPreviewWindowCoordinator.activeInstance?.hideFullPreviewWindow()
        }
    }

    @MainActor
    private func deferredWatcherKey(pid: pid_t, action: WindowAction, purpose: String = "dismiss") -> String {
        "\(pid)-\(action.rawValue)-\(purpose)"
    }

    @MainActor
    private func deferredRefreshKey(pid: pid_t, purpose: String) -> String {
        "\(pid)-\(purpose)"
    }

    @MainActor
    private var shouldRunDeferredWatchers: Bool {
        hasAppeared
    }

    @MainActor
    private func cancelAllDeferredActionWatchers() {
        for watcher in deferredActionWatchersByKey.values {
            watcher.task.cancel()
        }
        deferredActionWatchersByKey.removeAll()
    }

    @MainActor
    private func startDeferredRefreshTask(
        pid: pid_t,
        purpose: String,
        operation: @escaping () async -> Void
    ) {
        let key = deferredRefreshKey(pid: pid, purpose: purpose)
        deferredRefreshTasksByKey[key]?.task.cancel()

        let token = UUID()
        let task = Task {
            await operation()
            await MainActor.run {
                if deferredRefreshTasksByKey[key]?.token == token {
                    deferredRefreshTasksByKey.removeValue(forKey: key)
                }
            }
        }
        deferredRefreshTasksByKey[key] = DeferredRefreshTask(token: token, task: task)
    }

    @MainActor
    private func startDeferredActionWatcher(
        pid: pid_t,
        action: WindowAction,
        purpose: String = "dismiss",
        operation: @escaping @MainActor () async -> Void
    ) {
        let key = deferredWatcherKey(pid: pid, action: action, purpose: purpose)
        deferredActionWatchersByKey[key]?.task.cancel()

        let token = UUID()
        let task = Task { @MainActor in
            await operation()
            if deferredActionWatchersByKey[key]?.token == token {
                deferredActionWatchersByKey.removeValue(forKey: key)
            }
        }
        deferredActionWatchersByKey[key] = DeferredActionWatcher(token: token, task: task)
    }

    private func performHighlightActionIfNeeded() {
        guard usesHighlightAction, dragSession == nil else {
            cancelDockHighlightAction()
            return
        }

        let appearance = resolvedAppearance
        let selectedIndex = previewStateCoordinator.currIndex
        let selectionInputSource = previewStateCoordinator.selectionInputSource
        guard selectedIndex >= 0, selectedIndex < previewStateCoordinator.windows.count else {
            cancelDockHighlightAction()
            return
        }
        guard selectionInputSource != .programmatic else {
            cancelDockHighlightAction()
            return
        }

        cancelDockHighlightAction()
        let selectedWindow = previewStateCoordinator.windows[selectedIndex]
        guard !selectedWindow.isWindowlessApp else {
            cancelDockHighlightAction()
            return
        }
        let selectedWindowID = selectedWindow.id
        let actionID = UUID()
        dockHighlightActionID = actionID

        let performAction: () -> Void = {
            guard dockHighlightActionID == actionID else { return }
            guard let resolvedIndex = previewStateCoordinator.windows.firstIndex(where: { $0.id == selectedWindowID }) else {
                cancelDockHighlightAction()
                return
            }
            let resolvedWindow = previewStateCoordinator.windows[resolvedIndex]

            switch appearance.previewHoverAction {
            case .none:
                cancelDockHighlightAction()
            case .tap:
                if resolvedWindow.isMinimized {
                    handleWindowAction(.minimize, at: resolvedIndex)
                } else if resolvedWindow.isEffectivelyHiddenForUI {
                    handleWindowAction(.hide, at: resolvedIndex)
                } else {
                    resolvedWindow.bringToFront()
                    onWindowTap?()
                }
            case .previewFullSize:
                guard let coordinator = SharedPreviewWindowCoordinator.activeInstance,
                      let hoverID = coordinator.beginFullPreviewHover()
                else { return }
                fullPreviewHoverID = hoverID
                coordinator.showWindow(
                    appName: resolvedWindow.app.localizedName ?? "Unknown",
                    windows: [resolvedWindow],
                    mouseScreen: bestGuessMonitor,
                    dockItemElement: nil,
                    overrideDelay: true,
                    centeredHoverWindowState: .fullWindowPreview,
                    fullPreviewHoverID: hoverID
                )
            }
        }

        dockHighlightActionTimer?.invalidate()
        dockHighlightActionTimer = nil

        if appearance.tapEquivalentInterval == 0 {
            performAction()
        } else {
            dockHighlightActionTimer = Timer.scheduledTimer(withTimeInterval: appearance.tapEquivalentInterval, repeats: false) { _ in
                performAction()
            }
        }
    }

    private var hasPendingHighlightAction: Bool {
        dockHighlightActionTimer != nil || dockHighlightActionID != nil
    }

    private func refreshHighlightActionIfNeeded() {
        guard usesHighlightAction || hasPendingHighlightAction else { return }
        performHighlightActionIfNeeded()
    }

    private func handleHoverIndexChange(_ hoveredIndex: Int?, _ location: CGPoint?) -> Bool {
        let isWindowSwitcher = previewStateCoordinator.windowSwitcherActive
        let isCmdTabPreview = !isWindowSwitcher && dockPosition == .cmdTab
        let isDockPreview = !isWindowSwitcher && !isCmdTabPreview
        guard isWindowSwitcher || isDockPreview || isCmdTabPreview else { return false }
        if isWindowSwitcher, !enableMouseHoverInSwitcher { return false }
        guard edgeScrollRequest == nil else { return false }

        guard let hoveredIndex else {
            if isDockPreview || isWindowSwitcher || isCmdTabPreview {
                previewStateCoordinator.clearSelectionIfMouseSource(shouldScroll: false)
                refreshHighlightActionIfNeeded()
            }
            return false
        }

        if !previewStateCoordinator.registerMouseMovementSinceOpen() {
            return false
        }
        guard hoveredIndex != previewStateCoordinator.currIndex else { return true }

        previewStateCoordinator.setIndex(to: hoveredIndex, shouldScroll: false, source: .mouse)
        return true
    }

    private func handleDragHoverIndexChange(_ hoveredIndex: Int?) {
        guard enableMouseHoverInSwitcher else { return }
        guard let hoveredIndex else { return }
        guard hoveredIndex != previewStateCoordinator.currIndex else { return }

        guard previewStateCoordinator.registerMouseMovementSinceOpen() else { return }

        previewStateCoordinator.setIndex(to: hoveredIndex, shouldScroll: false)
    }

    private func handleAppHeaderHover(_ hovering: Bool) {
        let shouldShowHover = hovering && previewStateCoordinator.registerMouseMovementSinceOpen()
        if hoveringAppIcon != shouldShowHover {
            hoveringAppIcon = shouldShowHover
        }
    }

    private var radii: CardRadius.Resolved {
        (appearanceOverride ?? cachedAppearance)?.radii ?? .current()
    }

    private var showsSelectionSummary: Bool {
        !mockPreviewActive && resolvedAppearance.showWindowSelectionSummary && previewStateCoordinator.checkedWindowCount > 0
    }

    private var selectionSummary: some View {
        PreviewSelectionStrip(coordinator: previewStateCoordinator,
                              style: previewStateCoordinator.selectionSummaryStyle,
                              backgroundAppearance: backgroundAppearance)
            .fixedSize(horizontal: true, vertical: true)
    }

    var body: some View {
        BaseHoverContainer(
            bestGuessMonitor: bestGuessMonitor,
            mockPreviewActive: mockPreviewActive,
            content: { windowGridContent() },
            backgroundAppearance: backgroundAppearance,
            cornerRadius: radii.container
        )
        .padding(.bottom, showsSelectionSummary && previewStateCoordinator.selectionSummaryStyle == .popover
            ? PreviewHeaderLayout.contentReservation(for: .popover) : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            activateApp()
        }
        .padding(.top, (!previewStateCoordinator.windowSwitcherActive && effectiveAppNameStyle == .popover && effectiveShowAppName) ? PreviewHeaderLayout.contentReservation(for: .popover) : 0)
        .overlay {
            if !mockPreviewActive, !isDragging {
                WindowDismissalContainer(appName: appName,
                                         bestGuessMonitor: bestGuessMonitor,
                                         dockPosition: dockPosition,
                                         dockItemElement: dockItemElement,
                                         applicationProcessIdentifier: previewStateCoordinator.windows.first?.app.processIdentifier,
                                         applicationBundleIdentifier: previewStateCoordinator.windows.first?.app.bundleIdentifier,
                                         dockItemFrameOverride: dockItemFrameOverride,
                                         originalMouseLocation: mouseLocation,
                                         reportsInteractionBounds: true,
                                         minimizeAllWindowsCallback: { wasAppActiveBeforeClick in
                                             minimizeAllWindows(wasAppActiveBeforeClick: wasAppActiveBeforeClick)
                                         })
                    .padding(PreviewHeaderLayout.dismissalInsets(
                        appHeaderStyle: !previewStateCoordinator.windowSwitcherActive && effectiveShouldShowHeader ? effectiveAppNameStyle : nil,
                        selectionSummaryStyle: showsSelectionSummary ? previewStateCoordinator.selectionSummaryStyle : nil
                    ))
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            hasAppeared = true
            loadAppIcon()
            if Defaults[.enableLivePreview], Defaults[.livePreviewStreamKeepAlive] != 0 {
                LiveCaptureManager.shared.panelOpened()
            }
            if #available(macOS 15.0, *) {
                dynamicFadeEnabled = true
            }
            previewStateCoordinator.scheduleActiveFocusedWindowRefresh()
            refreshHighlightActionIfNeeded()
        }
        .onDisappear {
            hasAppeared = false
            cancelPreviewDrag()
            if Defaults[.enableLivePreview], Defaults[.livePreviewStreamKeepAlive] != 0 {
                Task { await LiveCaptureManager.shared.panelClosed() }
            }
            edgeScrollRequest = nil
            cancelDockHighlightAction()
            cancelAllDeferredActionWatchers()
        }
        .onChange(of: previewStateCoordinator.windows.map(PreviewWindowIdentity.init)) { identities in
            if let dragSession, !identities.contains(dragSession.identity),
               !dragSession.isCompletingDrop || dragSession.window.app.isTerminated
            {
                cancelPreviewDrag()
            }
        }
        .onChange(of: previewStateCoordinator.windowSwitcherActive) { isActive in
            if !isActive {
                previewStateCoordinator.searchQuery = ""
                edgeScrollRequest = nil
            }
            refreshHighlightActionIfNeeded()
        }
        .onChange(of: previewStateCoordinator.pointerInteractionSessionID) { _ in
            hoveringAppIcon = false
            cancelPreviewDrag()
        }
        .onChange(of: previewStateCoordinator.selectionSummaryStyle) { _ in
            if showsSelectionSummary { previewStateCoordinator.refreshSelectionLayout() }
        }
        .task(id: [previewStateCoordinator.windowSwitcherActive, cachedAppearance?.enableMultiWindowSelection ?? Defaults[.enableMultiWindowSelection]]) {
            let keys = PreviewAppearanceSettings.observedKeys + BackgroundAppearance.observedKeys
            for await _ in Defaults.updates(keys, initial: true) {
                let previousAppearance = cachedAppearance
                let updated = PreviewAppearanceSettings.resolve(
                    windowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
                    dockPosition: dockPosition
                )
                if updated != cachedAppearance { cachedAppearance = updated }
                if let previousAppearance, previousAppearance.showWindowSelectionSummary != updated.showWindowSelectionSummary,
                   previewStateCoordinator.checkedWindowCount > 0
                {
                    previewStateCoordinator.refreshSelectionLayout()
                }
                if !updated.enableMultiWindowSelection, previewStateCoordinator.checkedWindowCount > 0 {
                    previewStateCoordinator.clearCheckedWindows(resetOwnership: true)
                }
                if !updated.enableWindowDragTiling { previewStateCoordinator.setPreviewDragTarget(nil) }
                let updatedBg = BackgroundAppearance.resolve()
                if updatedBg != backgroundAppearance { backgroundAppearance = updatedBg }

                let didHoverActionChange = previousAppearance?.previewHoverAction != updated.previewHoverAction
                let didDelayChange = previousAppearance?.tapEquivalentInterval != updated.tapEquivalentInterval
                let didActiveBorderVisibilityChange = previousAppearance?.showActiveWindowBorder != updated.showActiveWindowBorder
                if didHoverActionChange || didDelayChange {
                    refreshHighlightActionIfNeeded()
                }
                if didActiveBorderVisibilityChange {
                    previewStateCoordinator.scheduleActiveFocusedWindowRefresh()
                }
            }
        }
        .background {
            SelectionReader(selection: previewStateCoordinator.selection) { currIndex in
                Color.clear
                    .onChange(of: currIndex) { _ in
                        refreshHighlightActionIfNeeded()
                    }
            }
        }
        .onChange(of: previewStateCoordinator.selectionInputSource) { _ in
            if previewStateCoordinator.selectionInputSource == .keyboard {
                edgeScrollRequest = nil
            }
            refreshHighlightActionIfNeeded()
        }
        .onChange(of: scrolledFromStart) { hasScrolled in
            if !hasScrolled, edgeScrollRequest == .backward {
                edgeScrollRequest = nil
            }
        }
        .onChange(of: scrolledToEnd) { reachedEnd in
            if reachedEnd, edgeScrollRequest == .forward {
                edgeScrollRequest = nil
            }
        }
        .onChange(of: edgeAutoScrollEnabled) { isEnabled in
            if !isEnabled {
                edgeScrollRequest = nil
            }
        }
        .onChange(of: usesCompactRows) { _ in
            refreshHighlightActionIfNeeded()
        }
        .onChange(of: enableHoverActionsInCompactMode) { _ in
            refreshHighlightActionIfNeeded()
        }
        .onChange(of: hasScreenRecordingPermission) { _ in
            refreshHighlightActionIfNeeded()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            previewStateCoordinator.scheduleActiveFocusedWindowRefresh()
        }
    }

    @ViewBuilder
    private func windowGridContent() -> some View {
        let calculatedMaxDimension = previewStateCoordinator.dimensionState.overallMaxPreviewDimension
        let calculatedDimensionsMap = previewStateCoordinator.dimensionState.windowDimensionsMap
        let gridFlow = GridFlow.resolve(
            compact: usesCompactRows,
            windowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
            dockPosition: dockPosition
        )
        let scrollAxis: Axis.Set = gridFlow.scrollsVertically ? .vertical : .horizontal

        buildFlowStack(
            gridFlow: gridFlow,
            currentMaxDimensionForPreviews: calculatedMaxDimension,
            currentDimensionsMapForPreviews: calculatedDimensionsMap
        )
        .fadeOnEdges(
            axis: scrollAxis == .horizontal ? .horizontal : .vertical,
            fadeLength: 20,
            disableLeading: dynamicFadeEnabled && !scrolledFromStart,
            disableTrailing: scrolledToEnd
        )
        .padding(.top, (!previewStateCoordinator.windowSwitcherActive && effectiveAppNameStyle == .default && effectiveShowAppName) ? PreviewHeaderLayout.contentReservation(for: .default) : 0)
        .padding(.bottom, showsSelectionSummary && previewStateCoordinator.selectionSummaryStyle == .default ? PreviewHeaderLayout.contentReservation(for: .default) : 0)
        .clipShape(RoundedRectangle(cornerRadius: radii.container, style: .continuous).inset(by: 1))
        .overlay(alignment: PreviewHeaderLayout.alignment(for: effectiveAppNameStyle, edge: .top)) {
            hoverTitleBaseView(labelSize: measureString(appName, fontSize: 14))
        }
        .overlay(alignment: PreviewHeaderLayout.alignment(for: previewStateCoordinator.selectionSummaryStyle, edge: .bottom)) {
            if showsSelectionSummary { selectionSummary.transition(.opacity) }
        }
        .overlay {
            SelectionReader(selection: previewStateCoordinator.selection) { currIndex in
                Group {
                    if dockPosition == .cmdTab,
                       Defaults[.enableCmdTabEnhancements],
                       !Defaults[.hasSeenCmdTabFocusHint],
                       !previewStateCoordinator.windowSwitcherActive,
                       currIndex < 0
                    {
                        CmdTabFocusFullOverlayView()
                            .transition(.opacity)
                            .allowsHitTesting(false)
                            .clipShape(RoundedRectangle(cornerRadius: radii.container, style: .continuous))
                    }
                }
                .onAppear { recordCmdTabFocusHintUsage(at: currIndex) }
                .onChange(of: currIndex) { recordCmdTabFocusHintUsage(at: $0) }
            }
        }
        .measure($edgeScrollHoverSize)
        .onContinuousHover { phase in
            guard edgeAutoScrollEnabled else {
                edgeScrollRequest = nil
                return
            }

            switch phase {
            case let .active(location):
                handleEdgeScrollHover(at: location, isHorizontal: scrollAxis == .horizontal)
            case .ended:
                edgeScrollRequest = nil
            }
        }
        .onDisappear { edgeScrollRequest = nil }
    }

    private func recordCmdTabFocusHintUsage(at index: Int) {
        guard !mockPreviewActive, dockPosition == .cmdTab,
              Defaults[.enableCmdTabEnhancements], !previewStateCoordinator.windowSwitcherActive,
              previewStateCoordinator.windows.indices.contains(index),
              !Defaults[.hasSeenCmdTabFocusHint]
        else { return }
        Defaults[.hasSeenCmdTabFocusHint] = true
    }

    private func handleWindowDrop(at location: CGPoint, for window: WindowInfo, token: UUID) {
        let displays = WindowSpaces.managedDisplays()
        guard !window.isWindowlessApp,
              let currentScreen = location.screen(),
              let targetSpaceID = WindowSpaces.currentManagedSpaceID(mouseLocation: location),
              let destination = WindowSpaces.destination(forSpaceID: targetSpaceID, in: displays),
              destination.space.kind == .desktop,
              WindowSpaces.validateMoveSource(window, in: displays) == nil
        else {
            NSSound.beep()
            cancelPreviewDrag(token: token)
            return
        }

        let finishPlacement: @MainActor () -> Void = {
            guard dragSession?.token == token else { return }
            guard revealWindowForDragPlacement(window),
                  WindowUtil.placeWindowCentered(window, at: location, on: currentScreen) != nil
            else {
                NSSound.beep()
                cancelPreviewDrag(token: token)
                return
            }

            dragCompletionTask?.cancel()
            dragCompletionTask = Task { @MainActor in
                let activated = await window.bringToFrontConfirmed()
                guard !Task.isCancelled, dragSession?.token == token else { return }
                dragCompletionTask = nil
                cancelPreviewDrag(token: token)
                if activated { onWindowTap?() }
                else { NSSound.beep() }
            }
        }

        if WindowSpaces.sourceSpaceIDs(for: window).contains(targetSpaceID) {
            finishPlacement()
            return
        }

        WindowUtil.moveWindowConfirmed(window, toManagedSpace: targetSpaceID) { success in
            guard dragSession?.token == token else { return }
            guard success else {
                NSSound.beep()
                cancelPreviewDrag(token: token)
                return
            }
            finishPlacement()
        }
    }

    private func revealWindowForDragPlacement(_ window: WindowInfo) -> Bool {
        do {
            if window.app.isHidden {
                try window.appAxElement.setAttribute(kAXHiddenAttribute, false)
                WindowUtil.updateCachedWindowState(window, isHidden: false)
            }
            if window.isMinimized || (try? window.axElement.isMinimized()) == true {
                try window.axElement.setAttribute(kAXMinimizedAttribute, false)
                WindowUtil.updateCachedWindowState(window, isMinimized: false)
            }
            return true
        } catch {
            DebugLogger.log(
                "WindowPreviewHoverContainer.revealWindowForDragPlacement",
                details: "Failed to reveal window \(window.id): \(error)"
            )
            return false
        }
    }

    private func beginPreviewDrag(for window: WindowInfo, at location: CGPoint) {
        guard dragSession == nil, !mockPreviewActive, !window.isWindowlessApp else { return }
        let checked = previewStateCoordinator.checkedActionTargets(for: window) ?? []
        let windows = checked.count > 1 ? checked : [window]
        let session = PreviewDragSession(
            identity: PreviewWindowIdentity(window),
            window: window,
            targets: windows.map {
                PreviewDragTarget(window: $0, originalFrame: $0.frame)
            },
            draggedIdentities: Set(windows.map(PreviewWindowIdentity.init))
        )
        dragSession = session
        cancelDockHighlightAction()
        isDragging = true
        dragPoints.removeAll(keepingCapacity: true)
        lastShakeCheck = .distantPast
        let logicalWindowSize = (try? window.axElement.size()) ?? window.frame.size
        DragPreviewCoordinator.shared.startDragging(
            image: window.image,
            fallbackIcon: window.app.icon,
            logicalWindowSize: logicalWindowSize,
            group: session.targets.map(\.window),
            at: location,
            token: session.token
        )
    }

    private func updatePreviewDrag(
        for window: WindowInfo,
        cursorLocation: CGPoint,
        shakeLocation: CGPoint
    ) {
        if dragSession == nil {
            beginPreviewDrag(for: window, at: cursorLocation)
        }

        guard var session = dragSession,
              session.identity == PreviewWindowIdentity(window),
              DragPreviewCoordinator.shared.isActive(token: session.token),
              !session.consumedByShake
        else { return }

        if !previewStateCoordinator.windowSwitcherActive,
           aeroShakeAction != .none,
           checkForShakeGesture(currentPoint: shakeLocation)
        {
            session.consumedByShake = true
            dragSession = session
            previewStateCoordinator.setPreviewDragTarget(nil)
            isDragging = false
            DragPreviewCoordinator.shared.endDragging(token: session.token)

            switch aeroShakeAction {
            case .all:
                minimizeAllWindows()
            case .except:
                if session.targets.count > 1 {
                    _ = WindowUtil.minimizeAllWindowsExcept(session.targets.map(\.window))
                    onWindowTap?()
                } else { minimizeAllWindows(session.window) }
            case .none:
                break
            }
            return
        }

        let target = Defaults[.enableWindowDragTiling]
            ? previewStateCoordinator.dragTargetGrid?.windowForDrop(at: cursorLocation) : nil
        if let target, !target.isWindowlessApp, !target.app.isTerminated, target.isFullscreen != true,
           !session.draggedIdentities.contains(PreviewWindowIdentity(target))
        {
            previewStateCoordinator.setPreviewDragTarget(PreviewWindowIdentity(target))
        } else { previewStateCoordinator.setPreviewDragTarget(nil) }
        DragPreviewCoordinator.shared.updatePreviewPosition(to: cursorLocation)
    }

    private func finishPreviewDrag(for window: WindowInfo, at location: CGPoint) {
        guard var session = dragSession,
              session.identity == PreviewWindowIdentity(window)
        else { return }

        DragPreviewCoordinator.shared.endDragging(token: session.token)
        previewStateCoordinator.setPreviewDragTarget(nil)
        if !session.consumedByShake,
           !window.app.isTerminated
        {
            session.isCompletingDrop = true
            dragSession = session
            edgeScrollRequest = nil
            if Defaults[.enableWindowDragTiling],
               let target = previewStateCoordinator.dragTargetGrid?.windowForDrop(at: location)
            {
                completeTileDrop(session, on: target)
            } else if session.targets.count > 1 {
                completeGroupDrop(session, at: location)
            } else { handleWindowDrop(at: location, for: session.window, token: session.token) }
        } else {
            cancelPreviewDrag(token: session.token)
        }
    }

    private func completeTileDrop(_ session: PreviewDragSession, on target: WindowInfo) {
        let identity = PreviewWindowIdentity(target)
        let checked = previewStateCoordinator.checkedActionTargets(for: target) ?? []
        let targetGroup = checked.contains(where: { PreviewWindowIdentity($0) == identity }) ? checked : [target]
        let dragged = session.targets.map(\.window)
        let order = PreviewDragLayout.tilingOrder(target: identity, targetGroup: targetGroup.map(PreviewWindowIdentity.init),
                                                  dragged: dragged.map(PreviewWindowIdentity.init))
        guard !order.isEmpty else { cancelPreviewDrag(token: session.token); return }

        let displays = WindowSpaces.managedDisplays()
        let memberships = WindowSpaces.sourceSpaceIDs(for: target)
        let desktops = displays.flatMap(\.spaces).filter { $0.kind == .desktop && memberships.contains($0.id) }
        guard !target.app.isTerminated, WindowSpaces.validateMoveSource(target, in: displays) == nil,
              desktops.count == 1,
              let destination = WindowSpaces.destination(forSpaceID: desktops[0].id, in: displays)
        else { NSSound.beep(); cancelPreviewDrag(token: session.token); return }
        // Shared Spaces identify a Desktop, not the target window's physical display.
        let targetScreen = NSScreen.screensHaveSeparateSpaces
            ? WindowSpaces.screen(forDisplayIdentifier: destination.display.identifier)
            : target.screenIdentifier.flatMap { NSScreen.findScreen(byIdentifier: $0) }
            ?? (NSScreen.screens.count == 1 ? NSScreen.screens.first : nil)
        guard let targetScreen else { NSSound.beep(); cancelPreviewDrag(token: session.token); return }

        let byIdentity = Dictionary((targetGroup + dragged).map { (PreviewWindowIdentity($0), $0) }, uniquingKeysWith: { first, _ in first })
        let windows = order.compactMap { byIdentity[$0] }
        dragCompletionTask = Task { @MainActor in
            let result = await WindowUtil.tilePreviewWindows(windows, direction: .neutral, bringToFront: true,
                                                             destination: destination, on: targetScreen,
                                                             isRequestActive: { dragSession?.token == session.token })
            guard !Task.isCancelled, dragSession?.token == session.token else { return }
            dragCompletionTask = nil
            cancelPreviewDrag(token: session.token)
            if !result.failed.isEmpty {
                DebugLogger.log("PreviewTileDrop", details: "Failed: " + result.failed.map { "\($0.pid):\($0.windowID)" }.joined(separator: ", "))
                NSSound.beep()
            } else if !result.succeeded.isEmpty { onWindowTap?() }
        }
    }

    private func completeGroupDrop(_ session: PreviewDragSession, at location: CGPoint) {
        let displays = WindowSpaces.managedDisplays()
        guard let screen = location.screen(),
              let spaceID = WindowSpaces.currentManagedSpaceID(mouseLocation: location),
              let destination = WindowSpaces.destination(forSpaceID: spaceID, in: displays),
              destination.space.kind == .desktop
        else { NSSound.beep(); cancelPreviewDrag(token: session.token); return }

        dragCompletionTask = Task { @MainActor in
            let result = await WindowUtil.placeDraggedWindows(session.targets, at: location, on: screen,
                                                              destination: destination,
                                                              isRequestActive: { dragSession?.token == session.token })
            guard !Task.isCancelled, dragSession?.token == session.token else { return }
            dragCompletionTask = nil
            cancelPreviewDrag(token: session.token)
            if !result.failed.isEmpty {
                DebugLogger.log("PreviewGroupDrop", details: "Failed: " + result.failed.map { "\($0.pid):\($0.windowID)" }.joined(separator: ", "))
                NSSound.beep()
            } else if !result.succeeded.isEmpty { onWindowTap?() }
        }
    }

    private func previewDragGesture(for window: WindowInfo) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                updatePreviewDrag(
                    for: window,
                    cursorLocation: NSEvent.mouseLocation,
                    shakeLocation: value.location
                )
            }
            .onEnded { _ in
                finishPreviewDrag(for: window, at: NSEvent.mouseLocation)
            }
    }

    private func cancelPreviewDrag(token: UUID? = nil) {
        guard let session = dragSession else {
            previewStateCoordinator.setPreviewDragTarget(nil)
            dragCompletionTask?.cancel()
            dragCompletionTask = nil
            isDragging = false
            dragPoints.removeAll(keepingCapacity: true)
            return
        }
        let token = token ?? session.token
        guard token == session.token else { return }

        previewStateCoordinator.setPreviewDragTarget(nil)
        dragCompletionTask?.cancel()
        dragCompletionTask = nil
        DragPreviewCoordinator.shared.endDragging(token: token)
        dragSession = nil
        isDragging = false
        dragPoints.removeAll(keepingCapacity: true)
    }

    @ViewBuilder
    private func hoverTitleBaseView(labelSize: CGSize) -> some View {
        if !previewStateCoordinator.windowSwitcherActive, effectiveShouldShowHeader {
            PreviewHeader(style: effectiveAppNameStyle, edge: .top,
                          backgroundAppearance: backgroundAppearance, onHover: handleAppHeaderHover)
            {
                HStack(spacing: PreviewHeaderLayout.labelSpacing) {
                    if let appIcon {
                        Image(nsImage: appIcon)
                            .resizable()
                            .scaledToFit()
                            .zIndex(1)
                            .frame(width: PreviewHeaderLayout.minimumHeight, height: PreviewHeaderLayout.minimumHeight)
                    } else {
                        ProgressView().frame(width: PreviewHeaderLayout.minimumHeight, height: PreviewHeaderLayout.minimumHeight)
                    }
                    if !effectiveShowAppIconOnly { hoverTitleLabelView(labelSize: labelSize) }
                }
            } actions: {
                Group {
                    update(updateAvailable && !mockPreviewActive)
                    massOperations(hoveringAppIcon && !updateAvailable && showMassActionButtons)
                }
            }
        }
    }

    @ViewBuilder
    func update(_ shouldDisplay: Bool) -> some View {
        if shouldDisplay {
            Button {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.updater.checkForUpdates()
                }
            } label: {
                Label("Update available", systemImage: "arrow.down.circle.fill")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        CustomizableFluidGradientView()
                            .opacity(effectiveAppNameStyle == .shadowed ? 1 : 0.25)
                    )
                    .clipShape(Capsule())
                    .shadow(radius: 2)
                    .overlay(
                        Capsule()
                            .stroke(.secondary.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    func massOperations(_ shouldDisplay: Bool) -> some View {
        if shouldDisplay, hasAppHeaderWindowTargets {
            Group {
                Button {
                    handleAppHeaderAction(.closeAllWindows)
                } label: {
                    Text("Close All")
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(AccentButtonStyle(small: true))

                Button {
                    handleAppHeaderAction(.minimizeAllWindows)
                } label: {
                    Text("Minimize All")
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(AccentButtonStyle(small: true))
            }
        }
    }

    private var hasAppHeaderWindowTargets: Bool {
        previewStateCoordinator.windows.contains { !$0.isWindowlessApp && !$0.app.isTerminated }
    }

    @ViewBuilder
    private func hoverTitleLabelView(labelSize: CGSize) -> some View {
        let trimmedAppName = appName.trimmingCharacters(in: .whitespaces)
        let baseText = Text(trimmedAppName)

        let rainbowGradientColors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
        let rainbowGradientHighlights: [Color] = [.white.opacity(0.45), .yellow.opacity(0.35), .pink.opacity(0.4)]
        let rainbowGradientSpeed: CGFloat = 0.65
        let defaultBlur: CGFloat = 0.5

        Group {
            switch effectiveAppNameStyle {
            case .shadowed:
                if trimmedAppName == "DockDoor" {
                    FluidGradient(
                        blobs: rainbowGradientColors,
                        highlights: rainbowGradientHighlights,
                        speed: rainbowGradientSpeed,
                        blur: defaultBlur
                    )
                    .frame(width: labelSize.width, height: labelSize.height)
                    .mask(baseText)
                    .fontWeight(.medium)
                    .padding(.leading, 4)
                    .modifier(PreviewHeaderTextShadow(labelWidth: labelSize.width))
                } else {
                    baseText
                        .foregroundStyle(Color.primary)
                        .modifier(PreviewHeaderTextShadow(labelWidth: labelSize.width))
                }
            case .default, .popover:
                if trimmedAppName == "DockDoor" {
                    FluidGradient(
                        blobs: rainbowGradientColors,
                        highlights: rainbowGradientHighlights,
                        speed: rainbowGradientSpeed,
                        blur: defaultBlur
                    )
                    .frame(width: labelSize.width, height: labelSize.height)
                    .mask(baseText)
                } else {
                    baseText
                        .foregroundStyle(Color.primary)
                }
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func embeddedContentView() -> some View {
        switch embeddedContentType {
        case let .media(bundleIdentifier):
            MediaControlsView(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                dockPosition: dockPosition,
                bestGuessMonitor: bestGuessMonitor,
                dockItemElement: dockItemElement,
                isEmbeddedMode: true,
                idealWidth: embeddedContentWidth
            )
            .pinnable(appName: appName, bundleIdentifier: bundleIdentifier, type: .media)
        case let .calendar(bundleIdentifier):
            CalendarView(
                appName: appName,
                bundleIdentifier: bundleIdentifier,
                dockPosition: dockPosition,
                bestGuessMonitor: bestGuessMonitor,
                dockItemElement: dockItemElement,
                isEmbeddedMode: true,
                idealWidth: embeddedContentWidth
            )
            .pinnable(appName: appName, bundleIdentifier: bundleIdentifier, type: .calendar)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func buildFlowStack(
        gridFlow: GridFlow,
        currentMaxDimensionForPreviews: CGPoint,
        currentDimensionsMapForPreviews: [Int: WindowDimensions]
    ) -> some View {
        let cachedFilteredIndices = filteredWindowIndices()
        let appearance = appearanceOverride ?? cachedAppearance ?? PreviewAppearanceSettings.resolve(
            windowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
            dockPosition: dockPosition
        )
        let currentSpaceNumbers: Set<Int> = if !appearance.showSpaceNumberIndicator ||
            !appearance.highlightCurrentSpaceNumberIndicator
        {
            []
        } else if mockPreviewActive {
            [1]
        } else {
            Set(currentActiveSpaceIDs().compactMap { SpaceNumberResolver.number(for: $0) })
        }
        if shouldShowNoResultsView() {
            noResultsView()
                .globalPadding(20)
                .padding(2)
        } else if previewStateCoordinator.windowSwitcherActive,
                  previewStateCoordinator.windows.isEmpty,
                  embeddedContentType == .none
        {
            noEligibleWindowsView()
                .globalPadding(20)
                .padding(2)
        } else {
            let lines: [[FlowItem]] = usesCompactRows
                ? createFlowItems(filteredIndices: cachedFilteredIndices).map { [$0] }
                : createChunkedItems(filteredIndices: cachedFilteredIndices, gridFlow: gridFlow)
            let onlyWindowlessDockLikeRows = !appearance.showFullSizeWindowlessPreviews &&
                !cachedFilteredIndices.isEmpty &&
                cachedFilteredIndices.allSatisfy { index in
                    index < previewStateCoordinator.windows.count && previewStateCoordinator.windows[index].isWindowlessApp
                }
            let metrics = PreviewLayoutMetrics.resolve(
                compact: usesCompactRows,
                onlyWindowlessDockLikeRows: onlyWindowlessDockLikeRows,
                paddingMultiplier: appearance.globalPaddingMultiplier
            )
            let layout = CardGridScrollView.Layout(
                lines: lines,
                laysOutItemsInRows: gridFlow.laysOutItemsInRows,
                scrollsVertically: gridFlow.scrollsVertically,
                centerLines: previewStateCoordinator.windowSwitcherActive && appearance.allowDynamicImageSizing && !usesCompactRows,
                spacing: metrics.itemSpacing,
                inset: metrics.contentInset,
                dimensions: currentDimensionsMapForPreviews,
                appearance: appearance
            )
            CardGridScrollView(
                layout: layout,
                contentKey: previewStateCoordinator.windows.map(\.viewSnapshot),
                focusedWindowID: previewStateCoordinator.focusedWindowID,
                coordinator: previewStateCoordinator,
                scrolledFromStart: $scrolledFromStart,
                scrolledToEnd: $scrolledToEnd,
                isInteractive: !mockPreviewActive,
                edgeScrollRequest: edgeScrollRequest,
                edgeScrollSpeed: edgeAutoScrollSpeed,
                makeCard: { item in
                    AnyView(buildFlowItem(
                        item: item,
                        laysOutItemsInRows: gridFlow.laysOutItemsInRows,
                        currentMaxDimensionForPreviews: currentMaxDimensionForPreviews,
                        currentDimensionsMapForPreviews: currentDimensionsMapForPreviews,
                        filteredIndices: cachedFilteredIndices,
                        appearance: appearance,
                        currentSpaceNumbers: currentSpaceNumbers
                    ))
                }
            )
            .padding(2)
        }
    }

    private func handleEdgeScrollHover(at location: CGPoint, isHorizontal: Bool) {
        guard previewStateCoordinator.registerMouseMovementSinceOpen() else {
            edgeScrollRequest = nil
            return
        }

        let edgeSize: CGFloat = 50
        let width = edgeScrollHoverSize.width
        let summaryHeight = showsSelectionSummary && previewStateCoordinator.selectionSummaryStyle == .default
            ? PreviewHeaderLayout.contentReservation(for: .default) : 0
        let height = edgeScrollHoverSize.height - summaryHeight

        guard width > 0, height > 0, location.y <= height else {
            edgeScrollRequest = nil
            return
        }

        if isHorizontal {
            let toolbarExclusion: CGFloat = 46
            let appearance = appearanceOverride ?? cachedAppearance ?? PreviewAppearanceSettings.resolve(
                windowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
                dockPosition: dockPosition
            )
            let topExclusion = appearance.controlPosition.showsOnTop ? toolbarExclusion : 0
            let bottomExclusion = appearance.controlPosition.showsOnBottom ? toolbarExclusion : 0

            guard location.y >= topExclusion, location.y <= height - bottomExclusion else {
                edgeScrollRequest = nil
                return
            }

            let request: CardGridScrollView.EdgeScrollRequest? = if location.x <= edgeSize, scrolledFromStart {
                .backward
            } else if location.x >= width - edgeSize, !scrolledToEnd {
                .forward
            } else {
                nil
            }
            updateEdgeScrollRequest(request)
        } else {
            let request: CardGridScrollView.EdgeScrollRequest? = if location.y <= edgeSize, scrolledFromStart {
                .backward
            } else if location.y >= height - edgeSize, !scrolledToEnd {
                .forward
            } else {
                nil
            }
            updateEdgeScrollRequest(request)
        }
    }

    private func updateEdgeScrollRequest(_ request: CardGridScrollView.EdgeScrollRequest?) {
        guard request != edgeScrollRequest else { return }

        if request != nil, edgeScrollRequest == nil {
            previewStateCoordinator.setIndex(to: -1, shouldScroll: false, source: .mouse)
            refreshHighlightActionIfNeeded()
        }

        edgeScrollRequest = request
    }

    private var edgeAutoScrollEnabled: Bool {
        if previewStateCoordinator.windowSwitcherActive {
            return enableWindowSwitcherEdgeAutoScroll
        }
        return dockPosition == .cmdTab ? enableCmdTabEdgeAutoScroll : enableDockPreviewEdgeAutoScroll
    }

    private var edgeAutoScrollSpeed: CGFloat {
        if previewStateCoordinator.windowSwitcherActive {
            return mouseHoverAutoScrollSpeed
        }
        return dockPosition == .cmdTab ? cmdTabEdgeAutoScrollSpeed : dockPreviewEdgeAutoScrollSpeed
    }

    private func loadAppIcon() {
        guard let app = previewStateCoordinator.windows.first?.app, let bundleID = app.bundleIdentifier else { return }
        if let icon = SharedHoverUtils.loadAppIcon(for: bundleID) {
            DispatchQueue.main.async {
                if appIcon != icon { appIcon = icon }
            }
        } else if appIcon != nil {
            DispatchQueue.main.async { appIcon = nil }
        }
    }

    private func activateApp() {
        guard let app = previewStateCoordinator.windows.first?.app else { return }
        if app.isHidden { app.unhide() }
        app.activate(options: [.activateIgnoringOtherApps])
        previewStateCoordinator.scheduleActiveFocusedWindowRefresh()
    }

    private func closeAllWindows() {
        onWindowTap?()
        guard let app = previewStateCoordinator.windows.first?.app else { return }
        _ = WindowUtil.closeAllWindows(for: app, preferredWindows: previewStateCoordinator.windows)
    }

    private func handleAppHeaderAction(_ action: WindowAction) {
        guard hasAppHeaderWindowTargets else { return }
        let selectedIndex = previewStateCoordinator.currIndex
        let targetIndex = if previewStateCoordinator.windows.indices.contains(selectedIndex) {
            selectedIndex
        } else {
            0
        }
        handleWindowAction(action, at: targetIndex)
    }

    private func minimizeAllWindows(
        _ except: WindowInfo? = nil,
        wasAppActiveBeforeClick: Bool? = nil,
        preferSharedToggle: Bool = false
    ) {
        onWindowTap?()
        let originalWindows = previewStateCoordinator.windows

        guard !originalWindows.isEmpty else { return }
        guard let app = originalWindows.first?.app else { return }

        func runSharedMinimizeAll(with preferredWindows: [WindowInfo]) {
            guard !preferredWindows.isEmpty else {
                previewStateCoordinator.scheduleVisibilityStateSync(processIdentifier: app.processIdentifier)
                return
            }
            let changedCount = WindowUtil.minimizeAllWindows(for: app, preferredWindows: preferredWindows)
            if changedCount == 0 {
                previewStateCoordinator.scheduleVisibilityStateSync(processIdentifier: app.processIdentifier)
            }
        }

        if let except {
            guard let keptWindow = originalWindows.first(where: { $0.id == except.id }) else {
                except.bringToFront()
                return
            }

            _ = WindowUtil.minimizeAllWindowsExcept(keptWindow)

            previewStateCoordinator.setWindows([keptWindow], dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor, isMockPreviewActive: mockPreviewActive)
            keptWindow.bringToFront()
            return
        }

        if let wasAppActiveBeforeClick {
            if wasAppActiveBeforeClick {
                switch Defaults[.dockClickAction] {
                case .hide:
                    if WindowUtil.hasOnlyFullscreenWindows(for: app, preferredWindows: originalWindows) {
                        previewStateCoordinator.scheduleVisibilityStateSync(processIdentifier: app.processIdentifier)
                        return
                    }
                    app.hide()
                    previewStateCoordinator.setWindows([], dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor, isMockPreviewActive: mockPreviewActive)
                case .minimize:
                    let preferredToMinimize = originalWindows.filter {
                        !$0.isWindowlessApp &&
                            !$0.isMinimized &&
                            (try? $0.axElement.isFullscreen()) != true
                    }
                    runSharedMinimizeAll(with: preferredToMinimize)
                    previewStateCoordinator.setWindows([], dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor, isMockPreviewActive: mockPreviewActive)
                case .cycleWindows:
                    break
                }
            } else {
                if WindowUtil.hasOnlyFullscreenWindows(for: app, preferredWindows: originalWindows) {
                    previewStateCoordinator.scheduleVisibilityStateSync(processIdentifier: app.processIdentifier)
                    return
                }
                app.activate()
                app.unhide()
                let preferredToRestore = originalWindows.filter {
                    !$0.isWindowlessApp &&
                        $0.isMinimized &&
                        (try? $0.axElement.isFullscreen()) != true
                }
                runSharedMinimizeAll(with: preferredToRestore)
            }
        } else {
            if preferSharedToggle {
                runSharedMinimizeAll(with: originalWindows)
            } else {
                _ = WindowUtil.minimizeAllWindowsGlobally()
            }
            previewStateCoordinator.setWindows([], dockPosition: dockPosition, bestGuessMonitor: bestGuessMonitor, isMockPreviewActive: mockPreviewActive)
        }
    }

    private func handleWindowAction(_ action: WindowAction, at index: Int) {
        if action == .selectAllWindows {
            if !mockPreviewActive { previewStateCoordinator.selectAllDisplayedWindows() }
            return
        }
        guard index < previewStateCoordinator.windows.count else { return }
        let window = previewStateCoordinator.windows[index]
        if action == .toggleWindowSelection {
            if !mockPreviewActive { previewStateCoordinator.toggleCheckedWindow(window) }
            return
        }
        let willQuitOnClose = action == .close &&
            !window.isWindowlessApp &&
            WindowUtil.shouldQuitAppOnWindowClose(processIdentifier: window.app.processIdentifier)
        let appPID = window.app.processIdentifier
        let existingAppWindowIDs = Set(
            previewStateCoordinator.windows
                .filter { $0.app.processIdentifier == appPID && !$0.isWindowlessApp }
                .map(\.id)
        )
        let hiddenStateBeforeAction: Bool? = if action == .hide {
            (try? window.appAxElement.attribute(kAXHiddenAttribute, Bool.self)) ?? window.isHidden
        } else {
            nil
        }
        var actionStateWindow = window
        if let hiddenStateBeforeAction {
            actionStateWindow.isHidden = hiddenStateBeforeAction
        }
        let category = action.postActionCategory(
            for: actionStateWindow,
            preferredWindows: previewStateCoordinator.windows
        )
        let keepPreviewsOpen = SharedPreviewWindowCoordinator.activeInstance?.selectionKeepsPreviewsOpen == true || (category?.keepPreviewsOpen ?? true)
        let closeAfterSuccess = action.closePreviewsOnlyAfterSuccess(
            for: actionStateWindow,
            category: category
        )
        let shouldClosePreviews = !keepPreviewsOpen
        let shouldForegroundMoveResize = Defaults[.moveResizeBringToForeground] &&
            category == .movingAndResizing
        let forceImmediateCloseForFullscreenTransitionPreAction = action.shouldForcePreviewCloseForFullscreenTransition(
            on: actionStateWindow,
            preferredWindows: previewStateCoordinator.windows
        )
        let skipToggleFullscreenRefresh = action == .toggleFullScreen &&
            (keepPreviewsOpen || forceImmediateCloseForFullscreenTransitionPreAction)
        let shouldRunInPlaceRefresh = action.shouldScheduleAppRefresh &&
            !skipToggleFullscreenRefresh
        let expectedFullscreenState: Bool? = if action == .toggleFullScreen {
            (try? window.axElement.isFullscreen()).map(!)
        } else {
            nil
        }
        let expectedMinimizedState: Bool? = if action == .minimize {
            !window.isMinimized
        } else {
            nil
        }
        let expectedHiddenState = hiddenStateBeforeAction.map { !$0 }
        let expectedMinimizeAllState: Bool? = if action == .minimizeAllWindows {
            switch category {
            case .hiding:
                true
            case .unhiding:
                false
            default:
                nil
            }
        } else {
            nil
        }

        let activationDismissalSuppressionToken: UUID? = if action == .hide,
                                                            keepPreviewsOpen,
                                                            !forceImmediateCloseForFullscreenTransitionPreAction,
                                                            let hiddenStateBeforeAction
        {
            SharedPreviewWindowCoordinator.activeInstance?.suppressNextActionDrivenActivationDismissal(
                for: window.app,
                wasHidden: hiddenStateBeforeAction
            )
        } else {
            nil
        }

        if action.shouldScheduleDockReconciliation, !skipToggleFullscreenRefresh {
            scheduleDockActionReconciliationIfNeeded(for: window.app)
        }

        let result = action.perform(
            on: actionStateWindow,
            keepPreviewOnQuit: false,
            preferredWindows: previewStateCoordinator.windows,
            hiddenStateBeforeAction: hiddenStateBeforeAction
        )
        if case .noChange = result {
            SharedPreviewWindowCoordinator.activeInstance?.cancelActionDrivenActivationDismissalSuppression(
                token: activationDismissalSuppressionToken
            )
        }
        previewStateCoordinator.scheduleActiveFocusedWindowRefresh()

        var actionConfirmedSuccess = false
        switch result {
        case .dismissed:
            actionConfirmedSuccess = !action.requiresDeferredSuccessWatcher || !closeAfterSuccess || !shouldClosePreviews
        case let .windowUpdated(updatedWindow):
            actionConfirmedSuccess = true
            if action == .hide {
                previewStateCoordinator.updateHiddenStateForApp(
                    processIdentifier: updatedWindow.app.processIdentifier,
                    isHidden: updatedWindow.isHidden
                )
            } else {
                previewStateCoordinator.updateWindow(at: index, with: updatedWindow)
            }
        case .noChange:
            break
        }

        if action == .minimize || action == .hide || action == .minimizeAllWindows {
            previewStateCoordinator.scheduleVisibilityStateSync(processIdentifier: window.app.processIdentifier)
        }

        if shouldRunInPlaceRefresh {
            scheduleInPlaceActionRefresh(
                for: window.app,
                fallbackWindow: window,
                forceImageRefresh: action == .openNewWindow,
                previousWindowIDs: action == .openNewWindow ? existingAppWindowIDs : nil,
                sourceWindowID: action == .openNewWindow ? window.id : nil
            )
        }

        if shouldForegroundMoveResize,
           actionConfirmedSuccess,
           WindowUtil.canBringWindowToFrontWithoutSpaceSwitch(window)
        {
            window.bringToFront()
        }

        if action.shouldForcePreviewCloseAfterAction(
            predictedTransition: forceImmediateCloseForFullscreenTransitionPreAction,
            hiddenStateBeforeAction: hiddenStateBeforeAction,
            result: result
        ) {
            onWindowTap?()
            return
        }

        guard shouldClosePreviews else { return }

        if action == .close || action == .quit {
            scheduleFailedClosingFocusNotification(
                action: action,
                window: window,
                willQuitOnClose: willQuitOnClose
            )
            onWindowTap?()
            return
        }

        if !closeAfterSuccess {
            if action == .hide, case .noChange = result {
                return
            }
            onWindowTap?()
            return
        }

        if action == .minimize || action == .hide || action == .minimizeAllWindows {
            scheduleVisibilityDismissConfirmation(
                action: action,
                window: window,
                targetMinimizedState: expectedMinimizedState,
                targetHiddenState: expectedHiddenState,
                targetMinimizeAllState: expectedMinimizeAllState
            )
            return
        }

        if actionConfirmedSuccess {
            onWindowTap?()
            return
        }

        switch action {
        case .toggleFullScreen:
            if let expectedFullscreenState {
                scheduleFullscreenDismissConfirmation(
                    window: window,
                    targetFullscreenState: expectedFullscreenState
                )
            }
        case .openNewWindow:
            scheduleNewWindowDismissConfirmation(
                window: window,
                previousWindowIDs: existingAppWindowIDs
            )
        case .close:
            if willQuitOnClose {
                scheduleAppTerminationDismissConfirmation(
                    window: window,
                    sourceAction: .close
                )
            } else if window.isWindowlessApp {
                scheduleCloseAllDismissConfirmation(
                    window: window,
                    sourceAction: .close
                )
            } else {
                scheduleWindowClosureDismissConfirmation(
                    window: window
                )
            }
        case .quit:
            scheduleAppTerminationDismissConfirmation(
                window: window,
                sourceAction: .quit
            )
        case .closeAllWindows:
            scheduleCloseAllDismissConfirmation(
                window: window,
                sourceAction: .closeAllWindows
            )
        default:
            break
        }
    }

    private func scheduleFailedClosingFocusNotification(
        action: WindowAction,
        window: WindowInfo,
        willQuitOnClose: Bool
    ) {
        let app = window.app
        let pid = app.processIdentifier
        let windowID = window.id
        let isWindowless = window.isWindowlessApp

        startDeferredActionWatcher(
            pid: pid,
            action: action,
            purpose: "failed-focus"
        ) {
            var missingWindowConfirmations = 0
            var emptyWindowSetConfirmations = 0

            for delay in WindowAction.deferredConfirmationPollDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard shouldRunDeferredWatchers else { return }

                if action == .quit || willQuitOnClose {
                    if app.isTerminated || NSRunningApplication(processIdentifier: pid) == nil {
                        return
                    }
                    continue
                }

                await WindowUtil.updateNewWindowsForApp(app)
                guard shouldRunDeferredWatchers else { return }

                let cached = WindowUtil.readCachedWindows(for: pid).filter { !$0.isWindowlessApp }
                if isWindowless {
                    if cached.isEmpty {
                        emptyWindowSetConfirmations += 1
                        if emptyWindowSetConfirmations >= 2 {
                            return
                        }
                    } else {
                        emptyWindowSetConfirmations = 0
                    }
                    continue
                }

                let stillExists = cached.contains { $0.id == windowID && $0.app.processIdentifier == pid }
                if !stillExists {
                    missingWindowConfirmations += 1
                    if missingWindowConfirmations >= 2 {
                        return
                    }
                } else {
                    missingWindowConfirmations = 0
                }
            }

            guard shouldRunDeferredWatchers else { return }
            guard let runningApp = NSRunningApplication(processIdentifier: pid), !runningApp.isTerminated else { return }

            runningApp.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])

            let cachedWindows = WindowUtil.readCachedWindows(for: pid).filter { !$0.isWindowlessApp }
            if !isWindowless, let exactMatch = cachedWindows.first(where: { $0.id == windowID }) {
                exactMatch.bringToFront()
            } else if let firstWindow = cachedWindows.first {
                firstWindow.bringToFront()
            }
        }
    }

    private func scheduleVisibilityDismissConfirmation(
        action: WindowAction,
        window: WindowInfo,
        targetMinimizedState: Bool?,
        targetHiddenState: Bool?,
        targetMinimizeAllState: Bool?
    ) {
        let app = window.app
        let pid = app.processIdentifier

        startDeferredActionWatcher(pid: pid, action: action) {
            for delay in WindowAction.deferredConfirmationPollDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard shouldRunDeferredWatchers else { return }
                await WindowUtil.updateNewWindowsForApp(app)
                guard shouldRunDeferredWatchers else { return }

                var confirmed = false
                switch action {
                case .minimize:
                    if let targetMinimizedState {
                        confirmed = (try? window.axElement.isMinimized()) == targetMinimizedState
                    }
                case .hide:
                    if let targetHiddenState {
                        confirmed = app.isHidden == targetHiddenState
                    }
                case .minimizeAllWindows:
                    if let targetMinimizeAllState {
                        let nonFullscreen = WindowUtil.readCachedWindows(for: pid).filter {
                            !$0.isWindowlessApp && (try? $0.axElement.isFullscreen()) != true
                        }
                        if !nonFullscreen.isEmpty {
                            if targetMinimizeAllState {
                                confirmed = nonFullscreen.allSatisfy(\.isMinimized)
                            } else {
                                confirmed = nonFullscreen.allSatisfy { !$0.isMinimized }
                            }
                        }
                    }
                default:
                    break
                }

                if confirmed {
                    onWindowTap?()
                    return
                }
            }
        }
    }

    private func scheduleInPlaceActionRefresh(
        for app: NSRunningApplication,
        fallbackWindow: WindowInfo,
        forceImageRefresh: Bool = false,
        previousWindowIDs: Set<CGWindowID>? = nil,
        sourceWindowID: CGWindowID? = nil
    ) {
        let pid = app.processIdentifier

        startDeferredRefreshTask(pid: pid, purpose: "in-place-action-refresh") {
            for delay in WindowAction.inPlaceRefreshDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }
                await WindowUtil.updateNewWindowsForApp(app)
                guard !Task.isCancelled else { return }
                if forceImageRefresh {
                    await WindowUtil.refreshCachedWindowImagesAfterOpenNewWindow(
                        for: pid,
                        previousWindowIDs: previousWindowIDs ?? [],
                        sourceWindowID: sourceWindowID
                    )
                    guard !Task.isCancelled else { return }
                }

                await MainActor.run {
                    refreshVisibleRowsForApp(app: app, fallbackWindow: fallbackWindow)
                    previewStateCoordinator.scheduleActiveFocusedWindowRefresh()
                }
            }
        }
    }

    private func refreshVisibleRowsForApp(app: NSRunningApplication, fallbackWindow: WindowInfo) {
        let pid = app.processIdentifier
        var replacement = WindowUtil.readCachedWindows(
            for: pid,
            sortedBy: dockPosition == .cmdTab ? .cmdTab : .dockPreview
        )
        let runningApp = NSRunningApplication(processIdentifier: pid)
        let canAddWindowlessEntry = (runningApp?.isTerminated == false)
        let windowlessApp = runningApp ?? app
        if !canAddWindowlessEntry {
            replacement = []
        } else {
            replacement = WindowUtil.collapseNativeTabsIfNeeded(replacement)
        }

        if dockPosition == .cmdTab {
            let hasOtherInstanceRows = previewStateCoordinator.windows.contains {
                !$0.isWindowlessApp &&
                    $0.app.processIdentifier != pid &&
                    $0.app.bundleIdentifier == windowlessApp.bundleIdentifier
            }
            replacement = canAddWindowlessEntry
                ? WindowUtil.cmdTabPreviewWindows(
                    from: replacement,
                    app: windowlessApp,
                    allowWindowlessPlaceholder: !hasOtherInstanceRows
                ) ?? []
                : []
            if replacement.isEmpty, !hasOtherInstanceRows {
                onWindowTap?()
                return
            }
        } else if previewStateCoordinator.windowSwitcherActive {
            if Defaults[.showWindowsFromCurrentSpaceOnlyInSwitcher] {
                replacement = WindowUtil.filterWindowsByCurrentSpace(replacement)
            }
            if Defaults[.showWindowsFromCurrentMonitorOnlyInSwitcher] {
                replacement = WindowUtil.filterWindowsByCurrentMonitor(replacement)
            }
            if !Defaults[.includeHiddenWindowsInSwitcher] {
                replacement = replacement.filter { !$0.isEffectivelyHiddenForUI && !$0.isMinimized }
            }
            if canAddWindowlessEntry, replacement.isEmpty, Defaults[.showWindowlessAppsInSwitcher] {
                replacement = [WindowInfo.windowlessEntry(for: windowlessApp)]
            }
        } else {
            if Defaults[.showWindowsFromCurrentSpaceOnly] {
                replacement = WindowUtil.filterWindowsByCurrentSpace(replacement)
            }
            if Defaults[.showWindowsFromCurrentMonitorOnly] {
                replacement = WindowUtil.filterWindowsByCurrentMonitor(replacement)
            }
            if !Defaults[.includeHiddenWindowsInDockPreview] {
                replacement = replacement.filter { !$0.isEffectivelyHiddenForUI && !$0.isMinimized }
            }
            if canAddWindowlessEntry, replacement.isEmpty, Defaults[.showWindowlessAppsInDockPreview] {
                replacement = [WindowInfo.windowlessEntry(for: windowlessApp)]
            }
        }

        let mergeResult = previewStateCoordinator.mergeRefreshedRowsForPID(
            pid,
            replacementRows: replacement,
            dockPosition: dockPosition,
            bestGuessMonitor: bestGuessMonitor,
            isMockPreviewActive: mockPreviewActive
        )
        if !mergeResult.didPublish,
           previewStateCoordinator.windows.contains(where: { $0.id == fallbackWindow.id && $0.app.processIdentifier == pid })
        {
            previewStateCoordinator.scheduleVisibilityStateSync(processIdentifier: pid)
            previewStateCoordinator.scheduleActiveFocusedWindowRefresh()
        }

        refreshDisplayedFullPreviewIfNeeded(sourceWindows: mergeResult.mergedWindows)
    }

    private func refreshDisplayedFullPreviewIfNeeded(sourceWindows: [WindowInfo]? = nil) {
        guard previewStateCoordinator.fullWindowPreviewActive else { return }
        guard usesHighlightAction, resolvedAppearance.previewHoverAction == .previewFullSize else { return }
        let windows = sourceWindows ?? previewStateCoordinator.windows
        let selectedIndex = previewStateCoordinator.currIndex
        guard selectedIndex >= 0, selectedIndex < windows.count else { return }
        let selectedWindow = windows[selectedIndex]
        guard !selectedWindow.isWindowlessApp else { return }

        SharedPreviewWindowCoordinator.activeInstance?.showWindow(
            appName: selectedWindow.app.localizedName ?? "Unknown",
            windows: [selectedWindow],
            mouseScreen: bestGuessMonitor,
            dockItemElement: nil,
            overrideDelay: true,
            centeredHoverWindowState: .fullWindowPreview
        )
    }

    private func scheduleAppTerminationDismissConfirmation(window: WindowInfo, sourceAction: WindowAction) {
        let pid = window.app.processIdentifier
        let app = window.app

        startDeferredActionWatcher(pid: pid, action: sourceAction) {
            for delay in WindowAction.deferredConfirmationPollDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard shouldRunDeferredWatchers else { return }
                let appStillVisible = previewStateCoordinator.windows.contains { $0.app.processIdentifier == pid }
                if app.isTerminated || NSRunningApplication(processIdentifier: pid) == nil || !appStillVisible {
                    onWindowTap?()
                    return
                }
            }
        }
    }

    private func scheduleWindowClosureDismissConfirmation(window: WindowInfo) {
        let windowID = window.id
        let pid = window.app.processIdentifier
        let app = window.app

        startDeferredActionWatcher(pid: pid, action: .close) {
            for delay in WindowAction.deferredConfirmationPollDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard shouldRunDeferredWatchers else { return }
                await WindowUtil.updateNewWindowsForApp(app)
                guard shouldRunDeferredWatchers else { return }
                let cached = WindowUtil.readCachedWindows(for: pid)
                let stillExists = cached.contains { $0.id == windowID && $0.app.processIdentifier == pid }
                let stillVisible = previewStateCoordinator.windows.contains { $0.id == windowID && $0.app.processIdentifier == pid }
                if !stillExists || !stillVisible {
                    onWindowTap?()
                    return
                }
            }
        }
    }

    private func scheduleCloseAllDismissConfirmation(window: WindowInfo, sourceAction: WindowAction) {
        let pid = window.app.processIdentifier
        let app = window.app

        startDeferredActionWatcher(pid: pid, action: sourceAction) {
            for delay in WindowAction.deferredConfirmationPollDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard shouldRunDeferredWatchers else { return }
                await WindowUtil.updateNewWindowsForApp(app)
                guard shouldRunDeferredWatchers else { return }
                let cached = WindowUtil.readCachedWindows(for: pid).filter { !$0.isWindowlessApp }
                let visibleNonWindowlessCount = previewStateCoordinator.windows.filter { $0.app.processIdentifier == pid && !$0.isWindowlessApp }.count
                if cached.isEmpty || visibleNonWindowlessCount == 0 {
                    onWindowTap?()
                    return
                }
            }
        }
    }

    private func scheduleNewWindowDismissConfirmation(window: WindowInfo, previousWindowIDs: Set<CGWindowID>) {
        let pid = window.app.processIdentifier
        let app = window.app
        let originalWindowID = window.id
        let originalWindowTitle = window.windowName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hadNoTrackedWindowsBefore = previousWindowIDs.isEmpty

        startDeferredActionWatcher(pid: pid, action: .openNewWindow) {
            for delay in WindowAction.deferredConfirmationPollDelays {
                try? await Task.sleep(nanoseconds: delay)
                guard shouldRunDeferredWatchers else { return }
                await WindowUtil.updateNewWindowsForApp(app)
                guard shouldRunDeferredWatchers else { return }
                let cached = WindowUtil.readCachedWindows(for: pid).filter { !$0.isWindowlessApp }
                let currentIDs = Set(cached.map(\.id))
                let hasNewWindow = !currentIDs.subtracting(previousWindowIDs).isEmpty
                let hasUsableWindow = cached.contains { !$0.isMinimized && !$0.isEffectivelyHiddenForUI }
                let currentTitle = cached
                    .first(where: { $0.id == originalWindowID })?
                    .windowName?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let titleChanged = switch (originalWindowTitle, currentTitle) {
                case (nil, nil): false
                case (nil, let current?): !current.isEmpty
                case (let original?, nil): !original.isEmpty
                case let (original?, current?): original != current
                }
                let shouldTreatAsSuccess = hasNewWindow ||
                    titleChanged ||
                    (hadNoTrackedWindowsBefore && hasUsableWindow)

                if shouldTreatAsSuccess {
                    onWindowTap?()
                    return
                }
            }
        }
    }

    private func scheduleFullscreenDismissConfirmation(
        window: WindowInfo,
        targetFullscreenState: Bool
    ) {
        guard !mockPreviewActive else { return }

        let windowID = window.id
        let pid = window.app.processIdentifier

        startDeferredActionWatcher(pid: pid, action: .toggleFullScreen) {
            try? await Task.sleep(nanoseconds: WindowAction.fullscreenConfirmationDelay)
            guard shouldRunDeferredWatchers else { return }
            guard let confirmedFullscreen = try? window.axElement.isFullscreen(),
                  confirmedFullscreen == targetFullscreenState
            else { return }

            let stillVisible = previewStateCoordinator.windows.contains(where: { $0.id == windowID && $0.app.processIdentifier == pid })
            guard stillVisible else {
                return
            }

            onWindowTap?()
        }
    }

    private func scheduleDockActionReconciliationIfNeeded(for app: NSRunningApplication) {
        guard !mockPreviewActive else { return }
        guard !previewStateCoordinator.windowSwitcherActive else { return }
        guard dockPosition != .cmdTab else { return }

        let pid = app.processIdentifier
        startDeferredRefreshTask(pid: pid, purpose: "dock-action-reconciliation") {
            for (index, delay) in WindowAction.reconciliationDelays.enumerated() {
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled else { return }

                await WindowUtil.updateNewWindowsForApp(app)
                guard !Task.isCancelled else { return }

                if index == 1 {
                    await WindowUtil.updateAllWindowsInCurrentSpace()
                    guard !Task.isCancelled else { return }
                }

                await MainActor.run {
                    DockObserver.activeInstance?.processSelectedDockItemChanged()
                }
            }
        }
    }

    private func checkForShakeGesture(currentPoint: CGPoint) -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastShakeCheck) > 0.05 else { return false }
        lastShakeCheck = now

        dragPoints.append(currentPoint)

        if dragPoints.count > 20 {
            dragPoints.removeFirst(dragPoints.count - 20)
        }

        guard dragPoints.count >= 8 else { return false }

        var directionChanges = 0
        var velocities: [(dx: CGFloat, dy: CGFloat)] = []

        for i in 1 ..< dragPoints.count {
            let prev = dragPoints[i - 1]
            let curr = dragPoints[i]
            let dx = curr.x - prev.x
            let dy = curr.y - prev.y
            velocities.append((dx: dx, dy: dy))
        }

        for i in 1 ..< velocities.count {
            let prev = velocities[i - 1]
            let curr = velocities[i]

            let significantX = abs(prev.dx) > 5 && abs(curr.dx) > 5
            let significantY = abs(prev.dy) > 5 && abs(curr.dy) > 5

            if (significantX && prev.dx.sign != curr.dx.sign) ||
                (significantY && prev.dy.sign != curr.dy.sign)
            {
                directionChanges += 1
            }
        }

        var totalDistance: CGFloat = 0
        for i in 1 ..< dragPoints.count {
            let prev = dragPoints[i - 1]
            let curr = dragPoints[i]
            let dx = curr.x - prev.x
            let dy = curr.y - prev.y
            totalDistance += sqrt(dx * dx + dy * dy)
        }

        let isShake = directionChanges >= 4 && totalDistance > 100

        if isShake {
            dragPoints.removeAll()
        }

        return isShake
    }

    private func filteredWindowIndices() -> [Int] {
        previewStateCoordinator.filteredWindowIndices()
    }

    private func createFlowItems(filteredIndices: [Int]) -> [FlowItem] {
        var allItems: [FlowItem] = []

        for index in filteredIndices {
            allItems.append(.window(index))
        }

        if embeddedContentType != .none {
            allItems.append(.embedded)
        }

        return allItems
    }

    private func createChunkedItems(filteredIndices: [Int], gridFlow: GridFlow) -> [[FlowItem]] {
        var itemsToProcess: [FlowItem] = []
        itemsToProcess.reserveCapacity(filteredIndices.count + (embeddedContentType != .none ? 1 : 0))
        for index in filteredIndices {
            itemsToProcess.append(.window(index))
        }
        if embeddedContentType != .none {
            itemsToProcess.append(.embedded)
        }

        let maxColumns = previewStateCoordinator.dimensionState.effectiveGridColumns
        var maxRows = previewStateCoordinator.dimensionState.effectiveGridRows

        guard maxColumns > 0, maxRows > 0 else {
            return itemsToProcess.isEmpty ? [[]] : [itemsToProcess]
        }

        if mockPreviewActive, previewStateCoordinator.windowSwitcherActive {
            maxRows = 1
        }

        let shouldReverse = (dockPosition == .bottom || dockPosition == .right) && !previewStateCoordinator.windowSwitcherActive

        let chunks = WindowPreviewHoverContainer.chunkArray(
            items: itemsToProcess,
            isHorizontal: gridFlow.laysOutItemsInRows,
            maxColumns: maxColumns,
            maxRows: maxRows,
            reverse: shouldReverse,
            fillToLimit: gridFlow.fillsLinesToLimit
        )

        return chunks.isEmpty ? [[]] : chunks
    }

    @ViewBuilder
    private func buildFlowItem(
        item: FlowItem,
        laysOutItemsInRows: Bool,
        currentMaxDimensionForPreviews: CGPoint,
        currentDimensionsMapForPreviews: [Int: WindowDimensions],
        filteredIndices: [Int],
        appearance: PreviewAppearanceSettings,
        currentSpaceNumbers: Set<Int>
    ) -> some View {
        switch item {
        case .embedded:
            let dims = currentDimensionsMapForPreviews[filteredIndices.first ?? 0]
            embeddedContentView()
                .padding(.trailing, usesCompactRows ? -compactEmbeddedContentOverflow : 0)
                .frame(
                    minWidth: usesCompactRows ? nil : (laysOutItemsInRows ? nil : dims?.size.width),
                    maxWidth: usesCompactRows ? appearance.compactModeWidth + compactEmbeddedContentOverflow : nil,
                    minHeight: laysOutItemsInRows ? (usesCompactRows ? nil : dims?.size.height) : nil
                )
                .fixedSize(horizontal: false, vertical: usesCompactRows)
                .id("\(appName)-embedded")
        case let .window(index):
            SelectionReader(selection: previewStateCoordinator.selection) { currIndex in
                windowFlowItem(
                    index: index,
                    currIndex: currIndex,
                    currentDimensionsMapForPreviews: currentDimensionsMapForPreviews,
                    appearance: appearance,
                    currentSpaceNumbers: currentSpaceNumbers
                )
            }
            .id("\(appName)-\(index)-\(previewStateCoordinator.pointerInteractionSessionID)")
        }
    }

    @ViewBuilder
    private func windowFlowItem(
        index: Int,
        currIndex: Int,
        currentDimensionsMapForPreviews: [Int: WindowDimensions],
        appearance: PreviewAppearanceSettings,
        currentSpaceNumbers: Set<Int>
    ) -> some View {
        let windows = previewStateCoordinator.windows
        if index < windows.count {
            let windowInfo = windows[index]

            // Compute live preview eligibility once
            let useLivePreview: Bool = {
                if mockPreviewActive { return false }

                // Check global and context-specific settings
                let windowSwitcherActive = previewStateCoordinator.windowSwitcherActive
                let livePreviewEnabledForContext = windowSwitcherActive ? enableLivePreviewForWindowSwitcher : enableLivePreviewForDock
                guard enableLivePreview, livePreviewEnabledForContext else { return false }

                // Can't use live preview for minimized/hidden windows
                guard !windowInfo.isMinimized, !windowInfo.isEffectivelyHiddenForUI else { return false }

                // Check scope-based eligibility for window switcher
                if windowSwitcherActive {
                    switch windowSwitcherLivePreviewScope {
                    case .allWindows:
                        return true
                    case .selectedWindowOnly:
                        return index == currIndex
                    case .selectedAppWindows:
                        guard currIndex >= 0, currIndex < windows.count else { return false }
                        let selectedBundleID = windows[currIndex].app.bundleIdentifier
                        return windowInfo.app.bundleIdentifier == selectedBundleID
                    }
                }

                return true
            }()

            let isSelected = index == currIndex
            let handleCardAction: (WindowAction) -> Void = { action in
                if action == .selectAllWindows {
                    if !mockPreviewActive { previewStateCoordinator.selectAllDisplayedWindows() }
                } else if action == .toggleWindowSelection {
                    if !mockPreviewActive { previewStateCoordinator.toggleCheckedWindow(windowInfo) }
                } else if !mockPreviewActive,
                          SharedPreviewWindowCoordinator.activeInstance?.performCheckedWindowAction(action, on: windowInfo) != nil
                {
                    return
                } else {
                    if action != .none { SharedPreviewWindowCoordinator.activeInstance?.cancelPreviewBatchAction() }
                    handleWindowAction(action, at: index)
                }
            }
            let presentation = PreviewCardPresentation.resolve(
                isWindowlessApp: windowInfo.isWindowlessApp,
                containerUsesCompactRows: usesCompactRows,
                showFullSizeWindowlessPreviews: appearance.showFullSizeWindowlessPreviews,
                compactWidth: appearance.compactModeWidth,
                previewWidth: appearance.previewWidth
            )

            switch presentation {
            case let .compact(compactRowWidth):
                WindowPreviewCompact(
                    windowInfo: windowInfo,
                    index: index,
                    dockPosition: dockPosition,
                    uniformCardRadius: uniformCardRadius,
                    handleWindowAction: handleCardAction,
                    isSelected: isSelected,
                    windowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
                    mockPreviewActive: mockPreviewActive,
                    onTap: onWindowTap,
                    onHoverIndexChange: handleHoverIndexChange,
                    onDragHoverIndexChange: handleDragHoverIndexChange,
                    widthOverride: compactRowWidth,
                    appearance: appearance,
                    backgroundAppearance: backgroundAppearance,
                    focusedWindowID: previewStateCoordinator.focusedWindowID,
                    currentSpaceNumbers: currentSpaceNumbers,
                    spaceNumber: previewStateCoordinator.desktopNumber(for: windowInfo),
                    isChecked: previewStateCoordinator.selection.checkedWindows.membership.contains(PreviewWindowIdentity(windowInfo)),
                    dragSelection: appearance.enableWindowDragTiling && !mockPreviewActive ? previewStateCoordinator.selection : nil
                )
                .equatable()
                .gesture(previewDragGesture(for: windowInfo))
            case .regular:
                WindowPreview(
                    windowInfo: windowInfo,
                    onTap: onWindowTap,
                    index: index,
                    dockPosition: dockPosition,
                    bestGuessMonitor: bestGuessMonitor,
                    uniformCardRadius: uniformCardRadius,
                    handleWindowAction: handleCardAction,
                    isSelected: isSelected,
                    windowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
                    dimensions: resolvedDimensions(for: index, dimensionsMap: currentDimensionsMapForPreviews),
                    showAppIconOnly: effectiveShowAppIconOnly,
                    mockPreviewActive: mockPreviewActive,
                    onHoverIndexChange: handleHoverIndexChange,
                    onDragHoverIndexChange: handleDragHoverIndexChange,
                    useLivePreview: useLivePreview,
                    appearance: appearance,
                    backgroundAppearance: backgroundAppearance,
                    focusedWindowID: previewStateCoordinator.focusedWindowID,
                    currentSpaceNumbers: currentSpaceNumbers,
                    spaceNumber: previewStateCoordinator.desktopNumber(for: windowInfo),
                    isChecked: previewStateCoordinator.selection.checkedWindows.membership.contains(PreviewWindowIdentity(windowInfo)),
                    dragSelection: appearance.enableWindowDragTiling && !mockPreviewActive ? previewStateCoordinator.selection : nil
                )
                .equatable()
                .gesture(previewDragGesture(for: windowInfo))
            }
        } else {
            EmptyView()
        }
    }

    private func shouldShowNoResultsView() -> Bool {
        let query = previewStateCoordinator.searchQuery
        return previewStateCoordinator.windowSwitcherActive &&
            !query.isEmpty &&
            filteredWindowIndices().isEmpty &&
            embeddedContentType == .none
    }

    private func noResultsView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)

            VStack(spacing: 4) {
                Text("No Results")
                    .font(.headline)
                    .foregroundColor(.primary)

                Text("No windows match your search")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: usesCompactRows ? compactModeWidth : previewWidth, maxWidth: usesCompactRows ? compactModeWidth : previewWidth, minHeight: 120)
    }

    private func noEligibleWindowsView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.minus")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary)

            Text(String(localized: "No Eligible Windows", comment: "Empty Window Switcher scope state"))
                .font(.headline)
                .foregroundColor(.primary)
        }
        .frame(
            minWidth: usesCompactRows ? compactModeWidth : previewWidth,
            maxWidth: usesCompactRows ? compactModeWidth : previewWidth,
            minHeight: 120
        )
    }
}

enum PreviewHeaderLayout {
    static let labelSpacing: CGFloat = 6
    static let minimumHeight: CGFloat = 24
    static let shadowedOuterOverflow: CGFloat = 11.5

    static func dismissalInsets(appHeaderStyle: AppNameStyle?, selectionSummaryStyle: AppNameStyle?) -> EdgeInsets {
        let inset = HoverContainerPadding.container
        return EdgeInsets(top: inset - (appHeaderStyle == .shadowed ? shadowedOuterOverflow : 0), leading: inset,
                          bottom: inset - (selectionSummaryStyle == .shadowed ? shadowedOuterOverflow : 0), trailing: inset)
    }

    static func contentReservation(for style: AppNameStyle) -> CGFloat {
        switch style {
        case .default: 25
        case .popover: 30
        case .shadowed: 0
        }
    }

    static func alignment(for style: AppNameStyle, edge: VerticalEdge) -> Alignment {
        if edge == .top { return style == .popover ? .top : .topLeading }
        return style == .popover ? .bottom : .bottomLeading
    }
}

private struct PreviewHeader<Label: View, Actions: View>: View {
    let style: AppNameStyle
    let edge: VerticalEdge
    let backgroundAppearance: BackgroundAppearance
    let onHover: ((Bool) -> Void)?
    let label: Label
    let actions: Actions

    init(style: AppNameStyle, edge: VerticalEdge, backgroundAppearance: BackgroundAppearance,
         onHover: ((Bool) -> Void)? = nil, @ViewBuilder label: () -> Label, @ViewBuilder actions: () -> Actions)
    {
        self.style = style
        self.edge = edge
        self.backgroundAppearance = backgroundAppearance
        self.onHover = onHover
        self.label = label()
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .center, spacing: style == .default ? nil : 2) {
            label.contentShape(Rectangle())
            actions.padding(.leading, 4)
        }
        .frame(minHeight: PreviewHeaderLayout.minimumHeight)
        .if(style == .popover) {
            $0.padding(.vertical, 5)
                .padding(.horizontal, 10)
                .dockStyle(backgroundAppearance: backgroundAppearance, cornerRadius: 10)
        }
        .contentShape(Rectangle())
        .if(style == .popover) { $0.contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous)) }
        .if(onHover != nil) { view in
            view.onContinuousHover { phase in
                switch phase {
                case .active: onHover?(true)
                case .ended: onHover?(false)
                }
            }
        }
        .if(style == .default) {
            $0.shadow(radius: 2)
                .globalPadding(edge == .top ? .top : .bottom, 12)
                .globalPadding(.leading, 20)
        }
        .if(style == .shadowed) {
            $0.padding(EdgeInsets(top: edge == .top ? -PreviewHeaderLayout.shadowedOuterOverflow : -1.5, leading: 15,
                                  bottom: edge == .top ? -1.5 : -PreviewHeaderLayout.shadowedOuterOverflow, trailing: 1.5))
        }
        .if(style == .popover) {
            $0.offset(y: (edge == .top ? -1 : 1) * PreviewHeaderLayout.contentReservation(for: style))
        }
    }
}

private struct PreviewHeaderTextShadow: ViewModifier {
    let labelWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .appHeaderTextShadow()
            .background {
                ZStack {
                    MaterialBlurView(material: .hudWindow)
                        .mask {
                            Ellipse().fill(LinearGradient(colors: [.white, .white.opacity(0.35)],
                                                          startPoint: .top, endPoint: .bottom))
                        }
                        .blur(radius: 5)
                }
                .frame(width: labelWidth + 30)
            }
    }
}

private struct PreviewSelectionStrip: View {
    @ObservedObject var coordinator: PreviewStateCoordinator
    let style: AppNameStyle
    let backgroundAppearance: BackgroundAppearance

    private var hiddenCount: Int {
        let visible = Set(coordinator.filteredWindowIndices().map { PreviewWindowIdentity(coordinator.windows[$0]) })
        return coordinator.selection.checkedWindows.membership.subtracting(visible).count
    }

    var body: some View {
        let countLabel = String(localized: "\(coordinator.checkedWindowCount) selected")
        PreviewHeader(style: style, edge: .bottom, backgroundAppearance: backgroundAppearance) {
            HStack(spacing: PreviewHeaderLayout.labelSpacing) {
                Text(countLabel)
                    .fontWeight(.medium)
                    .if(style == .shadowed) {
                        $0.modifier(PreviewHeaderTextShadow(labelWidth: measureString(countLabel, fontSize: 14).width))
                    }
                if hiddenCount > 0 {
                    let hiddenLabel = String(localized: "\(hiddenCount) outside view")
                    Text(hiddenLabel)
                        .foregroundStyle(.secondary)
                        .if(style == .shadowed) {
                            $0.modifier(PreviewHeaderTextShadow(labelWidth: measureString(hiddenLabel, fontSize: 14).width))
                        }
                }
            }
        } actions: {
            HStack(spacing: PreviewHeaderLayout.labelSpacing) {
                Button(String(localized: "Select All")) { coordinator.selectAllDisplayedWindows() }
                Button(String(localized: "Clear Selection")) { coordinator.clearCheckedWindows() }
            }
            .font(.caption)
            .buttonStyle(AccentButtonStyle(small: true))
        }
        .font(.body)
        .lineLimit(1)
    }
}
