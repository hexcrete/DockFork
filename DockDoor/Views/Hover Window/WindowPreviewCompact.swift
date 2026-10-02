import Defaults
import SwiftUI

private struct CompactRowContentClip: Shape {
    let trailingOverflow: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width + trailingOverflow,
            height: rect.height
        ))
    }
}

struct WindowPreviewCompact: View, Equatable {
    let windowInfo: WindowInfo
    let index: Int
    let dockPosition: DockPosition
    let uniformCardRadius: Bool
    let handleWindowAction: (WindowAction) -> Void
    let isSelected: Bool
    let windowSwitcherActive: Bool
    let mockPreviewActive: Bool
    let onTap: (() -> Void)?
    let onHoverIndexChange: ((Int?, CGPoint?) -> Void)?
    let onDragHoverIndexChange: ((Int?) -> Void)?
    let widthOverride: CGFloat?
    var appearance: PreviewAppearanceSettings
    let backgroundAppearance: BackgroundAppearance
    let focusedWindowID: CGWindowID?
    let currentSpaceNumbers: Set<Int>

    @State private var isHovering = false

    private var isHighlighted: Bool {
        isSelected
    }

    static func == (l: Self, r: Self) -> Bool {
        l.index == r.index && l.isSelected == r.isSelected
            && l.uniformCardRadius == r.uniformCardRadius
            && l.windowSwitcherActive == r.windowSwitcherActive
            && l.widthOverride == r.widthOverride
            && l.appearance == r.appearance
            && l.windowInfo.viewSnapshot == r.windowInfo.viewSnapshot
            && l.backgroundAppearance == r.backgroundAppearance
            && l.focusedWindowID == r.focusedWindowID
            && l.currentSpaceNumbers == r.currentSpaceNumbers
    }

    private var rowWidth: CGFloat {
        widthOverride ?? appearance.compactModeWidth
    }

    private var effectiveTrafficLightButtons: Set<WindowAction> {
        resolvedTrafficLightButtons(
            for: windowInfo,
            configuredButtons: appearance.enabledTrafficLightButtons,
            showWindowlessQuitButton: appearance.showWindowlessAppQuitButton
        )
    }

    private var canRenderTrafficLightButtons: Bool {
        appearance.trafficLightVisibility != .never &&
            !effectiveTrafficLightButtons.isEmpty
    }

    /// Checks if this window is the currently active (focused) window on the system and adds a border if so.
    private var isActiveWindow: Bool {
        guard appearance.showActiveWindowBorder else { return false }
        guard windowInfo.app.isActive else { return false }
        return windowInfo.id == focusedWindowID
    }

    private var appName: String {
        windowInfo.app.localizedName ?? "Unknown"
    }

    private var windowTitle: String? {
        let title = windowInfo.windowName ?? ""
        if title.isEmpty || title == appName {
            return nil
        }
        return title
    }

    private var stateIndicator: String? {
        if windowInfo.isWindowlessApp {
            return String(localized: "No Open Windows", comment: "Label for running apps without any open windows in the window switcher")
        }
        guard appearance.windowStateIndicatorPlacement == .onWindowPreviews else { return nil }
        if windowInfo.isMinimized {
            return String(localized: "Minimized", comment: "Window state label")
        } else if windowInfo.isEffectivelyHiddenForUI {
            return String(localized: "Hidden", comment: "Window state label")
        } else if windowInfo.isFullscreen == true {
            return String(localized: "Full Screen", comment: "Window state label")
        }
        return nil
    }

    private var secondaryStateIndicator: String? {
        stateIndicator
    }

    private var windowStateSymbols: [String] {
        WindowStateSymbolResolver.symbols(
            for: windowInfo,
            isEffectivelyHidden: windowInfo.isEffectivelyHiddenForUI
        )
    }

    private var movesWindowStateToIndicator: Bool {
        appearance.windowStateIndicatorPlacement == .nextToTrafficLightButtons &&
            !windowStateSymbols.isEmpty
    }

    private var indicatorStateSymbols: [String] {
        movesWindowStateToIndicator ? windowStateSymbols : []
    }

