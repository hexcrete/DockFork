import Defaults
import ScreenCaptureKit
import SwiftUI

struct TrafficLightButtons: View {
    static let actionOrder: [WindowAction] = [.quit, .close, .minimize, .toggleFullScreen, .maximize, .bringToCurrentSpace, .openNewWindow]

    static let buttonFrameSize: CGFloat = 17
    static let contentPadding: CGFloat = 4
    private static let buttonSpacing: CGFloat = 6

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let displayMode: TrafficLightButtonsVisibility
    let hoveringOverParentWindow: Bool
    let onWindowAction: (WindowAction) -> Void
    let pillStyling: Bool
    let mockPreviewActive: Bool
    let enabledButtons: Set<WindowAction>
    let useMonochrome: Bool
    var buttonScale: CGFloat = 1.0
    let backgroundAppearance: BackgroundAppearance
    var windowInfo: WindowInfo? = nil
    @State private var isHovering = false

    var body: some View {
        let selectedTargets = !mockPreviewActive && (hoveringOverParentWindow || isHovering)
            ? windowInfo.flatMap { SharedPreviewWindowCoordinator.activeInstance?.windowSwitcherCoordinator.checkedActionTargets(for: $0, includingWindowlessApps: true) }
            : nil
        Group {
            if displayMode != .never {
                HStack(spacing: Self.buttonSpacing) {
                    ForEach(Self.actionOrder.filter(enabledButtons.contains), id: \.self) { action in
                        Group {
                            switch action {
                            case .quit:
                                buttonFor(action: .quit, symbol: "power",
                                          color: Color(red: 0.29, green: 0.01, blue: 0.10),
                                          fillColor: Color(red: 0.88, green: 0.22, blue: 0.42))
                            case .close:
                                buttonFor(action: .close, symbol: "xmark",
                                          color: Color(red: 0.49, green: 0.02, blue: 0.04),
                                          fillColor: Color(red: 1.00, green: 0.30, blue: 0.28))
                            case .minimize:
                                buttonFor(action: .minimize, symbol: "minus",
                                          color: Color(red: 0.60, green: 0.34, blue: 0.07),
                                          fillColor: Color(red: 1.00, green: 0.80, blue: 0.20))
                            case .toggleFullScreen:
                                buttonFor(action: .toggleFullScreen, symbol: "arrow.up.left.and.arrow.down.right",
                                          color: Color(red: 0.05, green: 0.40, blue: 0.05),
                                          fillColor: Color(red: 0.26, green: 0.84, blue: 0.36))
                            case .maximize:
                                buttonFor(action: .maximize, symbol: "arrow.up.to.line",
                                          color: Color(red: 0.07, green: 0.22, blue: 0.32),
                                          fillColor: Color(red: 0.25, green: 0.52, blue: 0.72))
                            case .bringToCurrentSpace:
                                buttonFor(action: .bringToCurrentSpace, symbol: "arrow.right",
                                          color: Color(red: 0.02, green: 0.24, blue: 0.32),
                                          fillColor: Color(red: 0.08, green: 0.62, blue: 0.86))
                            case .openNewWindow:
                                buttonFor(action: .openNewWindow, symbol: "plus",
                                          color: Color(red: 0.04, green: 0.16, blue: 0.40),
                                          fillColor: Color(red: 0.42, green: 0.60, blue: 0.98))
                            default: EmptyView()
                            }
                        }
                        .help(windowInfo.map { action.menuTitle(for: $0, batchTargets: selectedTargets) } ?? action.localizedName)
                    }
                }
                .padding(Self.contentPadding)
                .opacity(buttonOpacity)
                .simultaneousGesture(TapGesture())
                .onHover { isHovering in
                    withAnimation(PreviewControlAnimation.animation(
                        duration: Defaults[.trafficLightTransitionDuration],
                        animationsEnabled: Defaults[.showAnimations],
                        reduceMotion: reduceMotion
                    )) {
                        self.isHovering = isHovering
                    }
                }
            }
        }
        .if(pillStyling && displayMode != .never && !enabledButtons.isEmpty) { view in
            view.materialPill(backgroundAppearance: backgroundAppearance)
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .contentShape(Rectangle())
    }

    private var isVisible: Bool {
        displayMode.isVisible(
            hoveringOverParentWindow: hoveringOverParentWindow
        )
    }

    private var buttonOpacity: Double {
        switch displayMode {
        case .dimmedOnPreviewHover, .dimmedUntilButtonHover:
            isHovering || mockPreviewActive ? 1 : 0.25
        case .fullOpacityOnPreviewHover, .alwaysVisible:
            1
        case .never:
            0
        }
    }

    private func buttonFor(action: WindowAction, symbol: String, color: Color, fillColor: Color) -> some View {
        let monochromeFillColor = colorScheme == .dark ? Color.gray.opacity(0.85) : Color.white
        return ZStack {
            TrafficLightOrb(base: useMonochrome ? monochromeFillColor : fillColor, diameter: Self.glyphFontSize * 1.0385)
            Image(systemName: "\(symbol).circle.fill")
                .font(.system(size: Self.glyphFontSize, weight: .bold))
                .foregroundStyle(useMonochrome ? AnyShapeStyle(.secondary) : AnyShapeStyle(color), .clear)
        }
        .scaleEffect(buttonScale)
        .frame(width: Self.buttonFrameSize * buttonScale, height: Self.buttonFrameSize * buttonScale)
        .contentShape(Rectangle())
        .onTapGesture {
            onWindowAction(action)
        }
    }

    private static let glyphFontSize: CGFloat = 13

    static func controlHeight(buttonScale: CGFloat, pillStyling: Bool) -> CGFloat {
        let contentHeight = buttonFrameSize * buttonScale + 2 * contentPadding
        return contentHeight + (pillStyling ? 2 * MaterialPillStyle.verticalPadding : 0)
    }

    static func controlWidth(buttonCount: Int, buttonScale: CGFloat, pillStyling: Bool) -> CGFloat {
        CGFloat(buttonCount) * buttonFrameSize * buttonScale + CGFloat(max(0, buttonCount - 1)) * buttonSpacing +
            2 * contentPadding + (pillStyling ? 2 * MaterialPillStyle.horizontalPadding : 0)
    }

    static func partialOverflowCounts(for actions: Set<WindowAction>, buttonScale: CGFloat,
                                      pillStyling: Bool, spacing: CGFloat) -> [Int]
    {
        let count = actionOrder.filter(actions.contains).count
        guard count > 1 else { return [] }
        let fullWidth = controlWidth(buttonCount: count, buttonScale: buttonScale, pillStyling: pillStyling)
        let menuWidth = controlWidth(buttonCount: 1, buttonScale: buttonScale, pillStyling: pillStyling)
        // A separate More control must save space before it becomes a fitting candidate.
        return stride(from: count - 1, through: 1, by: -1).filter {
            controlWidth(buttonCount: $0, buttonScale: buttonScale, pillStyling: pillStyling) + spacing + menuWidth < fullWidth
        }
    }
}

struct TrafficLightOrb: View {
    let base: Color
    let diameter: CGFloat

