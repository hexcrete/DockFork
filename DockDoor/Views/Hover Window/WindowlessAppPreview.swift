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
    let onHoverIndexChange: ((Int?, CGPoint?) -> Void)?
    var appearance: PreviewAppearanceSettings
    let backgroundAppearance: BackgroundAppearance

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
        appearance.enabledTrafficLightButtons.intersection([.quit])
    }

    private var canRenderTrafficLightButtons: Bool {
        appearance.trafficLightVisibility != .never && !windowlessEnabledButtons.isEmpty
    }

    private func titleBar(isLeadingControls: Bool, showTitleContent: Bool = true, showControlsContent: Bool = true) -> some View {
        let shouldShowSubtitle = appearance.showWindowTitle &&
            (appearance.windowTitleVisibility == .alwaysVisible || isSelected || isHovering)
        let showTrafficLightButtons = appearance.trafficLightVisibility.isVisible(
            hoveringOverParentWindow: isSelected || isHovering,
            mockPreviewActive: mockPreviewActive
        )

        let controlsContent = Group {
            if showControlsContent, canRenderTrafficLightButtons {
                TrafficLightButtons(
                    displayMode: appearance.trafficLightVisibility,
                    hoveringOverParentWindow: isSelected || isHovering,
                    onWindowAction: handleTrafficLightAction,
                    pillStyling: !appearance.disableDockStyleTrafficLights,
                    mockPreviewActive: mockPreviewActive,
                    enabledButtons: windowlessEnabledButtons,
                    useMonochrome: appearance.useMonochromeTrafficLights,
                    buttonScale: appearance.trafficLightButtonScale,
                    backgroundAppearance: backgroundAppearance
                )
                .frame(width: showTrafficLightButtons ? nil : 0)
                .clipped()
            }
        }

        return HStack(spacing: 4) {
            if appearance.controlPosition.isCentered {
                Spacer(minLength: 0)
                if showTitleContent {
                    appIcon
                    titleContent(showSubtitle: shouldShowSubtitle)
                }
                controlsContent
                Spacer(minLength: 0)
            } else if isLeadingControls {
                controlsContent
                Spacer(minLength: 8)
                if showTitleContent {
                    appIcon
                    titleContent(showSubtitle: shouldShowSubtitle)
                }
            } else {
                if showTitleContent {
                    appIcon
                    titleContent(showSubtitle: shouldShowSubtitle)
                }
                Spacer(minLength: 0)
                controlsContent
            }
        }
        .animation(nil, value: showTrafficLightButtons)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let appIcon = windowInfo.app.icon {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 35, height: 35)
        }
    }

    private func titleContent(showSubtitle: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(appName)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if showSubtitle {
                Text(String(localized: "No Open Windows", comment: "Label for running apps without any open windows in the window switcher"))
                    .font(appearance.windowTitleFontSize.font)
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(1)
            }
        }
        .padding(.trailing, 8)
    }

    private func handleTrafficLightAction(_ action: WindowAction) {
        switch action {
        case .quit:
            handleWindowAction(.quit)
        default:
            break
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appearance.controlPosition.showsOnTop {
                let config = appearance.controlPosition.topConfiguration
                if config.showTitle || (config.showControls && canRenderTrafficLightButtons) {
                    titleBar(
                        isLeadingControls: config.isLeadingControls,
                        showTitleContent: config.showTitle,
                        showControlsContent: config.showControls
                    )
                    .padding(.bottom, 4)
                }
            }

            iconContent
                .clipShape(RoundedRectangle(cornerRadius: CardRadius.image, style: .continuous))
                .dynamicWindowFrame(
                    allowDynamicSizing: false,
                    dimensions: dimensions ?? WindowPreviewHoverContainer.WindowDimensions(size: .zero, maxDimensions: .zero),
                    dockPosition: dockPosition,
                    windowSwitcherActive: windowSwitcherActive
                )
                .opacity(isSelected ? 1.0 : appearance.unselectedContentOpacity)

            if appearance.controlPosition.showsOnBottom {
                let config = appearance.controlPosition.bottomConfiguration
                if config.showTitle || (config.showControls && canRenderTrafficLightButtons) {
                    titleBar(
                        isLeadingControls: config.isLeadingControls,
                        showTitleContent: config.showTitle,
                        showControlsContent: config.showControls
                    )
                    .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: (dimensions?.maxDimensions.width ?? 0) > 0 ? dimensions!.maxDimensions.width : nil)
        .background {
            let cornerRadius = uniformCardRadius ? CardRadius.base + (CardRadius.innerPadding * appearance.globalPaddingMultiplier) : 8.0

            if !appearance.hidePreviewCardBackground {
                BlurView(cornerRadius: cornerRadius, appearance: backgroundAppearance)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .borderedBackground(.primary.opacity(0.1), lineWidth: 1.75, cornerRadius: cornerRadius)
                    .padding(-CardRadius.innerPadding)
                    .overlay {
                        if isSelected {
                            let highlightColor = appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor)
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(highlightColor.opacity(appearance.selectionOpacity))
                                .padding(-CardRadius.innerPadding)
                        }
                    }
            }
        }
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
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.shift) {
                WindowUtil.activateAndOpenNewWindow(app: windowInfo.app)
                onTap?()
                return
            }

            WindowUtil.activateWindowlessApp(app: windowInfo.app)
            onTap?()
        }
        .contextMenu {
            Button(action: {
                handleWindowAction(.openNewWindow)
            }) {
                Label(
                    String(localized: "Open New Window", comment: "Context menu action to open a new window for the app"),
                    systemImage: "plus.rectangle.on.rectangle"
                )
            }

            Divider()

            Button(role: .destructive, action: {
                handleTrafficLightAction(.quit)
            }) {
                if NSEvent.modifierFlags.contains(.option) {
                    Label("Force Quit", systemImage: "power")
                } else {
                    Label("Quit", systemImage: "minus.square.fill")
                }
            }
        }
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
