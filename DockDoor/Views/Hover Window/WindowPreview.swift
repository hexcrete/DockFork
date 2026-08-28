import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct SpaceNumberIndicator: View {
    static let unstyledControlLineHeight: CGFloat = 24
    private static let styledBadgeMinimumSize = CGSize(width: 14, height: 14)

    let number: Int
    let disableDockStyling: Bool
    let backgroundAppearance: BackgroundAppearance

    @ViewBuilder
    private func badgeContent(minimumWidth: CGFloat?, minimumHeight: CGFloat) -> some View {
        Text("\(number)")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .frame(minWidth: minimumWidth, minHeight: minimumHeight)
            .padding(.horizontal, number > 9 ? 2 : 0)
    }

    var body: some View {
        Group {
            if disableDockStyling {
                badgeContent(minimumWidth: 18, minimumHeight: 18)
                    .overlay {
                        Capsule().stroke(.secondary, lineWidth: 1)
                    }
                    .frame(height: Self.unstyledControlLineHeight)
                    .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
            } else {
                badgeContent(minimumWidth: nil, minimumHeight: 0)
                    .frame(
                        minWidth: Self.styledBadgeMinimumSize.width,
                        minHeight: Self.styledBadgeMinimumSize.height
                    )
                    .padding(4)
                    .materialPill(backgroundAppearance: backgroundAppearance)
            }
        }
        .accessibilityLabel(Text("Space \(number)"))
    }
}

struct PreviewAppearanceSettings: Equatable {
    let trafficLightVisibility: TrafficLightButtonsVisibility
    let enabledTrafficLightButtons: Set<WindowAction>
    let useMonochromeTrafficLights: Bool
    let showWindowTitle: Bool
    let windowTitleVisibility: WindowTitleVisibility
    let controlPosition: WindowSwitcherControlPosition
    let useEmbeddedElements: Bool
    let disableDockStyleTrafficLights: Bool
    let disableDockStyleTitles: Bool
    let showMinimizedHiddenLabels: Bool
    let selectionOpacity: Double
    let unselectedContentOpacity: Double
    let hoverHighlightColor: Color?
    let allowDynamicImageSizing: Bool
    let hidePreviewCardBackground: Bool
    let tapEquivalentInterval: Double
    let previewHoverAction: PreviewHoverAction
    let showActiveWindowBorder: Bool
    let activeAppIndicatorColor: Color
    let showAnimations: Bool
    let globalPaddingMultiplier: CGFloat
    let windowTitleFontSize: WindowTitleFontSize
    let trafficLightButtonScale: CGFloat
    let livePreviewQuality: LivePreviewQuality
    let livePreviewFrameRate: LivePreviewFrameRate
    let previewWidth: CGFloat
    let compactModeWidth: CGFloat
    let compactModeTitleFormat: CompactModeTitleFormat
    let compactModeItemSize: CompactModeItemSize
    let compactModeHideTrafficLights: Bool
    let showSpaceNumberIndicator: Bool
    let disableDockStyleSpaceNumberIndicator: Bool
    let titleOverflowStyle: TitleOverflowStyle

    var isDiagonalPosition: Bool {
        switch controlPosition {
        case .diagonalTopLeftBottomRight, .diagonalTopRightBottomLeft,
             .diagonalBottomLeftTopRight, .diagonalBottomRightTopLeft:
            true
        default:
            false
        }
    }

    static let observedKeys: [Defaults._AnyKey] = [
        .trafficLightButtonsVisibility, .switcherTrafficLightButtonsVisibility, .cmdTabTrafficLightButtonsVisibility,
        .enabledTrafficLightButtons, .switcherEnabledTrafficLightButtons, .cmdTabEnabledTrafficLightButtons,
        .useMonochromeTrafficLights, .switcherUseMonochromeTrafficLights, .cmdTabUseMonochromeTrafficLights,
        .showWindowTitle, .switcherShowWindowTitle, .cmdTabShowWindowTitle,
        .windowTitleVisibility, .switcherWindowTitleVisibility, .cmdTabWindowTitleVisibility,
        .dockPreviewControlPosition, .windowSwitcherControlPosition, .cmdTabControlPosition,
        .useEmbeddedDockPreviewElements, .cmdTabUseEmbeddedDockPreviewElements,
        .disableDockStyleTrafficLights, .switcherDisableDockStyleTrafficLights, .cmdTabDisableDockStyleTrafficLights,
        .disableDockStyleTitles, .cmdTabDisableDockStyleTitles,
        .dockLivePreviewQuality, .windowSwitcherLivePreviewQuality,
        .dockLivePreviewFrameRate, .windowSwitcherLivePreviewFrameRate,
        .showDockPreviewSpaceNumberIndicator, .showSwitcherSpaceNumberIndicator, .showCmdTabSpaceNumberIndicator,
        .disableDockStyleSpaceNumberIndicator, .switcherDisableDockStyleSpaceNumberIndicator, .cmdTabDisableDockStyleSpaceNumberIndicator,
        .showMinimizedHiddenLabels, .selectionOpacity, .unselectedContentOpacity, .hoverHighlightColor,
        .allowDynamicImageSizing, .hidePreviewCardBackground,
        .tapEquivalentInterval, .switcherTapEquivalentInterval, .cmdTabTapEquivalentInterval,
        .previewHoverAction, .switcherPreviewHoverAction, .cmdTabPreviewHoverAction,
        .showActiveWindowBorder, .activeAppIndicatorColor, .showAnimations, .globalPaddingMultiplier,
        .windowTitleFontSize, .trafficLightButtonScale,
        .previewWidth, .compactModeWidth, .compactModeTitleFormat, .compactModeItemSize, .compactModeHideTrafficLights, .titleOverflowStyle,
    ]

