import Defaults
import SwiftUI

struct WindowlessAppPreview: View, Equatable {
    let windowInfo: WindowInfo
    let index: Int
    let dockPosition: DockPosition
    let uniformCardRadius: Bool
    let isSelected: Bool
    let windowSwitcherActive: Bool
    let dimensions: WindowPreviewHoverContainer.WindowDimensions?
    let mockPreviewActive: Bool
    let handleWindowAction: (WindowAction) -> Void
    let onTap: (() -> Void)?
    let onHoverIndexChange: ((Int?, CGPoint?) -> Bool)?
    var appearance: PreviewAppearanceSettings
    let backgroundAppearance: BackgroundAppearance

    @Default(.middleClickAction) private var middleClickAction

    @State private var isHovering = false

    static func == (l: Self, r: Self) -> Bool {
        l.index == r.index && l.isSelected == r.isSelected
            && l.uniformCardRadius == r.uniformCardRadius
            && l.dimensions == r.dimensions
            && l.appearance == r.appearance
            && l.windowInfo.viewSnapshot == r.windowInfo.viewSnapshot
            && l.backgroundAppearance == r.backgroundAppearance
    }

    private var appName: String {
        windowInfo.app.localizedName ?? "Unknown"
    }

    private var windowlessEnabledButtons: Set<WindowAction> {
        guard appearance.showWindowlessAppQuitButton else { return [] }
        return appearance.enabledTrafficLightButtons.intersection([.quit])
    }

    private var canRenderTrafficLightButtons: Bool {
        appearance.trafficLightVisibility != .never && !windowlessEnabledButtons.isEmpty
    }

    private var switcherToolbarHorizontalPadding: CGFloat {
        CardRadius.switcherToolbarHorizontalPadding(
            uniformCardRadius: windowSwitcherActive && uniformCardRadius
        )
    }

    private func switcherAppIconSize(hasSecondaryLabel: Bool) -> CGFloat {
        if appearance.switcherAppIconSize > 0 {
            return min(max(appearance.switcherAppIconSize, 16), 64)
        }

        return hasSecondaryLabel ? 35 : 20
    }

    private func toolbarContent(isLeadingControls: Bool, showTitleContent: Bool, showControlsContent: Bool) -> some View {
        let shouldShowSubtitle = appearance.showWindowTitle &&
            (appearance.windowTitleVisibility == .alwaysVisible || isSelected || isHovering)
        let shouldShowTitle = appearance.showAppHeader && showTitleContent
        let shouldShowControls = canRenderTrafficLightButtons && showControlsContent
        let showTrafficLightButtons = appearance.trafficLightVisibility.isVisible(
            hoveringOverParentWindow: isSelected || isHovering
        )
        let titleOnRight = appearance.controlPosition.titleIsTrailing
        let iconOnRight = windowSwitcherActive && titleOnRight

        return HStack(spacing: 4) {
            if appearance.controlPosition.isCentered {
                Spacer(minLength: 0)
                if shouldShowTitle {
                    titleCluster(showSubtitle: shouldShowSubtitle, iconOnRight: false, textOnRight: false)
                }
                if shouldShowControls {
                    quitButton(alignment: .center, isVisible: showTrafficLightButtons)
                }
                Spacer(minLength: 0)
            } else if isLeadingControls {
                if shouldShowControls {
                    quitButton(alignment: .leading, isVisible: showTrafficLightButtons)
                }
                Spacer(minLength: 8)
                if shouldShowTitle {
                    titleCluster(
                        showSubtitle: shouldShowSubtitle,
                        iconOnRight: iconOnRight,
                        textOnRight: titleOnRight
                    )
                }
            } else {
                if shouldShowTitle {
                    titleCluster(
                        showSubtitle: shouldShowSubtitle,
                        iconOnRight: iconOnRight,
                        textOnRight: titleOnRight
                    )
                }
                Spacer(minLength: 0)
                if shouldShowControls {
                    quitButton(alignment: .trailing, isVisible: showTrafficLightButtons)
                }
            }
        }
        .animation(nil, value: showTrafficLightButtons)
    }

    private func titleCluster(showSubtitle: Bool, iconOnRight: Bool, textOnRight: Bool) -> some View {
        PreviewTitleCluster(iconOnRight: iconOnRight) {
            appIcon(hasSecondaryLabel: showSubtitle)
        } labels: {
            titleContent(
                showSubtitle: showSubtitle,
                alignment: textOnRight ? .trailing : .leading
            )
        }
    }

    private func quitButton(alignment: Alignment, isVisible: Bool) -> some View {
        TrafficLightButtons(
            previewAppearance: appearance,
            hoveringOverParentWindow: isSelected || isHovering,
            onWindowAction: handleWindowAction,
            mockPreviewActive: mockPreviewActive,
            enabledButtons: windowlessEnabledButtons,
            backgroundAppearance: backgroundAppearance
        )
        .frame(minWidth: 34, minHeight: 34, alignment: alignment)
        .frame(width: isVisible ? nil : 0)
        .clipped()
        .embeddedPreviewContrastShadow(appearance.usesEmbeddedTrafficLightContrastShadow)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func appIcon(hasSecondaryLabel: Bool) -> some View {
        let appIconSize = switcherAppIconSize(hasSecondaryLabel: hasSecondaryLabel)

        if let appIcon = windowInfo.app.icon {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: appIconSize, height: appIconSize)
        }
    }

