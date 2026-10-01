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
    private let maximumPreviewSize = CGSize(width: 240, height: 160)
    private let iconPreviewSize = CGSize(width: 45, height: 45)

    func startDragging(
        image: CGImage?,
        fallbackIcon: NSImage?,
        logicalWindowSize: CGSize,
        at location: CGPoint,
        token: UUID
    ) {
        endDragging()

        sessionToken = token
        dragStartLocation = location

        let content: NSImage
        let scaledSize: CGSize
        if let image {
            content = NSImage(cgImage: image, size: logicalWindowSize)
            scaledSize = constrainedPreviewSize(for: logicalWindowSize)
        } else if let fallbackIcon {
            content = fallbackIcon
            scaledSize = iconPreviewSize
        } else {
            return
        }

        let scaledFrame = CGRect(
            x: location.x - scaledSize.width / 2,
            y: location.y - scaledSize.height / 2,
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
        imageView.image = content
        imageView.imageScaling = .scaleProportionallyUpOrDown
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

    private func constrainedPreviewSize(for logicalSize: CGSize) -> CGSize {
        guard logicalSize.width > 0, logicalSize.height > 0 else {
            return iconPreviewSize
        }

        let scaled = CGSize(
            width: logicalSize.width * previewScale,
            height: logicalSize.height * previewScale
        )
        let constraintScale = min(
            1,
            maximumPreviewSize.width / scaled.width,
            maximumPreviewSize.height / scaled.height
        )
        return CGSize(
            width: scaled.width * constraintScale,
            height: scaled.height * constraintScale
        )
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