    private var hasWindowStateIndicator: Bool {
        (appearance.showSpaceNumberIndicator && windowInfo.spaceNumber != nil) || !indicatorStateSymbols.isEmpty
    }

    @ViewBuilder
    private var windowStateIndicator: some View {
        let spaceNumber = appearance.showSpaceNumberIndicator ? windowInfo.spaceNumber : nil
        if spaceNumber != nil || !indicatorStateSymbols.isEmpty {
            SpaceMoveIndicatorControl(
                window: windowInfo,
                spaceNumber: spaceNumber,
                isEnabled: appearance.enableSpaceIndicatorWindowMoving && !mockPreviewActive,
                dismissPreviews: onTap
            ) {
                WindowStateIndicator(
                    number: spaceNumber,
                    stateSymbols: indicatorStateSymbols,
                    disableDockStyling: appearance.disableDockStyleWindowStateIndicator,
                    backgroundAppearance: backgroundAppearance,
                    highlightsCurrentSpace: appearance.highlightCurrentSpaceNumberIndicator &&
                        spaceNumber.map(currentSpaceNumbers.contains) == true,
                    highlightColor: appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor),
                    highlightOpacity: appearance.selectionOpacity,
                    activeBorderColor: appearance.activeAppIndicatorColor
                )
            }
        }
    }

    @ViewBuilder
    private func trafficLightButtons(isVisible: Bool) -> some View {
        if !appearance.compactModeHideTrafficLights,
           canRenderTrafficLightButtons
        {
            TrafficLightButtons(
                previewAppearance: appearance,
                hoveringOverParentWindow: isSelected || isHovering,
                onWindowAction: handleWindowAction,
                mockPreviewActive: mockPreviewActive,
                enabledButtons: effectiveTrafficLightButtons,
                backgroundAppearance: backgroundAppearance
            )
            .frame(width: isVisible ? nil : 0)
            .clipped()
        }
    }

    var body: some View {
        let showTrafficLightButtons = appearance.trafficLightVisibility.isVisible(
            hoveringOverParentWindow: isSelected || isHovering,
            mockPreviewActive: mockPreviewActive
        )
        let hasVisibleTrafficLightButtons = !appearance.compactModeHideTrafficLights &&
            canRenderTrafficLightButtons && showTrafficLightButtons
        let windowStateIndicatorIsOutermost = hasWindowStateIndicator &&
            (!hasVisibleTrafficLightButtons || appearance.swapTrafficLightsAndWindowStateIndicator)
        let controlsTrailingInset = appearance.compactControlAlignmentEdgeInset(
            hasWindowStateIndicator: hasWindowStateIndicator,
            hasTrafficLightButtons: hasVisibleTrafficLightButtons,
            windowStateIndicatorIsOutermost: windowStateIndicatorIsOutermost
        )
        let controlsSpacing: CGFloat = if hasWindowStateIndicator, hasVisibleTrafficLightButtons {
            appearance.disableDockStyleTrafficLights ? 6 : 8
        } else {
            0
        }

        HStack(spacing: 10) {
            // App icon
            if let appIcon = windowInfo.app.icon {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: appearance.compactModeItemSize.iconSize, height: appearance.compactModeItemSize.iconSize)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: appearance.compactModeItemSize.iconSize, height: appearance.compactModeItemSize.iconSize)
                    .foregroundStyle(.secondary)
            }

            if appearance.showAppHeader {
                // Title content based on format
                VStack(alignment: .leading, spacing: 2) {
                    switch appearance.compactModeTitleFormat {
                    case .appNameAndTitle:
                        titleText(appName, isPrimary: true)
                        if windowInfo.isWindowlessApp, let state = secondaryStateIndicator {
                            stateText(state)
                        } else if let title = windowTitle {
                            HStack(spacing: 0) {
                                if let state = secondaryStateIndicator {
                                    stateText(state)
                                    Text("  \u{2022}  ")
                                        .font(appearance.compactModeItemSize.secondaryFont)
                                        .foregroundStyle(.secondary)
                                }
                                titleText(title, isPrimary: false)
                            }
                        } else if let state = secondaryStateIndicator {
                            stateText(state)
                        }

                    case .titleOnly:
                        titleText(windowInfo.isWindowlessApp ? appName : windowTitle ?? appName, isPrimary: true)
                        if let state = secondaryStateIndicator {
                            stateText(state)
                        }

                    case .appNameOnly:
                        titleText(appName, isPrimary: true)
                        if let state = secondaryStateIndicator {
                            stateText(state)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: controlsSpacing) {
                if appearance.swapTrafficLightsAndWindowStateIndicator {
                    trafficLightButtons(isVisible: showTrafficLightButtons)
                    windowStateIndicator
                } else {
                    windowStateIndicator
                    trafficLightButtons(isVisible: showTrafficLightButtons)
                }
            }
            .padding(.trailing, controlsTrailingInset)
        }
        .animation(nil, value: showTrafficLightButtons)
        .padding(.vertical, 8)
        .frame(width: rowWidth, height: appearance.compactModeItemSize.rowHeight, alignment: .leading)
        .clipShape(CompactRowContentClip(trailingOverflow: max(0, -controlsTrailingInset)))
        .previewCardChrome(
            uniformCardRadius: uniformCardRadius,
            paddingMultiplier: appearance.globalPaddingMultiplier,
            expansionEdges: .horizontal,
            hideBackground: appearance.hidePreviewCardBackground,
            isHighlighted: isHighlighted,
            isActiveWindow: isActiveWindow,
            highlightColor: appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor),
            highlightOpacity: appearance.selectionOpacity,
            activeBorderColor: appearance.activeAppIndicatorColor,
            backgroundAppearance: backgroundAppearance
        )
        .externalDragSpringLoading(
            windowInfo: windowInfo,
            index: index,
            uniformCardRadius: uniformCardRadius,
            appearance: appearance,
            windowSwitcherActive: windowSwitcherActive,
            handleWindowAction: handleWindowAction,
            onTap: onTap,
            onDragHoverIndexChange: onDragHoverIndexChange
        )
        .opacity(isHighlighted ? 1.0 : appearance.unselectedContentOpacity)
        .padding(.horizontal, CardRadius.innerPadding)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            let setHoverState: (Bool) -> Void = { newState in
                if appearance.showAnimations {
                    withAnimation(.snappy(duration: 0.175)) { isHovering = newState }
                } else {
                    isHovering = newState
                }
            }

            switch phase {
            case let .active(location):
                if !isHovering { setHoverState(true) }
                onHoverIndexChange?(index, location)
            case .ended:
                onHoverIndexChange?(nil, nil)
                if isHovering { setHoverState(false) }
            }
        }
        .windowPreviewInteractions(
            windowInfo: windowInfo,
            windowSwitcherActive: windowSwitcherActive,
            dockPosition: dockPosition,
            useCompactMode: true,
            handleWindowAction: handleWindowAction,
            onTap: onTap
        )
        .allowsHitTesting(!mockPreviewActive)
    }

    @ViewBuilder
    private func titleText(_ text: String, isPrimary: Bool) -> some View {
        let font = isPrimary ? appearance.compactModeItemSize.primaryFont : appearance.compactModeItemSize.secondaryFont
        switch appearance.titleOverflowStyle {
        case .marquee:
            MarqueeText(text: text, startDelay: 1, adaptsToAvailableWidth: true)
                .font(font)
                .foregroundStyle(isPrimary ? .primary : .secondary)
        case .truncateTail:
            Text(text).font(font).foregroundStyle(isPrimary ? .primary : .secondary)
                .lineLimit(1).truncationMode(.tail)
        case .truncateMiddle:
            Text(text).font(font).foregroundStyle(isPrimary ? .primary : .secondary)
                .lineLimit(1).truncationMode(.middle)
        case .truncateHead:
            Text(text).font(font).foregroundStyle(isPrimary ? .primary : .secondary)
                .lineLimit(1).truncationMode(.head)
        }
    }

    @ViewBuilder
    private func stateText(_ text: String) -> some View {
        Text(text)
            .font(appearance.compactModeItemSize.secondaryFont)
            .foregroundStyle(.secondary)
            .italic()
    }
}