    static func resolve(windowSwitcherActive: Bool, dockPosition: DockPosition) -> PreviewAppearanceSettings {
        let isCmdTab = dockPosition == .cmdTab
        func pick<T: Defaults.Serializable>(
            _ base: Defaults.Key<T>,
            switcher: Defaults.Key<T>? = nil,
            cmdTab: Defaults.Key<T>? = nil
        ) -> T {
            if windowSwitcherActive, let switcher { return Defaults[switcher] }
            if isCmdTab, let cmdTab { return Defaults[cmdTab] }
            return Defaults[base]
        }

        return PreviewAppearanceSettings(
            trafficLightVisibility: pick(.trafficLightButtonsVisibility, switcher: .switcherTrafficLightButtonsVisibility, cmdTab: .cmdTabTrafficLightButtonsVisibility),
            enabledTrafficLightButtons: pick(.enabledTrafficLightButtons, switcher: .switcherEnabledTrafficLightButtons, cmdTab: .cmdTabEnabledTrafficLightButtons),
            useMonochromeTrafficLights: pick(.useMonochromeTrafficLights, switcher: .switcherUseMonochromeTrafficLights, cmdTab: .cmdTabUseMonochromeTrafficLights),
            showWindowTitle: pick(.showWindowTitle, switcher: .switcherShowWindowTitle, cmdTab: .cmdTabShowWindowTitle),
            windowTitleVisibility: pick(.windowTitleVisibility, switcher: .switcherWindowTitleVisibility, cmdTab: .cmdTabWindowTitleVisibility),
            controlPosition: pick(.dockPreviewControlPosition, switcher: .windowSwitcherControlPosition, cmdTab: .cmdTabControlPosition),
            useEmbeddedElements: pick(.useEmbeddedDockPreviewElements, cmdTab: .cmdTabUseEmbeddedDockPreviewElements),
            disableDockStyleTrafficLights: pick(.disableDockStyleTrafficLights, switcher: .switcherDisableDockStyleTrafficLights, cmdTab: .cmdTabDisableDockStyleTrafficLights),
            disableDockStyleTitles: pick(.disableDockStyleTitles, cmdTab: .cmdTabDisableDockStyleTitles),
            showMinimizedHiddenLabels: Defaults[.showMinimizedHiddenLabels],
            selectionOpacity: Defaults[.selectionOpacity],
            unselectedContentOpacity: Defaults[.unselectedContentOpacity],
            hoverHighlightColor: Defaults[.hoverHighlightColor],
            allowDynamicImageSizing: Defaults[.allowDynamicImageSizing],
            hidePreviewCardBackground: Defaults[.hidePreviewCardBackground],
            tapEquivalentInterval: pick(.tapEquivalentInterval, switcher: .switcherTapEquivalentInterval, cmdTab: .cmdTabTapEquivalentInterval),
            previewHoverAction: pick(.previewHoverAction, switcher: .switcherPreviewHoverAction, cmdTab: .cmdTabPreviewHoverAction),
            showActiveWindowBorder: Defaults[.showActiveWindowBorder],
            activeAppIndicatorColor: Defaults[.activeAppIndicatorColor],
            showAnimations: Defaults[.showAnimations],
            globalPaddingMultiplier: Defaults[.globalPaddingMultiplier],
            windowTitleFontSize: Defaults[.windowTitleFontSize],
            trafficLightButtonScale: Defaults[.trafficLightButtonScale],
            livePreviewQuality: pick(.dockLivePreviewQuality, switcher: .windowSwitcherLivePreviewQuality),
            livePreviewFrameRate: pick(.dockLivePreviewFrameRate, switcher: .windowSwitcherLivePreviewFrameRate),
            previewWidth: Defaults[.previewWidth],
            compactModeWidth: Defaults[.compactModeWidth],
            compactModeTitleFormat: Defaults[.compactModeTitleFormat],
            compactModeItemSize: Defaults[.compactModeItemSize],
            compactModeHideTrafficLights: Defaults[.compactModeHideTrafficLights],
            showSpaceNumberIndicator: pick(.showDockPreviewSpaceNumberIndicator, switcher: .showSwitcherSpaceNumberIndicator, cmdTab: .showCmdTabSpaceNumberIndicator),
            disableDockStyleSpaceNumberIndicator: pick(.disableDockStyleSpaceNumberIndicator, switcher: .switcherDisableDockStyleSpaceNumberIndicator, cmdTab: .cmdTabDisableDockStyleSpaceNumberIndicator),
            titleOverflowStyle: Defaults[.titleOverflowStyle]
        )
    }
}