    private func titleContent(showSubtitle: Bool, alignment: HorizontalAlignment) -> some View {
        let textAlignment: TextAlignment = alignment == .trailing ? .trailing : .leading
        return VStack(alignment: alignment, spacing: 0) {
            Text(appName)
                .foregroundStyle(.primary)
                .multilineTextAlignment(textAlignment)
                .lineLimit(1)

            if showSubtitle {
                Text(String(localized: "No Open Windows", comment: "Label for running apps without any open windows in the window switcher"))
                    .font(appearance.windowTitleFontSize.font)
                    .foregroundStyle(.secondary)
                    .italic()
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(1)
            }
        }
        .padding(.trailing, 8)
        .embeddedPreviewContrastShadow(appearance.usesEmbeddedTitleContrastShadow)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if !appearance.useEmbeddedElements,
                   appearance.controlPosition.showsOnTop
                {
                    let config = appearance.controlPosition.topConfiguration
                    if (appearance.showAppHeader && config.showTitle) || (canRenderTrafficLightButtons && config.showControls) {
                        toolbarContent(
                            isLeadingControls: config.isLeadingControls,
                            showTitleContent: config.showTitle,
                            showControlsContent: config.showControls
                        )
                        .padding(.horizontal, switcherToolbarHorizontalPadding)
                        .padding(.bottom, 4)
                    }
                }

                iconContent
                    .clipShape(RoundedRectangle(cornerRadius: appearance.radii.image, style: .continuous))
                    .dynamicWindowFrame(
                        allowDynamicSizing: false,
                        dimensions: dimensions ?? WindowPreviewHoverContainer.WindowDimensions(size: .zero, maxDimensions: .zero),
                        dockPosition: dockPosition,
                        windowSwitcherActive: windowSwitcherActive
                    )
                    .opacity(isSelected ? 1.0 : appearance.unselectedContentOpacity)

                if !appearance.useEmbeddedElements,
                   appearance.controlPosition.showsOnBottom
                {
                    let config = appearance.controlPosition.bottomConfiguration
                    if (appearance.showAppHeader && config.showTitle) || (canRenderTrafficLightButtons && config.showControls) {
                        toolbarContent(
                            isLeadingControls: config.isLeadingControls,
                            showTitleContent: config.showTitle,
                            showControlsContent: config.showControls
                        )
                        .padding(.horizontal, switcherToolbarHorizontalPadding)
                        .padding(.top, 4)
                    }
                }
            }

            if appearance.useEmbeddedElements {
                EmbeddedSwitcherControlsLayout(
                    controlPosition: appearance.controlPosition,
                    hasTitleContent: appearance.showAppHeader,
                    hasControlsContent: canRenderTrafficLightButtons
                ) { isLeadingControls, showTitle, showControls in
                    toolbarContent(
                        isLeadingControls: isLeadingControls,
                        showTitleContent: showTitle,
                        showControlsContent: showControls
                    )
                }
            }
        }
        .frame(maxWidth: (dimensions?.maxDimensions.width ?? 0) > 0 ? dimensions!.maxDimensions.width : nil)
        .previewCardChrome(
            uniformCardRadius: uniformCardRadius,
            paddingMultiplier: appearance.globalPaddingMultiplier,
            hideBackground: appearance.hidePreviewCardBackground,
            isHighlighted: isSelected,
            showsHighlightWhenBackgroundHidden: false,
            highlightColor: appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor),
            highlightOpacity: appearance.selectionOpacity,
            activeBorderColor: appearance.activeAppIndicatorColor,
            backgroundAppearance: backgroundAppearance
        )
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
                let shouldShowHover = onHoverIndexChange?(index, location) ?? true
                if isHovering != shouldShowHover { setHoverState(shouldShowHover) }
            case .ended:
                _ = onHoverIndexChange?(nil, nil)
                if isHovering { setHoverState(false) }
            }
        }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.shift) {
                WindowUtil.activateAndOpenNewWindow(app: windowInfo.app)
                onTap?()
                return
            }

            WindowUtil.activateWindowlessApp(app: windowInfo.app)
            onTap?()
        }
        .onMiddleClick {
            if middleClickAction != .none {
                handleWindowAction(middleClickAction)
            }
        }
        .previewContextMenu(
            windowInfo: windowInfo,
            handleWindowAction: handleWindowAction
        )
        .fixedSize()
    }

    @ViewBuilder
    private var iconContent: some View {
        if let appIcon = windowInfo.app.icon {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
        }
    }
}