    private static let bodyShading = 0.16

    private static let rimStops: [Gradient.Stop] = [
        .init(color: .white.opacity(0.72), location: 0.00),
        .init(color: .white.opacity(0.66), location: 0.03),
        .init(color: .white.opacity(0.48), location: 0.07),
        .init(color: .white.opacity(0.28), location: 0.15),
        .init(color: .white.opacity(0.15), location: 0.25),
        .init(color: .white.opacity(0.04), location: 0.37),
        .init(color: .white.opacity(0.00), location: 0.50),
        .init(color: .white.opacity(0.03), location: 0.63),
        .init(color: .white.opacity(0.12), location: 0.75),
        .init(color: .white.opacity(0.23), location: 0.85),
        .init(color: .white.opacity(0.40), location: 0.93),
        .init(color: .white.opacity(0.55), location: 0.97),
        .init(color: .white.opacity(0.60), location: 1.00),
    ]

    private static let specularRim = LinearGradient(stops: rimStops, startPoint: .top, endPoint: .bottom)

    var body: some View {
        Circle()
            .fill(bodyGradient)
            .overlay {
                Circle()
                    .strokeBorder(Self.specularRim, lineWidth: max(0.5, diameter / 14))
            }
            .frame(width: diameter, height: diameter)
    }

    private var bodyGradient: LinearGradient {
        LinearGradient(
            colors: [base.shaded(by: -Self.bodyShading), base.shaded(by: Self.bodyShading)],
            startPoint: UnitPoint(x: 0.5, y: 0.25),
            endPoint: UnitPoint(x: 0.5, y: 0.75)
        )
    }
}

extension AppearanceSettingsView {
    struct TrafficLightButtonsSettingsView: View {
        @Default(.enabledTrafficLightButtons) private var enabledButtons
        @Default(.useMonochromeTrafficLights) private var useMonochrome
        @Default(.trafficLightButtonsVisibility) private var trafficLightButtonsVisibility
        @Default(.trafficLightButtonScale) private var buttonScale