struct WindowPreview: View, Equatable {
    let windowInfo: WindowInfo
    let onTap: (() -> Void)?
    let index: Int
    let dockPosition: DockPosition
    let bestGuessMonitor: NSScreen
    let uniformCardRadius: Bool
    let handleWindowAction: (WindowAction) -> Void
    var isSelected: Bool
    var windowSwitcherActive: Bool
    let dimensions: WindowPreviewHoverContainer.WindowDimensions
    let showAppIconOnly: Bool
    let mockPreviewActive: Bool
    let onHoverIndexChange: ((Int?, CGPoint?) -> Void)?
    let useLivePreview: Bool
    var skeletonMode: Bool = false
    var appearance: PreviewAppearanceSettings
    let backgroundAppearance: BackgroundAppearance
    let activeFocusedWindowID: CGWindowID?

    @State private var isHoveringOverDockPeekPreview = false
    @State private var isHoveringOverWindowSwitcherPreview = false
    @State private var isDraggingOver = false
    @State private var dragTimer: Timer?
    @State private var highlightOpacity = 0.0

    private var effectiveTrafficLightButtons: Set<WindowAction> {
        if windowInfo.isWindowlessApp {
            return appearance.enabledTrafficLightButtons.intersection([.quit])
        }
        return appearance.enabledTrafficLightButtons
    }

    private var isEffectivelyHidden: Bool {
        windowInfo.isEffectivelyHiddenForUI
    }

    private var windowStateLabel: String? {
        guard appearance.showMinimizedHiddenLabels else { return nil }
        if windowInfo.isMinimized {
            return String(localized: "Minimized", comment: "Window state label")
        } else if isEffectivelyHidden {
            return String(localized: "Hidden", comment: "Window state label")
        } else if windowInfo.isFullscreen == true {
            return String(localized: "Full Screen", comment: "Window state label")
        }
        return nil
    }

    private var windowStateSymbol: String? {
        guard appearance.showMinimizedHiddenLabels else { return nil }
        if windowInfo.isMinimized || isEffectivelyHidden {
            return "eye.slash"
        } else if windowInfo.isFullscreen == true {
            return "arrow.up.left.and.arrow.down.right"
        }
        return nil
    }

    private var hasSpaceIndicator: Bool {
        appearance.showSpaceNumberIndicator && windowInfo.spaceNumber != nil
    }

    private var embeddedControlsAreLeading: Bool {
        let topConfiguration = appearance.controlPosition.topConfiguration
        return topConfiguration.showControls
            ? topConfiguration.isLeadingControls
            : appearance.controlPosition.bottomConfiguration.isLeadingControls
    }

    @ViewBuilder
    private func spaceIndicator(
        controlsAreLeading: Bool,
        nonAlignmentPadding: CGFloat
    ) -> some View {
        if appearance.showSpaceNumberIndicator, let spaceNumber = windowInfo.spaceNumber {
            let adjustedPadding = max(0, nonAlignmentPadding)
            SpaceNumberIndicator(
                number: spaceNumber,
                disableDockStyling: appearance.disableDockStyleSpaceNumberIndicator,
                backgroundAppearance: backgroundAppearance
            )
            .padding(.leading, controlsAreLeading ? 0 : -adjustedPadding)
            .padding(.trailing, controlsAreLeading ? -adjustedPadding : 0)
        }
    }

