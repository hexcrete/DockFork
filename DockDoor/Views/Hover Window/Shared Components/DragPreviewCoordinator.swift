import AppKit
import Defaults
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

struct PreviewDragCardStyle: Equatable {
    let height: CGFloat
    let iconSize: CGFloat
    let spacing: CGFloat
    let horizontalInset: CGFloat
    let verticalPadding: CGFloat
    let font: Font
    let textFont: NSFont
    let uniformCardRadius: Bool
    let paddingMultiplier: CGFloat
    let hideBackground: Bool
    let backgroundAppearance: BackgroundAppearance

    static func compact(appearance: PreviewAppearanceSettings, uniformCardRadius: Bool, backgroundAppearance: BackgroundAppearance) -> Self {
        let size = appearance.compactModeItemSize
        let pill = SpacePillMetrics(height: size.rowHeight)
        return Self(height: size.rowHeight, iconSize: size.iconSize, spacing: pill.spacing,
                    horizontalInset: pill.horizontalInset, verticalPadding: CompactPreviewCardLayout.verticalPadding,
                    font: size.primaryFont, textFont: size.primaryAppKitFont, uniformCardRadius: uniformCardRadius,
                    paddingMultiplier: appearance.globalPaddingMultiplier, hideBackground: appearance.hidePreviewCardBackground,
                    backgroundAppearance: backgroundAppearance)
    }

    static func spacesBar(backgroundAppearance: BackgroundAppearance) -> Self {
        Self(height: SpacesBarLayout.pillHeight, iconSize: SpacesBarAppLayout.iconSize, spacing: SpacesBarAppLayout.spacing,
             horizontalInset: SpacesBarLayout.horizontalInset, verticalPadding: 0,
             font: SpacesBarLayout.font, textFont: SpacesBarLayout.textFont, uniformCardRadius: Defaults[.uniformCardRadius],
             paddingMultiplier: Defaults[.globalPaddingMultiplier], hideBackground: Defaults[.hidePreviewCardBackground],
             backgroundAppearance: backgroundAppearance)
    }

    var actionWidth: CGFloat { textFont.pointSize + spacing }

    func groupLayout(total: Int, maximumWidth: CGFloat) -> (visible: Int, width: CGFloat) {
        let count = AppIconStripFormatting.visibleCount(total: total, availableWidth: maximumWidth - horizontalInset * 2 - actionWidth,
                                                        iconSize: iconSize, font: textFont, spacing: spacing, maximumVisible: 6) ?? 0
        let remaining = total - count
        let suffixWidth = remaining > 0 ? ("+\(remaining)" as NSString).size(withAttributes: [.font: textFont]).width : 0
        let width = AppIconStripFormatting.width(iconCount: count, iconSize: iconSize, font: textFont, spacing: spacing)
            + suffixWidth + (remaining > 0 && count > 0 ? spacing : 0) + horizontalInset * 2 + actionWidth
        return (count, min(maximumWidth, ceil(width)))
    }
}

extension View {
    func previewDragCard(_ style: PreviewDragCardStyle, width: CGFloat) -> some View {
        let inset = min(style.horizontalInset, width / 2)
        return frame(width: max(0, width - inset * 2), height: style.height)
            .padding(.horizontal, inset)
            .clipped()
            .previewCardChrome(
                uniformCardRadius: style.uniformCardRadius, paddingMultiplier: style.paddingMultiplier, expansionEdges: [],
                hideBackground: style.hideBackground, isHighlighted: false,
                highlightColor: .accentColor, highlightOpacity: 0, activeBorderColor: .accentColor,
                backgroundAppearance: style.backgroundAppearance
            )
    }
}

struct PreviewDragApp: Identifiable {
    let id: String
    let app: NSRunningApplication
    var windowCount: Int

    static func grouped(_ windows: [WindowInfo]) -> [Self] {
        var result: [Self] = []
        var indices: [String: Int] = [:]
        for window in windows {
            let key = ManagedSpacePresentation.applicationKey(for: window.app)
            if let index = indices[key] {
                result[index].windowCount += 1
            } else {
                indices[key] = result.count
                result.append(Self(id: key, app: window.app, windowCount: 1))
            }
        }
        return result
    }
}

struct PreviewDragIcon: Identifiable {
    let id: String
    let image: NSImage
    let windowCount: Int
}

struct PreviewDragActionSymbol: View {
    let symbol: String
    let width: CGFloat

    var body: some View {
        Image(systemName: symbol).foregroundStyle(.secondary).frame(width: width)
    }
}

struct WindowGroupDragCard: View {
    var symbol: String = "nosign"
    let icons: [PreviewDragIcon]
    let overflow: Int
    let width: CGFloat
    let style: PreviewDragCardStyle

