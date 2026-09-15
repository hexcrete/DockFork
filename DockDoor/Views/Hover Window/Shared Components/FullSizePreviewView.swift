import Defaults
import SwiftUI

struct FullSizePreviewView: View {
    private static let standardWindowCornerRadius: CGFloat = 16

    let windowInfo: WindowInfo
    let windowSize: CGSize
    @Default(.enableLivePreview) var enableLivePreview
    @Default(.enableLivePreviewForDock) var enableLivePreviewForDock
    @Default(.dockLivePreviewQuality) var dockLivePreviewQuality
    @Default(.dockLivePreviewFrameRate) var dockLivePreviewFrameRate
    @Default(.fullSizePreviewOpacity) var fullSizePreviewOpacity
    @Default(.enableFullSizePreviewBackdropBlur) var enableFullSizePreviewBackdropBlur
    @Default(.showFullSizePreviewBorder) var showFullSizePreviewBorder
    @Default(.activeAppIndicatorColor) var activeAppIndicatorColor

    private var borderCornerRadius: CGFloat {
        windowInfo.isFullscreen == true ? 0 : Self.standardWindowCornerRadius
    }

    var body: some View {
        let useLivePreview = enableLivePreview &&
            enableLivePreviewForDock &&
            !windowInfo.isMinimized &&
            !windowInfo.isEffectivelyHiddenForUI

        ZStack {
            if enableFullSizePreviewBackdropBlur {
                if #available(macOS 26.0, *) {
                    LiquidGlassRepresentable(
                        cornerRadius: borderCornerRadius,
                        glassOpacity: 1,
                        tintOpacity: 0,
                        blurRadius: 20,
                        saturation: 1,
                        variant: 4
                    )
                } else {
                    MaterialBlurView(material: .hudWindow)
                }
            }

            if fullSizePreviewOpacity > 0 {
                Group {
                    if useLivePreview {
                        LivePreviewImage(windowID: windowInfo.id, fallbackImage: windowInfo.image, quality: dockLivePreviewQuality, frameRate: dockLivePreviewFrameRate)
                            .aspectRatio(windowSize, contentMode: .fit)
                    } else if let image = windowInfo.image {
                        Image(decorative: image, scale: 1.0)
                            .resizable()
                            .aspectRatio(windowSize, contentMode: .fit)
                    }
                }
                .opacity(fullSizePreviewOpacity)
            }
        }
        .frame(width: windowSize.width, height: windowSize.height)
        .clipShape(RoundedRectangle(cornerRadius: borderCornerRadius, style: .continuous))
        .overlay {
            if showFullSizePreviewBorder {
                RoundedRectangle(cornerRadius: borderCornerRadius, style: .continuous)
                    .strokeBorder(activeAppIndicatorColor, lineWidth: 2.5)
            }
        }
    }
}