        private let buttonDescriptions: [(WindowAction, String)] = [
            (.quit, String(localized: "Quit")),
            (.close, String(localized: "Close")),
            (.minimize, String(localized: "Minimize")),
            (.toggleFullScreen, String(localized: "Fullscreen")),
            (.maximize, String(localized: "Maximize")),
            (.bringToCurrentSpace, String(localized: "Bring to Current Space")),
            (.openNewWindow, String(localized: "New Window")),
        ]

        private var buttonRows: [[(WindowAction, String)]] {
            stride(from: 0, to: buttonDescriptions.count, by: 3).map { start in
                Array(buttonDescriptions[start ..< min(start + 3, buttonDescriptions.count)])
            }
        }

        var body: some View {
            Picker("Traffic Light Buttons Visibility", selection: $trafficLightButtonsVisibility) {
                ForEach(TrafficLightButtonsVisibility.allCases, id: \.self) { visibility in
                    Text(visibility.localizedName)
                        .tag(visibility)
                }
            }

            if trafficLightButtonsVisibility != .never {
                Group {
                    Text("Enabled Buttons")
                    VStack(alignment: .leading) {
                        if !enabledButtons.isEmpty {
                            TrafficLightButtons(
                                displayMode: trafficLightButtonsVisibility == .never ? .dimmedOnPreviewHover : trafficLightButtonsVisibility,
                                hoveringOverParentWindow: true,
                                onWindowAction: { _ in },
                                pillStyling: true,
                                mockPreviewActive: false,
                                enabledButtons: enabledButtons,
                                useMonochrome: useMonochrome,
                                buttonScale: buttonScale,
                                backgroundAppearance: .resolve()
                            )
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(buttonRows.indices, id: \.self) { rowIndex in
                                HStack(spacing: 12) {
                                    ForEach(buttonRows[rowIndex], id: \.0) { action, label in
                                        Toggle(isOn: Binding(
                                            get: { enabledButtons.contains(action) },
                                            set: { isEnabled in
                                                if isEnabled {
                                                    enabledButtons.insert(action)
                                                } else {
                                                    enabledButtons.remove(action)

                                                    if enabledButtons.isEmpty {
                                                        MessageUtil.showAlert(
                                                            title: String(localized: "All buttons removed"),
                                                            message: String(localized: "Your traffic lights will be set to disabled automatically."),
                                                            actions: [.ok, .cancel]
                                                        ) { action in
                                                            switch action {
                                                            case .ok:
                                                                trafficLightButtonsVisibility = .never
                                                            case .cancel:
                                                                break
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        )) {
                                            Text(label)
                                        }
                                        .toggleStyle(CheckboxToggleStyle())
                                    }
                                }
                            }
                        }
                    }

                    Toggle("Use Monochrome Colors", isOn: $useMonochrome)
                        .padding(.top, 4)
                }
            }
        }
    }
}
