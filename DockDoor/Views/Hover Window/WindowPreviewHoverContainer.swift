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
    @Default(.mouseHoverAutoScrollSpeed) var mouseHoverAutoScrollSpeed
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

    @State private var draggedWindowIndex: Int? = nil
    @State private var isDragging = false

    @State private var hasAppeared: Bool = false
    @State private var appIcon: NSImage? = nil
    @State private var hoveringAppIcon: Bool = false

    @State private var dragPoints: [CGPoint] = []
    @State private var lastShakeCheck: Date = .init()
    @State private var edgeScrollTimer: Timer?
    @State private var edgeScrollDirection: CGFloat = 0
    @State private var cachedScrollView: CardGridScrollView.ContainerView?
    @State private var edgeScrollHoverSize: CGSize = .zero
    @State private var scrolledFromStart = false
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

    private var minimumEmbeddedWidth: CGFloat {
        let calculatedDimensionsMap = previewStateCoordinator.dimensionState.windowDimensionsMap

        guard !calculatedDimensionsMap.isEmpty else {
            let fallback = MediaControlsLayout.embeddedArtworkSize + MediaControlsLayout.artworkTextSpacing + 165
            return shouldUseCompactMode ? compactModeWidth : fallback
        }

        var minWidth = 0.0

        for dimension in calculatedDimensionsMap {
            let width = dimension.value.size.width
            if minWidth == 0 || width < minWidth {
                minWidth = width
            }
        }

        if shouldUseCompactMode {
            return compactModeWidth
        }

        return minWidth
    }

    private var shouldUseCompactMode: Bool {
        if mockPreviewActive { return false }

        // Force list view if image preview is disabled or screen recording permission is not granted
        if disableImagePreview || !hasScreenRecordingPermission {
            return true
        }

        let windowCount = previewStateCoordinator.windows.count

        if previewStateCoordinator.windowSwitcherActive {
            return windowSwitcherCompactThreshold > 0 && windowCount >= windowSwitcherCompactThreshold
        } else if dockPosition == .cmdTab {
            return cmdTabCompactThreshold > 0 && windowCount >= cmdTabCompactThreshold
        } else {
            return dockPreviewCompactThreshold > 0 && windowCount >= dockPreviewCompactThreshold
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
        let isCompact = shouldUseCompactMode
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
        guard usesHighlightAction else {
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

    private func handleHoverIndexChange(_ hoveredIndex: Int?, _ location: CGPoint?) {
        let isWindowSwitcher = previewStateCoordinator.windowSwitcherActive
        let isCmdTabPreview = !isWindowSwitcher && dockPosition == .cmdTab
        let isDockPreview = !isWindowSwitcher && !isCmdTabPreview
        guard isWindowSwitcher || isDockPreview || isCmdTabPreview else { return }
        if isWindowSwitcher, !enableMouseHoverInSwitcher { return }

        guard let hoveredIndex else {
            if isDockPreview || isWindowSwitcher || isCmdTabPreview {
                previewStateCoordinator.clearSelectionIfMouseSource(shouldScroll: false)
                refreshHighlightActionIfNeeded()
            }
            return
        }
        guard hoveredIndex != previewStateCoordinator.currIndex else { return }

        if isWindowSwitcher, !previewStateCoordinator.hasMovedSinceOpen {
            let screenLocation = NSEvent.mouseLocation

            if previewStateCoordinator.initialHoverLocation == nil {
                previewStateCoordinator.initialHoverLocation = screenLocation
                return
            }

            if let initial = previewStateCoordinator.initialHoverLocation {
                let distance = hypot(screenLocation.x - initial.x, screenLocation.y - initial.y)
                if distance > 1 {
                    previewStateCoordinator.hasMovedSinceOpen = true
                } else {
                    return
                }
            }
        }

        previewStateCoordinator.setIndex(to: hoveredIndex, shouldScroll: false, source: .mouse)
    }

    private func handleDragHoverIndexChange(_ hoveredIndex: Int?) {
        guard enableMouseHoverInSwitcher else { return }
        guard let hoveredIndex else { return }
        guard hoveredIndex != previewStateCoordinator.currIndex else { return }

        if !previewStateCoordinator.hasMovedSinceOpen,
           let initial = previewStateCoordinator.initialHoverLocation
        {
            let screenLocation = NSEvent.mouseLocation
            let distance = hypot(screenLocation.x - initial.x, screenLocation.y - initial.y)
            guard distance > 1 else { return }
            previewStateCoordinator.hasMovedSinceOpen = true
        }

        previewStateCoordinator.setIndex(to: hoveredIndex, shouldScroll: false)
    }

    var body: some View {
        BaseHoverContainer(
            bestGuessMonitor: bestGuessMonitor,
            mockPreviewActive: mockPreviewActive,
            content: { windowGridContent() },
            backgroundAppearance: backgroundAppearance
        )
        .contentShape(Rectangle())
        .onTapGesture {
            activateApp()
        }
        .padding(.top, (!previewStateCoordinator.windowSwitcherActive && effectiveAppNameStyle == .popover && effectiveShowAppName) ? 30 : 0)
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
            if Defaults[.enableLivePreview], Defaults[.livePreviewStreamKeepAlive] != 0 {
                Task { await LiveCaptureManager.shared.panelClosed() }
            }
            stopEdgeScroll()
            cancelDockHighlightAction()
            cancelAllDeferredActionWatchers()
        }
        .onChange(of: previewStateCoordinator.windowSwitcherActive) { isActive in
            if !isActive {
                previewStateCoordinator.searchQuery = ""
                stopEdgeScroll()
            }
            refreshHighlightActionIfNeeded()
        }
        .task(id: previewStateCoordinator.windowSwitcherActive) {
            let keys = PreviewAppearanceSettings.observedKeys + BackgroundAppearance.observedKeys
            for await _ in Defaults.updates(keys, initial: true) {
                let previousAppearance = cachedAppearance
                let updated = PreviewAppearanceSettings.resolve(
                    windowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
                    dockPosition: dockPosition
                )
                if updated != cachedAppearance { cachedAppearance = updated }
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
            refreshHighlightActionIfNeeded()
        }
        .onChange(of: enableMouseHoverInSwitcher) { isEnabled in
            if !isEnabled {
                stopEdgeScroll()
            }
        }
        .onChange(of: shouldUseCompactMode) { _ in
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
        let orientationIsHorizontal: Bool = if previewStateCoordinator.windowSwitcherActive {
            true
        } else {
            dockPosition.isHorizontalFlow
        }
        let scrollAxis: Axis.Set = if shouldUseCompactMode {
            .vertical
        } else if previewStateCoordinator.windowSwitcherActive {
            Defaults[.windowSwitcherScrollDirection] == .horizontal ? .horizontal : .vertical
        } else {
            orientationIsHorizontal ? .horizontal : .vertical
        }

        buildFlowStack(
            orientationIsHorizontal,
            scrollAxis: scrollAxis,
            currentMaxDimensionForPreviews: calculatedMaxDimension,
            currentDimensionsMapForPreviews: calculatedDimensionsMap
        )
        .fadeOnEdges(axis: scrollAxis == .horizontal ? .horizontal : .vertical, fadeLength: 20, disableLeading: dynamicFadeEnabled && !scrolledFromStart)
        .padding(.top, (!previewStateCoordinator.windowSwitcherActive && effectiveAppNameStyle == .default && effectiveShowAppName) ? 25 : 0)
        .overlay(alignment: effectiveAppNameStyle == .popover ? .top : .topLeading) {
            hoverTitleBaseView(labelSize: measureString(appName, fontSize: 14))
        }
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
                                         minimizeAllWindowsCallback: { wasAppActiveBeforeClick in
                                             minimizeAllWindows(wasAppActiveBeforeClick: wasAppActiveBeforeClick)
                                         })
                                         .allowsHitTesting(false)
            }
        }
        .overlay {
            SelectionReader(selection: previewStateCoordinator.selection) { currIndex in
                if dockPosition == .cmdTab,
                   Defaults[.enableCmdTabEnhancements],
                   !Defaults[.hasSeenCmdTabFocusHint],
                   !previewStateCoordinator.windowSwitcherActive,
                   currIndex < 0
                {
                    CmdTabFocusFullOverlayView()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .clipShape(RoundedRectangle(cornerRadius: CardRadius.container, style: .continuous))
                }
            }
        }
        .measure($edgeScrollHoverSize)
        .onContinuousHover { phase in
            guard enableMouseHoverInSwitcher, previewStateCoordinator.windowSwitcherActive else { return }

            switch phase {
            case let .active(location):
                handleEdgeScrollHover(at: location, isHorizontal: scrollAxis == .horizontal)
            case .ended:
                stopEdgeScroll()
            }
        }
    }

    private func handleWindowDrop(at location: CGPoint, for index: Int) {
        guard index < previewStateCoordinator.windows.count else { return }
        let window = previewStateCoordinator.windows[index]
        guard !window.isWindowlessApp else { return }

        let currentScreen = NSScreen.screenFromQuartzPoint(location)
        let globalLocation = DockObserver.cgPointFromNSPoint(location, forScreen: currentScreen)
        window.moveToCurrentManagedSpace(mouseLocation: location)

        let finalPosition = CGPoint(
            x: globalLocation.x,
            y: globalLocation.y
        )

        if let positionValue = AXValue.from(point: finalPosition) {
            try? window.axElement.setAttribute(kAXPositionAttribute, positionValue)
            WindowUtil.updateCachedWindowState(
                window,
                screenIdentifier: .some(currentScreen.uniqueIdentifier())
            )
            window.bringToFront()
            onWindowTap?()
        }
    }

    @ViewBuilder
    private func hoverTitleBaseView(labelSize: CGSize) -> some View {
        let showName = !effectiveShowAppIconOnly

        if !previewStateCoordinator.windowSwitcherActive, effectiveShouldShowHeader {
            Group {
                switch effectiveAppNameStyle {
                case .default:
                    HStack(alignment: .center) {
                        HStack(spacing: 6) {
                            if let appIcon {
                                Image(nsImage: appIcon)
                                    .resizable()
                                    .scaledToFit()
                                    .zIndex(1)
                                    .frame(width: 24, height: 24)
                            } else {
                                ProgressView()
                                    .frame(width: 24, height: 24)
                            }
                            if showName {
                                hoverTitleLabelView(labelSize: labelSize)
                            }
                        }
                        .contentShape(Rectangle())

                        let shouldShowUpdateElements = updateAvailable && !mockPreviewActive

                        Group {
                            update(shouldShowUpdateElements)
                            massOperations(hoveringAppIcon && !updateAvailable && showMassActionButtons)
                        }
                        .padding(.leading, 4)
                    }
                    .contentShape(Rectangle())
                    .onHover { hover in
                        hoveringAppIcon = hover
                    }
                    .shadow(radius: 2)
                    .globalPadding(.top, 12)
                    .globalPadding(.leading, 20)

                case .shadowed:
                    HStack(spacing: 2) {
                        HStack(spacing: 6) {
                            if let appIcon {
                                Image(nsImage: appIcon)
                                    .resizable()
                                    .scaledToFit()
                                    .zIndex(1)
                                    .frame(width: 24, height: 24)
                            } else {
                                ProgressView()
                                    .frame(width: 24, height: 24)
                            }
                            if showName {
                                hoverTitleLabelView(labelSize: labelSize)
                            }
                        }
                        .contentShape(Rectangle())

                        let shouldShowUpdateElements = updateAvailable && !mockPreviewActive

                        Group {
                            update(shouldShowUpdateElements)
                            massOperations(hoveringAppIcon && !updateAvailable && showMassActionButtons)
                        }
                        .padding(.leading, 4)
                    }
                    .contentShape(Rectangle())
                    .onHover { hover in
                        hoveringAppIcon = hover
                    }
                    .padding(EdgeInsets(top: -11.5, leading: 15, bottom: -1.5, trailing: 1.5))

                case .popover:
                    HStack(alignment: .center, spacing: 2) {
                        HStack(spacing: 6) {
                            if let appIcon {
                                Image(nsImage: appIcon)
                                    .resizable()
                                    .scaledToFit()
                                    .zIndex(1)
                                    .frame(width: 24, height: 24)
                            } else {
                                ProgressView()
                                    .frame(width: 24, height: 24)
                            }
                            if showName {
                                hoverTitleLabelView(labelSize: labelSize)
                            }
                        }
                        .contentShape(Rectangle())

                        let shouldShowUpdateElements = updateAvailable && !mockPreviewActive

                        Group {
                            update(shouldShowUpdateElements)
                            massOperations(hoveringAppIcon && !updateAvailable && showMassActionButtons)
                        }
                        .padding(.leading, 4)
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    .dockStyle(backgroundAppearance: backgroundAppearance, cornerRadius: 10)
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onContinuousHover { phase in
                        switch phase {
                        case .active:
                            if !hoveringAppIcon { hoveringAppIcon = true }
                        case .ended:
                            if hoveringAppIcon { hoveringAppIcon = false }
                        }
                    }
                    .offset(y: -30)
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
        if shouldDisplay {
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
                    .shadow(stacked: 2, radius: 6)
                    .background(
                        ZStack {
                            MaterialBlurView(material: .hudWindow)
                                .mask(
                                    Ellipse()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(
                                                    colors: [
                                                        Color.white.opacity(1.0),
                                                        Color.white.opacity(0.35),
                                                    ]
                                                ),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                )
                                .blur(radius: 5)
                        }
                        .frame(width: labelSize.width + 30)
                    )
                } else {
                    baseText
                        .foregroundStyle(Color.primary)
                        .shadow(stacked: 2, radius: 6)
                        .background(
                            ZStack {
                                MaterialBlurView(material: .hudWindow)
                                    .mask(
                                        Ellipse()
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(
                                                        colors: [
                                                            Color.white.opacity(1.0),
                                                            Color.white.opacity(0.35),
                                                        ]
                                                    ),
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            )
                                    )
                                    .blur(radius: 5)
                            }
                            .frame(width: labelSize.width + 30)
                        )
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
                idealWidth: minimumEmbeddedWidth
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
                idealWidth: minimumEmbeddedWidth
            )
            .pinnable(appName: appName, bundleIdentifier: bundleIdentifier, type: .calendar)
        case .none:
            EmptyView()
        }
    }

    @ViewBuilder
    private func buildFlowStack(
        _ isHorizontal: Bool,
        scrollAxis: Axis.Set,
        currentMaxDimensionForPreviews: CGPoint,
        currentDimensionsMapForPreviews: [Int: WindowDimensions]
    ) -> some View {
        let cachedFilteredIndices = filteredWindowIndices()
        let appearance = appearanceOverride ?? cachedAppearance ?? PreviewAppearanceSettings.resolve(
            windowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
            dockPosition: dockPosition
        )
        if shouldShowNoResultsView() {
            noResultsView()
                .globalPadding(20)
                .padding(2)
        } else {
            let lines: [[FlowItem]] = shouldUseCompactMode
                ? createFlowItems(filteredIndices: cachedFilteredIndices).map { [$0] }
                : createChunkedItems(filteredIndices: cachedFilteredIndices)
            let layout = CardGridScrollView.Layout(
                lines: lines,
                isHorizontal: shouldUseCompactMode || isHorizontal,
                scrollsVertically: scrollAxis == .vertical,
                centerLines: previewStateCoordinator.windowSwitcherActive && appearance.allowDynamicImageSizing && !shouldUseCompactMode,
                spacing: shouldUseCompactMode ? 4 : HoverContainerPadding.itemSpacing,
                inset: 20 * appearance.globalPaddingMultiplier,
                dimensions: currentDimensionsMapForPreviews,
                appearance: appearance,
                compact: shouldUseCompactMode
            )
            CardGridScrollView(
                layout: layout,
                contentKey: previewStateCoordinator.windows.map(\.viewSnapshot),
                coordinator: previewStateCoordinator,
                scrolledFromStart: $scrolledFromStart,
                isInteractive: !mockPreviewActive,
                makeCard: { item in
                    AnyView(buildFlowItem(
                        item: item,
                        isHorizontal: isHorizontal,
                        currentMaxDimensionForPreviews: currentMaxDimensionForPreviews,
                        currentDimensionsMapForPreviews: currentDimensionsMapForPreviews,
                        filteredIndices: cachedFilteredIndices,
                        appearance: appearance
                    ))
                }
            )
            .padding(2)
        }
    }

    private func startEdgeScroll(direction: CGFloat, isHorizontal: Bool) {
        edgeScrollDirection = direction
        guard edgeScrollTimer == nil else { return }

        if cachedScrollView == nil || cachedScrollView?.window == nil {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.title.isEmpty }) {
                cachedScrollView = findScrollView(in: window.contentView)
            }
        }

        edgeScrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            smoothScrollBy(direction: edgeScrollDirection, isHorizontal: isHorizontal)
        }
    }

    private func stopEdgeScroll() {
        edgeScrollTimer?.invalidate()
        edgeScrollTimer = nil
        edgeScrollDirection = 0
        cachedScrollView = nil
    }

    private func smoothScrollBy(direction: CGFloat, isHorizontal: Bool) {
        cachedScrollView?.scrollBy(mouseHoverAutoScrollSpeed * direction)
    }

    private func findScrollView(in view: NSView?) -> CardGridScrollView.ContainerView? {
        guard let view else { return nil }
        if let container = view as? CardGridScrollView.ContainerView {
            return container
        }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func handleEdgeScrollHover(at location: CGPoint, isHorizontal: Bool) {
        let edgeSize: CGFloat = 50
        let toolbarExclusion: CGFloat = 46
        let appearance = appearanceOverride ?? cachedAppearance ?? PreviewAppearanceSettings.resolve(
            windowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
            dockPosition: dockPosition
        )
        let topExclusion = appearance.controlPosition.showsOnTop ? toolbarExclusion : 0
        let bottomExclusion = appearance.controlPosition.showsOnBottom ? toolbarExclusion : 0
        let width = edgeScrollHoverSize.width
        let height = edgeScrollHoverSize.height

        guard width > 0, height > 0 else {
            stopEdgeScroll()
            return
        }

        guard location.y >= topExclusion, location.y <= height - bottomExclusion else {
            stopEdgeScroll()
            return
        }

        if isHorizontal {
            if location.x <= edgeSize {
                startEdgeScroll(direction: -1, isHorizontal: true)
            } else if location.x >= width - edgeSize {
                startEdgeScroll(direction: 1, isHorizontal: true)
            } else {
                stopEdgeScroll()
            }
        } else {
            if location.y <= topExclusion + edgeSize {
                startEdgeScroll(direction: -1, isHorizontal: false)
            } else if location.y >= height - bottomExclusion - edgeSize {
                startEdgeScroll(direction: 1, isHorizontal: false)
            } else {
                stopEdgeScroll()
            }
        }
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
        guard !previewStateCoordinator.windows.isEmpty else { return }
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
        guard index < previewStateCoordinator.windows.count else { return }
        let window = previewStateCoordinator.windows[index]
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
        let keepPreviewsOpen = category?.keepPreviewsOpen ?? true
        let closeAfterSuccess = action.closePreviewsOnlyAfterSuccess(
            for: actionStateWindow,
            category: category
        )
        let shouldClosePreviews = !keepPreviewsOpen
        let shouldForegroundMoveResize = !shouldClosePreviews &&
            Defaults[.moveResizeBringToForeground] &&
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

    private func lookupDimensions(for index: Int, dimensionsMap: [Int: WindowDimensions]) -> WindowDimensions? {
        dimensionsMap[index]
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

    private func createChunkedItems(filteredIndices: [Int]) -> [[FlowItem]] {
        let isHorizontal: Bool = if previewStateCoordinator.windowSwitcherActive {
            true
        } else {
            dockPosition.isHorizontalFlow
        }

        var itemsToProcess: [FlowItem] = []
        itemsToProcess.reserveCapacity(filteredIndices.count + (embeddedContentType != .none ? 1 : 0))
        for index in filteredIndices {
            itemsToProcess.append(.window(index))
        }
        if embeddedContentType != .none {
            itemsToProcess.append(.embedded)
        }

        var (maxColumns, maxRows) = WindowPreviewHoverContainer.calculateEffectiveMaxColumnsAndRows(
            bestGuessMonitor: bestGuessMonitor,
            overallMaxDimensions: previewStateCoordinator.dimensionState.overallMaxPreviewDimension,
            dockPosition: dockPosition,
            isWindowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
            previewMaxColumns: previewMaxColumns,
            previewMaxRows: previewMaxRows,
            switcherMaxRows: switcherMaxRows,
            totalItems: itemsToProcess.count
        )

        guard maxColumns > 0, maxRows > 0 else {
            return itemsToProcess.isEmpty ? [[]] : [itemsToProcess]
        }

        if mockPreviewActive, previewStateCoordinator.windowSwitcherActive {
            maxRows = 1
        }

        let shouldReverse = (dockPosition == .bottom || dockPosition == .right) && !previewStateCoordinator.windowSwitcherActive

        let chunks = WindowPreviewHoverContainer.chunkArray(
            items: itemsToProcess,
            isHorizontal: isHorizontal,
            maxColumns: maxColumns,
            maxRows: maxRows,
            reverse: shouldReverse,
            fillToLimit: previewStateCoordinator.windowSwitcherActive && Defaults[.windowSwitcherScrollDirection] == .vertical
        )

        return chunks.isEmpty ? [[]] : chunks
    }

    @ViewBuilder
    private func buildFlowItem(
        item: FlowItem,
        isHorizontal: Bool,
        currentMaxDimensionForPreviews: CGPoint,
        currentDimensionsMapForPreviews: [Int: WindowDimensions],
        filteredIndices: [Int],
        appearance: PreviewAppearanceSettings
    ) -> some View {
        switch item {
        case .embedded:
            let dims = currentDimensionsMapForPreviews[filteredIndices.first ?? 0]
            embeddedContentView()
                .frame(
                    minWidth: shouldUseCompactMode ? nil : (isHorizontal ? nil : dims?.size.width),
                    maxWidth: shouldUseCompactMode ? appearance.compactModeWidth + 2 * CardRadius.innerPadding : nil,
                    minHeight: isHorizontal ? (shouldUseCompactMode ? nil : dims?.size.height) : nil
                )
                .fixedSize(horizontal: false, vertical: shouldUseCompactMode)
                .id("\(appName)-embedded")
        case let .window(index):
            SelectionReader(selection: previewStateCoordinator.selection) { currIndex in
                windowFlowItem(
                    index: index,
                    currIndex: currIndex,
                    currentDimensionsMapForPreviews: currentDimensionsMapForPreviews,
                    appearance: appearance
                )
            }
            .id("\(appName)-\(index)")
        }
    }

    @ViewBuilder
    private func windowFlowItem(
        index: Int,
        currIndex: Int,
        currentDimensionsMapForPreviews: [Int: WindowDimensions],
        appearance: PreviewAppearanceSettings
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

            let useWindowlessCompactRowInDockLikeMode = windowInfo.isWindowlessApp &&
                (!previewStateCoordinator.windowSwitcherActive || dockPosition == .cmdTab) &&
                !shouldUseCompactMode
            // Use compact mode if the container requires it, for windowless Dock/Cmd+Tab rows, or as an image fallback.
            let useCompactForThisWindow = shouldUseCompactMode ||
                useWindowlessCompactRowInDockLikeMode ||
                (windowInfo.image == nil && !useLivePreview)

            let isSelected = index == currIndex

            if windowInfo.isWindowlessApp, !shouldUseCompactMode, !useWindowlessCompactRowInDockLikeMode {
                WindowlessAppPreview(
                    windowInfo: windowInfo,
                    index: index,
                    dockPosition: dockPosition,
                    uniformCardRadius: uniformCardRadius,
                    isSelected: isSelected,
                    windowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
                    dimensions: lookupDimensions(for: index, dimensionsMap: currentDimensionsMapForPreviews),
                    mockPreviewActive: mockPreviewActive,
                    handleWindowAction: { action in
                        handleWindowAction(action, at: index)
                    },
                    onTap: onWindowTap,
                    onHoverIndexChange: handleHoverIndexChange,
                    appearance: appearance,
                    backgroundAppearance: backgroundAppearance
                )
                .equatable()
            } else if useCompactForThisWindow {
                let compactRowWidth = if shouldUseCompactMode {
                    appearance.compactModeWidth
                } else if useWindowlessCompactRowInDockLikeMode {
                    appearance.previewWidth
                } else {
                    resolvedDimensions(for: index, dimensionsMap: currentDimensionsMapForPreviews).size.width
                }
                WindowPreviewCompact(
                    windowInfo: windowInfo,
                    index: index,
                    dockPosition: dockPosition,
                    uniformCardRadius: uniformCardRadius,
                    handleWindowAction: { action in
                        handleWindowAction(action, at: index)
                    },
                    isSelected: isSelected,
                    windowSwitcherActive: previewStateCoordinator.windowSwitcherActive,
                    mockPreviewActive: mockPreviewActive,
                    onTap: onWindowTap,
                    onHoverIndexChange: handleHoverIndexChange,
                    widthOverride: compactRowWidth,
                    appearance: appearance,
                    backgroundAppearance: backgroundAppearance,
                    focusedWindowID: previewStateCoordinator.focusedWindowID
                )
                .equatable()
            } else {
                WindowPreview(
                    windowInfo: windowInfo,
                    onTap: onWindowTap,
                    index: index,
                    dockPosition: dockPosition,
                    bestGuessMonitor: bestGuessMonitor,
                    uniformCardRadius: uniformCardRadius,
                    handleWindowAction: { action in
                        handleWindowAction(action, at: index)
                    },
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
                    focusedWindowID: previewStateCoordinator.focusedWindowID
                )
                .equatable()
                .gesture(
                    DragGesture(minimumDistance: 3, coordinateSpace: .global)
                        .onChanged { value in
                            if draggedWindowIndex == nil {
                                draggedWindowIndex = index
                                isDragging = true
                                DragPreviewCoordinator.shared.startDragging(
                                    windowInfo: windowInfo,
                                    at: NSEvent.mouseLocation
                                )
                            }
                            if draggedWindowIndex == index {
                                let currentPoint = value.location
                                if !previewStateCoordinator.windowSwitcherActive, aeroShakeAction != .none,
                                   checkForShakeGesture(currentPoint: currentPoint)
                                {
                                    DragPreviewCoordinator.shared.endDragging()
                                    draggedWindowIndex = nil
                                    isDragging = false

                                    switch aeroShakeAction {
                                    case .all:
                                        minimizeAllWindows()
                                    case .except:
                                        minimizeAllWindows(windowInfo)
                                    default: break
                                    }
                                } else {
                                    DragPreviewCoordinator.shared.updatePreviewPosition(to: NSEvent.mouseLocation)
                                }
                            }
                        }
                        .onEnded { value in
                            if draggedWindowIndex == index {
                                handleWindowDrop(at: NSEvent.mouseLocation, for: index)
                                DragPreviewCoordinator.shared.endDragging()
                                draggedWindowIndex = nil
                                isDragging = false
                                dragPoints.removeAll()
                            }
                        }
                )
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
        .frame(minWidth: shouldUseCompactMode ? compactModeWidth : previewWidth, maxWidth: shouldUseCompactMode ? compactModeWidth : previewWidth, minHeight: 120)
    }
}
