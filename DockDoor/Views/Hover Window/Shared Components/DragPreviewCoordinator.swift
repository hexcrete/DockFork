import AppKit
import SwiftUI

struct PreviewDragTarget {
    let window: WindowInfo
    let originalFrame: CGRect
}

enum PreviewDragLayout {
    static func tilingOrder(target: PreviewWindowIdentity, targetGroup: [PreviewWindowIdentity],
                            dragged: [PreviewWindowIdentity]) -> [PreviewWindowIdentity]
    {
        guard !dragged.contains(target) else { return [] }
        var seen = Set<PreviewWindowIdentity>()
        return (targetGroup + dragged).filter { seen.insert($0).inserted }
    }

    // Cached frames use AX coordinates, whose vertical axis is opposite AppKit's.
    static func centers(for frames: [CGRect], at pointer: CGPoint, within visibleFrame: CGRect) -> [CGPoint]? {
        guard frames.allSatisfy({ $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0 }) else { return nil }
        guard let first = frames.first else { return [] }
        let bounds = frames.dropFirst().reduce(first) { $0.union($1) }
        let centerX = bounds.width <= visibleFrame.width
            ? min(max(pointer.x, visibleFrame.minX + bounds.width / 2), visibleFrame.maxX - bounds.width / 2) : visibleFrame.midX
        let centerY = bounds.height <= visibleFrame.height
            ? min(max(pointer.y, visibleFrame.minY + bounds.height / 2), visibleFrame.maxY - bounds.height / 2) : visibleFrame.midY
        return frames.map { CGPoint(x: centerX + $0.midX - bounds.midX, y: centerY + bounds.midY - $0.midY) }
    }
}

enum PreviewDragCardStyle {
    static let padding: CGFloat = 10
    static let spacing: CGFloat = 8
}

extension View {
    func previewDragCard() -> some View {
        padding(PreviewDragCardStyle.padding)
            .dockStyle(backgroundAppearance: .resolve(), cornerRadius: 12)
    }
}

struct SpaceDragLabel: View, Equatable {
    let title: String
    let symbol: String

    var body: some View {
        HStack(spacing: PreviewDragCardStyle.spacing) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: SpacesBarLayout.textFont.pointSize)
            Text(title)
        }
        .font(SpacesBarLayout.font)
        .previewDragCard()
        .fixedSize()
    }
}

@MainActor
final class DragPreviewCoordinator {
    static let shared = DragPreviewCoordinator()
    private var previewWindow: NSWindow?
    private var registeredWindowID: CGWindowID?
    private var sessionToken: UUID?
    private var dropToken: UUID?
    private var dropTask: Task<Void, Never>?
    private var spaceLabel: SpaceDragLabel?
    private var spaceLabelView: NSHostingView<SpaceDragLabel>?
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
        group: [WindowInfo] = [],
        at location: CGPoint,
        token: UUID
    ) {
        beginDragging(at: location, token: token)

        if group.count > 1 {
            let visible = Array(group.prefix(6))
            let overflow = group.count - visible.count
            let iconsWidth = CGFloat(visible.count) * iconPreviewSize.width
            let spacingWidth = CGFloat(visible.count - 1) * PreviewDragCardStyle.spacing
            let overflowWidth: CGFloat = overflow > 0 ? 40 : 0
            let size = CGSize(width: iconsWidth + spacingWidth + PreviewDragCardStyle.padding * 2 + overflowWidth, height: 65)
            let row = HStack(spacing: PreviewDragCardStyle.spacing) {
                ForEach(visible, id: \.id) { window in
                    Image(nsImage: window.app.icon ?? NSImage())
                        .resizable().frame(width: 45, height: 45)
                }
                if overflow > 0 { Text("+\(overflow)").font(.caption).foregroundStyle(.secondary) }
            }
            .frame(width: size.width - PreviewDragCardStyle.padding * 2, height: size.height - PreviewDragCardStyle.padding * 2)
            .previewDragCard()
            showGhost(NSHostingView(rootView: row), size: size, at: location)
            return
        }

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

        let imageView = NSImageView(frame: NSRect(origin: .zero, size: scaledSize))
        imageView.image = content
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.alphaValue = previewOpacity
        showGhost(imageView, size: scaledSize, at: location)
    }

    private func beginDragging(at location: CGPoint, token: UUID) {
        cancelPendingDrop()
        endDragging()
        sessionToken = token
        dragStartLocation = location
    }

    func startSpaceDragging(title: String, at location: CGPoint, token: UUID) {
        beginDragging(at: location, token: token)
        let content = SpaceDragLabel(title: title, symbol: "nosign")
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        spaceLabel = content
        spaceLabelView = hosting
        showGhost(hosting, size: CGSize(width: ceil(size.width), height: ceil(size.height)), at: location)
    }

    func updateSpaceLabel(title: String, symbol: String, token: UUID) {
        guard sessionToken == token, let hosting = spaceLabelView, let window = previewWindow,
              let initialFrame = initialWindowFrame else { return }
        let content = SpaceDragLabel(title: title, symbol: symbol)
        guard spaceLabel != content else { return }
        spaceLabel = content
        hosting.rootView = content
        let size = hosting.fittingSize
        let roundedSize = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard roundedSize != initialFrame.size else { return }
        initialWindowFrame = CGRect(x: initialFrame.midX - roundedSize.width / 2, y: initialFrame.midY - roundedSize.height / 2,
                                    width: roundedSize.width, height: roundedSize.height)
        let frame = window.frame
        window.setFrame(CGRect(x: frame.midX - roundedSize.width / 2, y: frame.midY - roundedSize.height / 2,
                               width: roundedSize.width, height: roundedSize.height), display: true)
    }

    private func showGhost(_ content: NSView, size: CGSize, at location: CGPoint) {
        let scaledFrame = CGRect(x: location.x - size.width / 2, y: location.y - size.height / 2,
                                 width: size.width, height: size.height)

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

        previewWindow.contentView = content
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

    func isCompletingDrop(token: UUID) -> Bool {
        dropToken == token
    }

    // A released drop must survive the preview disappearing during placement or activation.
    func completeDrop(token: UUID, operation: @escaping @MainActor () async -> WindowUtil.PreviewBatchResult,
                      completion: @escaping @MainActor (WindowUtil.PreviewBatchResult) -> Void)
    {
        cancelPendingDrop()
        dropToken = token
        dropTask = Task { @MainActor in
            guard !Task.isCancelled, dropToken == token else { return }
            let result = await operation()
            guard !Task.isCancelled, dropToken == token else { return }
            dropTask = nil
            dropToken = nil
            completion(result)
        }
    }

    private func cancelPendingDrop() {
        dropTask?.cancel()
        dropTask = nil
        dropToken = nil
    }

    func endDragging(token: UUID? = nil) {
        if let token, sessionToken != token { return }

        sessionToken = nil
        spaceLabel = nil
        spaceLabelView = nil
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
