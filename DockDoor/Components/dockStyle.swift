import Defaults
import SwiftUI

enum CardRadius {
    static let innerPadding: Double = 6
    static let outerPadding: Double = 20
    static let fallback: Double = 8

    struct Resolved: Equatable {
        let card: Double
        let image: Double
        let container: Double

        init(uniform: Bool, base: Double, paddingMultiplier: Double) {
            guard uniform else {
                card = CardRadius.fallback
                image = CardRadius.fallback
                container = CardRadius.fallback
                return
            }
            card = base + CardRadius.innerPadding * paddingMultiplier
            image = max(0, card - CardRadius.innerPadding)
            container = base + CardRadius.outerPadding * paddingMultiplier
        }

        static func current() -> Resolved {
            Resolved(
                uniform: Defaults[.uniformCardRadius],
                base: Defaults[.previewCornerRadius],
                paddingMultiplier: Defaults[.globalPaddingMultiplier]
            )
        }
    }

    static var inner: Double { Resolved.current().card }
    static var container: Double { Resolved.current().container }
    static var image: Double { Resolved.current().image }
    static func previewCard(uniform: Bool, paddingMultiplier: CGFloat) -> Double {
        Resolved(
            uniform: uniform,
            base: Defaults[.previewCornerRadius],
            paddingMultiplier: Double(paddingMultiplier)
        ).card
    }

    static var containerContentClip: some Shape { containerContentClip(cornerRadius: container) }

    static func containerContentClip(cornerRadius: Double) -> some Shape {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .inset(by: 1)
    }

    static func widgetContentPadding(_ base: CGFloat, cardRadius: Double) -> CGFloat {
        max(base, CGFloat(cardRadius) * 0.3 + 4.5)
    }

    static func switcherToolbarHorizontalPadding(uniformCardRadius: Bool) -> CGFloat {
        guard uniformCardRadius else { return 0 }
        return CGFloat(innerPadding / 2)
    }
}

private struct PreviewCardChromeModifier: ViewModifier {
    @Default(.previewCornerRadius) private var previewCornerRadius

    let uniformCardRadius: Bool
    let paddingMultiplier: CGFloat
    let expansionEdges: Edge.Set
    let hideBackground: Bool
    let isHighlighted: Bool
    let isActiveWindow: Bool
    let showsHighlightWhenBackgroundHidden: Bool
    let highlightColor: Color
    let highlightOpacity: Double
    let activeBorderColor: Color
    let backgroundAppearance: BackgroundAppearance

    private var cornerRadius: Double {
        CardRadius.Resolved(
            uniform: uniformCardRadius,
            base: previewCornerRadius,
            paddingMultiplier: Double(paddingMultiplier)
        ).card
    }

    func body(content: Content) -> some View {
        content.background {
            if !hideBackground {
                BlurView(cornerRadius: cornerRadius, appearance: backgroundAppearance)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .borderedBackground(.primary.opacity(0.1), lineWidth: 1.75, cornerRadius: cornerRadius)
                    .padding(expansionEdges, -CardRadius.innerPadding)
                    .overlay {
                        if isHighlighted {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(highlightColor.opacity(highlightOpacity))
                                .padding(expansionEdges, -CardRadius.innerPadding)
                        }
                    }
                    .overlay {
                        if isActiveWindow {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(activeBorderColor, lineWidth: 2.5)
                                .padding(expansionEdges, -CardRadius.innerPadding)
                        }
                    }
            }

            if hideBackground, showsHighlightWhenBackgroundHidden, isHighlighted {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(highlightColor, lineWidth: 2.5)
                    .padding(expansionEdges, -CardRadius.innerPadding)
            }
        }
    }
}