    @ViewBuilder
    private func controlsWithSpaceIndicator(
        controlsAreLeading: Bool,
        nonAlignmentPadding: CGFloat = 0,
        spacing: CGFloat = 8,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let sideInset: CGFloat = nonAlignmentPadding > 0 ? 2 : 0
        HStack(spacing: spacing) {
            if controlsAreLeading {
                content()
                spaceIndicator(
                    controlsAreLeading: true,
                    nonAlignmentPadding: nonAlignmentPadding
                )
            } else {
                spaceIndicator(
                    controlsAreLeading: false,
                    nonAlignmentPadding: nonAlignmentPadding
                )
                content()
            }
        }
        .padding(.leading, controlsAreLeading ? 0 : sideInset)
        .padding(.trailing, controlsAreLeading ? sideInset : 0)
    }

    private func controlsSpacing(hasAdjacentControl: Bool) -> CGFloat {
        appearance.disableDockStyleSpaceNumberIndicator || hasAdjacentControl ? 8 : 0
    }

    private var canRenderTrafficLightButtons: Bool {
        appearance.trafficLightVisibility != .never &&
            !effectiveTrafficLightButtons.isEmpty &&
            (windowInfo.closeButton != nil || windowInfo.isWindowlessApp || windowInfo.isMinimized || isEffectivelyHidden)
    }

    private func shouldShowTrafficLightButtons(parentHovered: Bool) -> Bool {
        appearance.trafficLightVisibility.isVisible(
            hoveringOverParentWindow: parentHovered,
            mockPreviewActive: mockPreviewActive
        )
    }

    static func == (l: Self, r: Self) -> Bool {
        l.index == r.index && l.isSelected == r.isSelected && l.useLivePreview == r.useLivePreview
            && l.skeletonMode == r.skeletonMode && l.dimensions == r.dimensions
            && l.uniformCardRadius == r.uniformCardRadius && l.showAppIconOnly == r.showAppIconOnly
            && l.windowSwitcherActive == r.windowSwitcherActive
            && l.appearance == r.appearance && l.windowInfo.viewSnapshot == r.windowInfo.viewSnapshot
            && l.backgroundAppearance == r.backgroundAppearance
            && l.activeFocusedWindowID == r.activeFocusedWindowID
    }

    private var isActiveWindow: Bool {
        guard appearance.showActiveWindowBorder else { return false }
        guard let activeFocusedWindowID else { return false }
        return windowInfo.id == activeFocusedWindowID
    }

    @ViewBuilder
    private func titleLabel(_ text: String, adaptsToAvailableWidth: Bool = false) -> some View {
        switch appearance.titleOverflowStyle {
        case .marquee:
            MarqueeText(text: text, startDelay: 1, adaptsToAvailableWidth: adaptsToAvailableWidth)
        case .truncateTail:
            MarqueeText(
                text: text,
                truncationMode: .tail,
                enableScrolling: false,
                adaptsToAvailableWidth: adaptsToAvailableWidth
            )
        case .truncateMiddle:
            MarqueeText(
                text: text,
                truncationMode: .middle,
                enableScrolling: false,
                adaptsToAvailableWidth: adaptsToAvailableWidth
            )
        case .truncateHead:
            MarqueeText(
                text: text,
                truncationMode: .head,
                enableScrolling: false,
                adaptsToAvailableWidth: adaptsToAvailableWidth
            )
        }
    }

    @ViewBuilder
    private func windowContent(isMinimized: Bool, isHidden: Bool, isSelected: Bool) -> some View {
        let inactive = (isMinimized || isHidden) && appearance.showMinimizedHiddenLabels
        let stateSymbol = windowStateSymbol
        let quality = appearance.livePreviewQuality
        let frameRate = appearance.livePreviewFrameRate

        Group {
            if skeletonMode {
                Color.clear
            } else if useLivePreview {
                LivePreviewImage(windowID: windowInfo.id, fallbackImage: windowInfo.image, quality: quality, frameRate: frameRate)
            } else if let cgImage = windowInfo.image {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .scaledToFit()
            }
        }
        .markHidden(isHidden: inactive || (windowSwitcherActive && !isSelected))
        .overlay {
            if let stateSymbol {
                Image(systemName: stateSymbol)
                    .font(.largeTitle)
                    .foregroundColor(.primary)
                    .shadow(radius: 2)
                    .transition(.opacity)
            }
        }
        .animation(appearance.showAnimations ? .easeInOut(duration: 0.15) : nil, value: stateSymbol)
        .clipShape(RoundedRectangle(cornerRadius: CardRadius.image, style: .continuous))
        .dynamicWindowFrame(
            allowDynamicSizing: appearance.allowDynamicImageSizing && !windowSwitcherActive,
            dimensions: dimensions,
            dockPosition: dockPosition,
            windowSwitcherActive: windowSwitcherActive
        )
        .opacity(isSelected ? 1.0 : appearance.unselectedContentOpacity)
    }