    var body: some View {
        HStack(spacing: style.spacing) {
            PreviewDragActionSymbol(symbol: symbol, width: style.textFont.pointSize)
            ForEach(icons) { icon in
                Image(nsImage: icon.image).resizable().frame(width: style.iconSize, height: style.iconSize)
                    .appWindowCount(icon.windowCount, height: style.height)
            }
            if overflow > 0 { Text("+\(overflow)").foregroundStyle(.secondary).lineLimit(1) }
        }
        .font(style.font)
        .padding(.vertical, style.verticalPadding)
        .previewDragCard(style, width: width)
    }
}

struct SpaceDragLabel: View, Equatable {
    let title: String
    let symbol: String
    let style: PreviewDragCardStyle
    let maximumWidth: CGFloat

    var body: some View {
        let titleWidth = (title as NSString).size(withAttributes: [.font: style.textFont]).width
        let width = min(maximumWidth, ceil(titleWidth + style.textFont.pointSize + style.spacing + style.horizontalInset * 2))
        HStack(spacing: style.spacing) {
            PreviewDragActionSymbol(symbol: symbol, width: style.textFont.pointSize)
            Text(title).lineLimit(1).truncationMode(.tail)
        }
        .font(style.font)
        .previewDragCard(style, width: width)
    }
}

struct WindowDragGhost: View {
    var card: WindowGroupDragCard
    let image: NSImage?
    let imageSize: CGSize
    let imageOpacity: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: imageSize.width, height: imageSize.height).opacity(imageOpacity)
            }
            card
        }
        .frame(width: max(card.width, imageSize.width), height: max(card.style.height, imageSize.height))
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
    private var windowGhostView: NSHostingView<WindowDragGhost>?
    private var windowSymbol = "nosign"
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
        cardStyle: PreviewDragCardStyle,
        at location: CGPoint,
        token: UUID
    ) {
        beginDragging(at: location, token: token)

        let maximumWidth = max(1, location.screen()?.visibleFrame.width ?? maximumPreviewSize.width)
        let apps = PreviewDragApp.grouped(group)
        let layout = cardStyle.groupLayout(total: apps.count, maximumWidth: maximumWidth)
        let icons = apps.prefix(layout.visible).map { PreviewDragIcon(id: $0.id, image: $0.app.icon ?? NSImage(), windowCount: $0.windowCount) }
        let card = WindowGroupDragCard(icons: icons, overflow: apps.count - icons.count, width: layout.width, style: cardStyle)
        var content: NSImage?
        var imageSize = CGSize.zero
        if group.count <= 1 {
            if let image {
                content = NSImage(cgImage: image, size: logicalWindowSize)
                imageSize = constrainedPreviewSize(for: logicalWindowSize)
            } else if let fallbackIcon {
                content = fallbackIcon
                imageSize = iconPreviewSize
            }
        }
        let ghost = WindowDragGhost(card: card, image: content, imageSize: imageSize, imageOpacity: previewOpacity)
        let hosting = NSHostingView(rootView: ghost)
        windowGhostView = hosting
        showGhost(hosting, size: CGSize(width: max(layout.width, imageSize.width), height: max(cardStyle.height, imageSize.height)),
                  at: location, hasShadow: false)
    }

    func updateWindowSymbol(_ symbol: String, token: UUID) {
        guard sessionToken == token, symbol != windowSymbol, let hosting = windowGhostView else { return }
        windowSymbol = symbol
        var content = hosting.rootView
        content.card.symbol = symbol
        hosting.rootView = content
    }

    private func beginDragging(at location: CGPoint, token: UUID) {
        cancelPendingDrop()
        endDragging()
        sessionToken = token
        dragStartLocation = location
    }

    func startSpaceDragging(title: String, style: PreviewDragCardStyle, at location: CGPoint, token: UUID) {
        beginDragging(at: location, token: token)
        let content = SpaceDragLabel(title: title, symbol: "nosign", style: style,
                                     maximumWidth: max(1, location.screen()?.visibleFrame.width ?? maximumPreviewSize.width))
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize
        spaceLabel = content
        spaceLabelView = hosting
        showGhost(hosting, size: CGSize(width: ceil(size.width), height: ceil(size.height)), at: location, hasShadow: false)
    }

    func updateSpaceLabel(title: String, symbol: String, token: UUID) {
        guard sessionToken == token, let hosting = spaceLabelView, let window = previewWindow,
              let initialFrame = initialWindowFrame, let previous = spaceLabel else { return }
        let content = SpaceDragLabel(title: title, symbol: symbol, style: previous.style, maximumWidth: previous.maximumWidth)
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

    private func showGhost(_ content: NSView, size: CGSize, at location: CGPoint, hasShadow: Bool = true) {
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
        previewWindow.hasShadow = hasShadow
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
        windowGhostView = nil
        windowSymbol = "nosign"
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