extension View {
    func previewCardChrome(
        uniformCardRadius: Bool,
        paddingMultiplier: CGFloat,
        expansionEdges: Edge.Set = .all,
        hideBackground: Bool,
        isHighlighted: Bool,
        isActiveWindow: Bool = false,
        showsHighlightWhenBackgroundHidden: Bool = true,
        highlightColor: Color,
        highlightOpacity: Double,
        activeBorderColor: Color,
        backgroundAppearance: BackgroundAppearance
    ) -> some View {
        modifier(PreviewCardChromeModifier(
            uniformCardRadius: uniformCardRadius,
            paddingMultiplier: paddingMultiplier,
            expansionEdges: expansionEdges,
            hideBackground: hideBackground,
            isHighlighted: isHighlighted,
            isActiveWindow: isActiveWindow,
            showsHighlightWhenBackgroundHidden: showsHighlightWhenBackgroundHidden,
            highlightColor: highlightColor,
            highlightOpacity: highlightOpacity,
            activeBorderColor: activeBorderColor,
            backgroundAppearance: backgroundAppearance
        ))
    }
}

struct DockStyleModifier: ViewModifier {
    let backgroundAppearance: BackgroundAppearance
    let cornerRadius: Double
    let highlightColor: Color?
    let backgroundOpacity: CGFloat
    let outerPadding: CGFloat

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    glassBackground
                    if let hc = highlightColor {
                        FluidGradient(blobs: hc.generateShades(count: 3), highlights: hc.generateShades(count: 3), speed: 0.5, blur: 0.75)
                            .opacity(0.2 * backgroundOpacity)
                    }
                }
                .clipShape(shape)
            }
            .padding(outerPadding)
    }

    /// The synthetic blur variant relies on the glass shader's own edge
    /// refraction as its border, so it skips `borderedBackground` (which
    /// insets the content and leaves an un-blurred gap) and uses an overlay
    /// stroke instead.
    @ViewBuilder
    private var glassBackground: some View {
        if #available(macOS 26.0, *), backgroundAppearance.usesModernGlass,
           let rim = LiquidGlass.borderGlass(activeAppearance: backgroundAppearance.glassRefraction)
        {
            BlurView(cornerRadius: cornerRadius, appearance: backgroundAppearance)
                .overlay {
                    Color.clear
                        .glassEffect(rim, in: shape)
                        .opacity(0.5)
                        .allowsHitTesting(false)
                }
                .opacity(backgroundOpacity)
        } else if backgroundAppearance.usesSyntheticBlur {
            BlurView(cornerRadius: cornerRadius, appearance: backgroundAppearance)
                .overlay {
                    shape.strokeBorder(
                        glassBorderGradient(opacity: backgroundAppearance.borderOpacity),
                        lineWidth: backgroundAppearance.borderWidth
                    )
                }
                .opacity(backgroundOpacity)
        } else {
            BlurView(cornerRadius: cornerRadius, appearance: backgroundAppearance)
                .borderedBackground(
                    glassBorderGradient(opacity: backgroundAppearance.borderOpacity),
                    lineWidth: backgroundAppearance.borderWidth,
                    shape: shape
                )
                .opacity(backgroundOpacity)
        }
    }
}

// Directional rim-light stroke that reads as lit glass rather than a flat
// outline. Stops match Docky's dock chrome at the default border opacity and
// scale together as the user's borderOpacity knob changes.
private func glassBorderGradient(opacity: CGFloat) -> LinearGradient {
    let scale = opacity / 0.15
    return LinearGradient(
        colors: [
            .white.opacity(0.35 * scale),
            .white.opacity(0.12 * scale),
            .white.opacity(0.05 * scale),
            .white.opacity(0.12 * scale),
            .white.opacity(0.28 * scale),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension View {
    func dockStyle(
        backgroundAppearance: BackgroundAppearance,
        cornerRadius: Double = CardRadius.Resolved.current().container,
        highlightColor: Color? = nil,
        backgroundOpacity: CGFloat = 1.0,
        outerPadding: CGFloat = HoverContainerPadding.dockStyleOuter
    ) -> some View {
        modifier(DockStyleModifier(
            backgroundAppearance: backgroundAppearance,
            cornerRadius: cornerRadius,
            highlightColor: highlightColor,
            backgroundOpacity: backgroundOpacity,
            outerPadding: outerPadding
        ))
    }
}
