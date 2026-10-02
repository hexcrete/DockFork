import SwiftUI

struct MaterialPillStyle: ViewModifier {
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 5

    let backgroundAppearance: BackgroundAppearance
    let highlightColor: Color?
    let highlightOpacity: Double

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background {
                ZStack {
                    BlurView(appearance: backgroundAppearance)
                    if let highlightColor {
                        highlightColor.opacity(highlightOpacity)
                    }
                }
            }
            .clipShape(Capsule(style: .continuous))
            .borderedBackground(
                .white.opacity(backgroundAppearance.borderOpacity),
                lineWidth: backgroundAppearance.borderWidth,
                shape: Capsule(style: .continuous)
            )
    }
}

extension View {
    func materialPill(
        backgroundAppearance: BackgroundAppearance,
        highlightColor: Color? = nil,
        highlightOpacity: Double = 0
    ) -> some View {
        modifier(MaterialPillStyle(
            backgroundAppearance: backgroundAppearance,
            highlightColor: highlightColor,
            highlightOpacity: highlightOpacity
        ))
    }
}
