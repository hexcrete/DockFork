import SwiftUI

struct PreviewPlaceholderImage: View {
    let appIcon: NSImage?

    var body: some View {
        if let appIcon {
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
