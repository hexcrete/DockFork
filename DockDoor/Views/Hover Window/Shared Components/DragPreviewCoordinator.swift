import AppKit

@MainActor
final class DragPreviewCoordinator {
    static let shared = DragPreviewCoordinator()
    private var previewWindow: NSWindow?
    private var registeredWindowID: CGWindowID?
    private var sessionToken: UUID?
    private var initialWindowFrame: CGRect?
    private var dragStartLocation: CGPoint?
    private let previewScale: CGFloat = 0.2
    private let previewOpacity: CGFloat = 0.5

    func startDragging(windowInfo: WindowInfo, at location: CGPoint, token: UUID) {
        endDragging()

        sessionToken = token
        dragStartLocation = location

        guard let image = windowInfo.image else { return }

        let scaledSize = CGSize(
            width: CGFloat(image.width) * previewScale,
            height: CGFloat(image.height) * previewScale
        )

        let scaledFrame = CGRect(
            x: location.x,
            y: location.y - scaledSize.height,
            width: scaledSize.width,
            height: scaledSize.height
        )

        let previewWindow = NSWindow(
            contentRect: scaledFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        previewWindow.backgroundColor = .clear
        previewWindow.isOpaque = false
        previewWindow.hasShadow = true
        previewWindow.level = .popUpMenu
        previewWindow.animationBehavior = .none
        previewWindow.isReleasedWhenClosed = false
        previewWindow.ignoresMouseEvents = true
        previewWindow.sharingType = .none
        previewWindow.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: scaledFrame.size))
        imageView.image = NSImage(cgImage: image, size: scaledFrame.size)
        imageView.imageScaling = .scaleAxesIndependently
        imageView.alphaValue = previewOpacity

        previewWindow.contentView = imageView
        initialWindowFrame = scaledFrame
        if previewWindow.windowNumber > 0 {
            let windowID = CGWindowID(previewWindow.windowNumber)
            WindowUtil.registerInternalWindow(windowID)
            registeredWindowID = windowID
        }
        previewWindow.setFrame(scaledFrame, display: true)
        previewWindow.orderFront(nil)
        previewWindow.alphaValue = 1

        self.previewWindow = previewWindow
    }

    func updatePreviewPosition(to currentLocation: CGPoint) {
        guard let startLocation = dragStartLocation,
              let initialFrame = initialWindowFrame,
              let previewWindow else { return }

        let deltaX = currentLocation.x - startLocation.x
        let deltaY = currentLocation.y - startLocation.y
        var newFrame = initialFrame
        newFrame.origin.x += deltaX
        newFrame.origin.y += deltaY
        previewWindow.setFrame(newFrame, display: true)
    }

    func isActive(token: UUID) -> Bool {
        sessionToken == token
    }

    func endDragging(token: UUID? = nil) {
        if let token, sessionToken != token { return }

        sessionToken = nil
        dragStartLocation = nil
        initialWindowFrame = nil

        if let window = previewWindow {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        if let windowID = registeredWindowID {
            WindowUtil.unregisterInternalWindow(windowID)
        }
        previewWindow = nil
        registeredWindowID = nil
    }
}