    @ViewBuilder
    private func embeddedControlsOverlay(_ selected: Bool) -> some View {
        if !windowSwitcherActive {
            embeddedDockPreviewControls(selected)
        }
    }

    @ViewBuilder
    private func embeddedDockPreviewControls(_ selected: Bool) -> some View {
        let titleToShow: String? = if let windowTitle = windowInfo.windowName, !windowTitle.isEmpty {
            windowTitle
        } else {
            windowInfo.app.localizedName
        }

        let hasTitle = appearance.showWindowTitle &&
            titleToShow != nil &&
            (appearance.windowTitleVisibility == .alwaysVisible || selected)

        let hasTrafficLights = canRenderTrafficLightButtons
        let showTrafficLights = shouldShowTrafficLightButtons(
            parentHovered: selected || isHoveringOverDockPeekPreview
        )
        let hasVisibleAdjacentControl = (hasTrafficLights && showTrafficLights) ||
            (!hasTrafficLights && windowStateLabel != nil && appearance.trafficLightVisibility != .never)
        let titleContent = Group {
            if hasTitle, let title = titleToShow {
                titleLabel(title, adaptsToAvailableWidth: true)
                    .font(appearance.windowTitleFontSize.font)
                    .padding(4)
                    .if(!appearance.disableDockStyleTitles) { view in
                        view.materialPill(backgroundAppearance: backgroundAppearance)
                    }
                    .frame(minWidth: 0)
                    .clipped()
            }
        }

        let controlsContent = controlsWithSpaceIndicator(
            controlsAreLeading: embeddedControlsAreLeading,
            nonAlignmentPadding: hasTrafficLights && showTrafficLights ? 10 : 0,
            spacing: controlsSpacing(hasAdjacentControl: hasVisibleAdjacentControl)
        ) {
            if hasTrafficLights {
                TrafficLightButtons(
                    displayMode: appearance.trafficLightVisibility,
                    hoveringOverParentWindow: selected || isHoveringOverDockPeekPreview,
                    onWindowAction: handleWindowAction,
                    pillStyling: !appearance.disableDockStyleTrafficLights,
                    mockPreviewActive: mockPreviewActive,
                    enabledButtons: effectiveTrafficLightButtons,
                    useMonochrome: appearance.useMonochromeTrafficLights,
                    buttonScale: appearance.trafficLightButtonScale,
                    backgroundAppearance: backgroundAppearance
                )
                .frame(width: showTrafficLights ? nil : 0)
                .clipped()
                .animation(nil, value: showTrafficLights)
            } else if let windowStateLabel,
                      appearance.trafficLightVisibility != .never
            {
                Text(windowStateLabel)
                    .font(appearance.windowTitleFontSize.font)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .if(!appearance.disableDockStyleTitles) { view in
                        view.materialPill(backgroundAppearance: backgroundAppearance)
                            .frame(height: 34)
                    }
            }
        }

        if hasTitle || hasTrafficLights || hasSpaceIndicator {
            switch appearance.controlPosition {
            case .topLeading, .topTrailing:
                VStack {
                    HStack(spacing: 4) {
                        if appearance.controlPosition == .topLeading {
                            titleContent
                            Spacer()
                            controlsContent
                        } else {
                            controlsContent
                            Spacer()
                            titleContent
                        }
                    }
                    .padding(8)
                    Spacer()
                }
            case .bottomLeading, .bottomTrailing:
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        if appearance.controlPosition == .bottomLeading {
                            titleContent
                            Spacer()
                            controlsContent
                        } else {
                            controlsContent
                            Spacer()
                            titleContent
                        }
                    }
                    .padding(8)
                }
            case .centeredTitleTopControlsBottom:
                VStack {
                    HStack {
                        Spacer()
                        titleContent
                        Spacer()
                    }
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        Spacer()
                        controlsContent
                        Spacer()
                    }
                    .padding(.bottom, 8)
                }
            case .centeredControlsTopTitleBottom:
                VStack {
                    HStack {
                        Spacer()
                        controlsContent
                        Spacer()
                    }
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        Spacer()
                        titleContent
                        Spacer()
                    }
                    .padding(.bottom, 8)
                }
            case .diagonalTopLeftBottomRight:
                VStack {
                    HStack {
                        titleContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        Spacer()
                        controlsContent
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
            case .diagonalTopRightBottomLeft:
                VStack {
                    HStack {
                        Spacer()
                        titleContent
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        controlsContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
                }
            case .diagonalBottomLeftTopRight:
                VStack {
                    HStack {
                        Spacer()
                        controlsContent
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        titleContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
                }
            case .diagonalBottomRightTopLeft:
                VStack {
                    HStack {
                        controlsContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        Spacer()
                        titleContent
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
            case .parallelTopLeftBottomLeft:
                VStack {
                    HStack {
                        titleContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        controlsContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
                }
            case .parallelTopRightBottomRight:
                VStack {
                    HStack {
                        Spacer()
                        titleContent
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        Spacer()
                        controlsContent
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
            case .parallelBottomLeftTopLeft:
                VStack {
                    HStack {
                        controlsContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        titleContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
                }
            case .parallelBottomRightTopRight:
                VStack {
                    HStack {
                        Spacer()
                        controlsContent
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        Spacer()
                        titleContent
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func windowSwitcherContent(_ selected: Bool, isLeadingControls: Bool, showTitleContent: Bool = true, showControlsContent: Bool = true) -> some View {
        let shouldShowWindowTitle = appearance.showWindowTitle &&
            (appearance.windowTitleVisibility == .alwaysVisible || selected || isHoveringOverWindowSwitcherPreview)
        let showTrafficLights = shouldShowTrafficLightButtons(
            parentHovered: selected || isHoveringOverWindowSwitcherPreview
        )
        let hasVisibleAdjacentControl = (canRenderTrafficLightButtons && showTrafficLights) ||
            (!canRenderTrafficLightButtons && windowStateLabel != nil && appearance.trafficLightVisibility != .never)
        let titleAndSubtitleContent = VStack(alignment: .leading, spacing: 0) {
            if !showAppIconOnly {
                Text(windowInfo.app.localizedName ?? "Unknown")
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if let windowTitle = windowInfo.windowName,
               !windowTitle.isEmpty,
               windowTitle != windowInfo.app.localizedName,
               shouldShowWindowTitle
            {
                titleLabel(windowTitle, adaptsToAvailableWidth: true)
                    .font(appearance.windowTitleFontSize.font)
                    .foregroundStyle(.secondary)
            }
        }

        let appIconContent = Group {
            if let appIcon = windowInfo.app.icon {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 35, height: 35)
            }
        }

        let controlsContent = controlsWithSpaceIndicator(
            controlsAreLeading: isLeadingControls,
            nonAlignmentPadding: 0,
            spacing: controlsSpacing(hasAdjacentControl: hasVisibleAdjacentControl)
        ) {
            if canRenderTrafficLightButtons {
                TrafficLightButtons(
                    displayMode: appearance.trafficLightVisibility,
                    hoveringOverParentWindow: selected || isHoveringOverWindowSwitcherPreview,
                    onWindowAction: handleWindowAction,
                    pillStyling: !appearance.disableDockStyleTrafficLights,
                    mockPreviewActive: mockPreviewActive,
                    enabledButtons: effectiveTrafficLightButtons,
                    useMonochrome: appearance.useMonochromeTrafficLights,
                    backgroundAppearance: backgroundAppearance
                )
                .frame(width: showTrafficLights ? nil : 0)
                .clipped()
            } else if let windowStateLabel,
                      appearance.trafficLightVisibility != .never
            {
                Text(windowStateLabel)
                    .font(appearance.windowTitleFontSize.font)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .if(!appearance.disableDockStyleTitles) { view in
                        view.materialPill(backgroundAppearance: backgroundAppearance)
                            .frame(height: 34)
                    }
            }
        }
        .fixedSize()

        let controlsGap: CGFloat = (canRenderTrafficLightButtons && showTrafficLights) ? 0 : 8

        let titleContent = HStack(spacing: 4) {
            appIconContent
            titleAndSubtitleContent
        }
        .layoutPriority(1)

        if appearance.controlPosition.isCentered {
            return AnyView(
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    if showTitleContent {
                        titleContent
                    }
                    if showControlsContent { controlsContent }
                    Spacer(minLength: 0)
                }
                .frame(width: dimensions.size.width)
                .animation(nil, value: showTrafficLights)
            )
        } else {
            return AnyView(
                HStack(spacing: 0) {
                    if isLeadingControls {
                        if showControlsContent { controlsContent }
                        Spacer(minLength: controlsGap)
                        if showTitleContent { titleContent }
                    } else {
                        if showTitleContent { titleContent }
                        Spacer(minLength: controlsGap)
                        if showControlsContent { controlsContent }
                    }
                }
                .frame(width: dimensions.size.width)
                .animation(nil, value: showTrafficLights)
            )
        }
    }

    private func dockPreviewContent(_ selected: Bool, isLeadingControls: Bool, showTitleContent: Bool = true, showControlsContent: Bool = true) -> some View {
        // Determine what title to show: window name first, then app name as fallback
        let titleToShow: String? = if let windowTitle = windowInfo.windowName, !windowTitle.isEmpty {
            windowTitle
        } else {
            windowInfo.app.localizedName
        }

        let hasTitle = appearance.showWindowTitle &&
            titleToShow != nil &&
            (appearance.windowTitleVisibility == .alwaysVisible || selected)

        let hasTrafficLights = canRenderTrafficLightButtons
        let showTrafficLights = shouldShowTrafficLightButtons(
            parentHovered: selected || isHoveringOverDockPeekPreview
        )
        let hasVisibleAdjacentControl = (hasTrafficLights && showTrafficLights) ||
            (!hasTrafficLights && windowStateLabel != nil && appearance.trafficLightVisibility != .never)
        let titleContent = Group {
            if hasTitle, let title = titleToShow {
                titleLabel(title, adaptsToAvailableWidth: true)
                    .font(appearance.windowTitleFontSize.font)
                    .padding(4)
                    .if(!appearance.disableDockStyleTitles) { view in
                        view.materialPill(backgroundAppearance: backgroundAppearance)
                    }
                    .frame(minWidth: 0)
                    .clipped()
            }
        }

        let controlsContent = controlsWithSpaceIndicator(
            controlsAreLeading: isLeadingControls,
            nonAlignmentPadding: 0,
            spacing: controlsSpacing(hasAdjacentControl: hasVisibleAdjacentControl)
        ) {
            if hasTrafficLights {
                TrafficLightButtons(
                    displayMode: appearance.trafficLightVisibility,
                    hoveringOverParentWindow: selected || isHoveringOverDockPeekPreview,
                    onWindowAction: handleWindowAction,
                    pillStyling: !appearance.disableDockStyleTrafficLights,
                    mockPreviewActive: mockPreviewActive,
                    enabledButtons: effectiveTrafficLightButtons,
                    useMonochrome: appearance.useMonochromeTrafficLights,
                    buttonScale: appearance.trafficLightButtonScale,
                    backgroundAppearance: backgroundAppearance
                )
                .frame(width: showTrafficLights ? nil : 0)
                .clipped()
            } else if let windowStateLabel,
                      appearance.trafficLightVisibility != .never
            {
                Text(windowStateLabel)
                    .font(appearance.windowTitleFontSize.font)
                    .italic()
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .if(!appearance.disableDockStyleTitles) { view in
                        view.materialPill(backgroundAppearance: backgroundAppearance)
                            .frame(height: 34)
                    }
            }
        }
        .fixedSize()

        if hasTitle || hasTrafficLights || hasSpaceIndicator {
            if appearance.controlPosition.isCentered {
                return AnyView(
                    HStack(spacing: 4) {
                        Spacer(minLength: 0)
                        if showTitleContent { titleContent }
                        if showControlsContent { controlsContent }
                        Spacer(minLength: 0)
                    }
                    .frame(width: dimensions.size.width)
                    .animation(nil, value: showTrafficLights)
                )
            } else {
                return AnyView(
                    HStack(spacing: 0) {
                        if isLeadingControls {
                            if showControlsContent { controlsContent }
                            Spacer(minLength: 8)
                            if showTitleContent { titleContent }
                        } else {
                            if showTitleContent { titleContent }
                            Spacer(minLength: 8)
                            if showControlsContent { controlsContent }
                        }
                    }
                    .frame(width: dimensions.size.width)
                    .animation(nil, value: showTrafficLights)
                )
            }
        } else {
            return AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private var previewCoreContent: some View {
        let finalIsSelected = isSelected

        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if !appearance.useEmbeddedElements || windowSwitcherActive,
                   appearance.controlPosition.showsOnTop
                {
                    let config = appearance.controlPosition.topConfiguration
                    Group {
                        if windowSwitcherActive {
                            windowSwitcherContent(finalIsSelected, isLeadingControls: config.isLeadingControls, showTitleContent: config.showTitle, showControlsContent: config.showControls)
                        } else {
                            dockPreviewContent(finalIsSelected, isLeadingControls: config.isLeadingControls, showTitleContent: config.showTitle, showControlsContent: config.showControls)
                        }
                    }
                    .padding(.bottom, 4)
                }

                windowContent(
                    isMinimized: windowInfo.isMinimized,
                    isHidden: isEffectivelyHidden,
                    isSelected: finalIsSelected
                )

                if !appearance.useEmbeddedElements || windowSwitcherActive,
                   appearance.controlPosition.showsOnBottom
                {
                    let config = appearance.controlPosition.bottomConfiguration
                    Group {
                        if windowSwitcherActive {
                            windowSwitcherContent(finalIsSelected, isLeadingControls: config.isLeadingControls, showTitleContent: config.showTitle, showControlsContent: config.showControls)
                        } else {
                            dockPreviewContent(finalIsSelected, isLeadingControls: config.isLeadingControls, showTitleContent: config.showTitle, showControlsContent: config.showControls)
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: dimensions.maxDimensions.width > 0 ? dimensions.maxDimensions.width : nil)
            .background {
                let cornerRadius = uniformCardRadius ? CardRadius.base + (CardRadius.innerPadding * appearance.globalPaddingMultiplier) : 8.0

                if !appearance.hidePreviewCardBackground {
                    BlurView(cornerRadius: cornerRadius, appearance: backgroundAppearance)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .borderedBackground(.primary.opacity(0.1), lineWidth: 1.75, cornerRadius: cornerRadius)
                        .padding(-CardRadius.innerPadding)
                        .overlay {
                            if finalIsSelected {
                                let highlightColor = appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor)
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .fill(highlightColor.opacity(appearance.selectionOpacity))
                                    .padding(-CardRadius.innerPadding)
                            }
                        }
                        .overlay {
                            if isActiveWindow {
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .strokeBorder(appearance.activeAppIndicatorColor, lineWidth: 2.5)
                                    .padding(-CardRadius.innerPadding)
                            }
                        }
                }
            }
        }
        .overlay {
            if isDraggingOver {
                let dragRadius = uniformCardRadius ? CardRadius.base + (CardRadius.innerPadding * appearance.globalPaddingMultiplier) : CardRadius.fallback
                RoundedRectangle(cornerRadius: dragRadius)
                    .fill(Color(nsColor: .controlAccentColor).opacity(0.3))
                    .padding(-CardRadius.innerPadding)
                    .opacity(highlightOpacity)
            }

            if !windowSwitcherActive, appearance.useEmbeddedElements {
                embeddedControlsOverlay(finalIsSelected)
            }
        }
        .onDrop(of: [UTType.item], isTargeted: $isDraggingOver) { providers in
            if !isDraggingOver { return false }
            handleWindowTap()
            return true
        }
        .onChange(of: isDraggingOver) { isOver in
            if isOver {
                startDragTimer()
            } else {
                cancelDragTimer()
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if isDraggingOver { return }

            let setHoverState: (Bool) -> Void = { newState in
                if appearance.showAnimations {
                    withAnimation(.snappy(duration: 0.175)) {
                        if windowSwitcherActive { isHoveringOverWindowSwitcherPreview = newState }
                        else { isHoveringOverDockPeekPreview = newState }
                    }
                } else {
                    if windowSwitcherActive { isHoveringOverWindowSwitcherPreview = newState }
                    else { isHoveringOverDockPeekPreview = newState }
                }
            }

            let currentHoverState = windowSwitcherActive ? isHoveringOverWindowSwitcherPreview : isHoveringOverDockPeekPreview

            switch phase {
            case let .active(location):
                if !currentHoverState { setHoverState(true) }
                onHoverIndexChange?(index, location)
            case .ended:
                onHoverIndexChange?(nil, nil)
                if currentHoverState {
                    setHoverState(false)
                }
            }
        }
    }

    var body: some View {
        previewCoreContent
            .windowPreviewInteractions(
                windowInfo: windowInfo,
                windowSwitcherActive: windowSwitcherActive,
                dockPosition: dockPosition,
                handleWindowAction: handleWindowAction,
                onTap: onTap
            )
            .fixedSize()
            .opacity(skeletonMode ? 0 : 1)
            .allowsHitTesting(!skeletonMode)
    }

    private func handleWindowTap() {
        if windowInfo.isMinimized {
            handleWindowAction(.minimize)
        } else if isEffectivelyHidden {
            handleWindowAction(.hide)
        } else {
            windowInfo.bringToFront()
            onTap?()
        }
    }

    private func startDragTimer() {
        dragTimer?.invalidate()
        highlightOpacity = 1.0
        dragTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.08)) { highlightOpacity = 0.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeInOut(duration: 0.08)) { highlightOpacity = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.easeInOut(duration: 0.08)) { highlightOpacity = 0.0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.easeInOut(duration: 0.08)) { highlightOpacity = 1.0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            cancelDragTimer()
                            handleWindowTap()
                        }
                    }
                }
            }
        }
    }

    private func cancelDragTimer() {
        dragTimer?.invalidate()
        dragTimer = nil
        isDraggingOver = false
        highlightOpacity = 0.0
    }
}
