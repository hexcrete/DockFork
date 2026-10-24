import AppKit
import Defaults
import SwiftUI

private final class BorderlessSearchFieldCell: NSSearchFieldCell {
    // Borderless fields otherwise let the field editor cover the cancel button.
    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: searchTextRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

struct SearchFieldView: View {
    let searchField: NSTextField
    @State private var backgroundAppearance: BackgroundAppearance = .resolve()

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            SearchTextFieldRepresentable(textField: searchField)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .materialPill(backgroundAppearance: backgroundAppearance)
        .frame(height: SearchWindow.searchHeight)
        .task {
            for await _ in Defaults.updates(BackgroundAppearance.observedKeys, initial: true) {
                let updated = BackgroundAppearance.resolve()
                if updated != backgroundAppearance { backgroundAppearance = updated }
            }
        }
    }
}

struct SearchTextFieldRepresentable: NSViewRepresentable {
    let textField: NSTextField

    func makeNSView(context: Context) -> NSTextField {
        textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}
}

class SearchWindow: NSPanel, NSSearchFieldDelegate {
    static let searchWidth: CGFloat = 300
    static let searchHeight: CGFloat = 40
    // The panel frame sits slightly inside the container edge. The capsule is
    // vertically centered within that frame, leaving a small visible gap.
    static let panelEdgeOffset: CGFloat = -4
    static let reservedHeight = max(
        0,
        searchHeight + panelEdgeOffset - HoverContainerPadding.container
    )

    private var searchField: NSSearchField!
    private weak var previewCoordinator: PreviewStateCoordinator?
    private var focusRequestID = UUID()

    private var searchPlaceholder: String {
        "Press \(KeyboardLabel.localizedKey(for: Defaults[.searchTriggerKey])) to search windows…"
    }

    init(previewCoordinator: PreviewStateCoordinator) {
        self.previewCoordinator = previewCoordinator
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.searchWidth, height: Self.searchHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        setupWindow()
        setupSearchField()
    }

    var isFocused: Bool {
        (NSApp.keyWindow === self) && (searchField.currentEditor() != nil)
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let accepted = super.makeFirstResponder(responder)
        if accepted, isFocused {
            setSearchPlaceholderVisible(false)
            configureFieldEditorForSingleLine()
        }
        return accepted
    }

    override func becomeKey() {
        super.becomeKey()
        if isFocused {
            setSearchPlaceholderVisible(false)
            configureFieldEditorForSingleLine()
        }
    }

    private func setupWindow() {
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        hidesOnDeactivate = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
    }

    private func setupSearchField() {
        searchField = NSSearchField()
        searchField.cell = BorderlessSearchFieldCell(textCell: "")
        searchField.isEditable = true
        searchField.isSelectable = true
        setSearchPlaceholderVisible(true)
        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.backgroundColor = .clear
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 14)
        searchField.usesSingleLineMode = true
        searchField.maximumNumberOfLines = 1
        searchField.lineBreakMode = .byClipping
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        (searchField.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        if let cell = searchField.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.usesSingleLineMode = true
            cell.isScrollable = true
            cell.lineBreakMode = .byClipping
        }
        searchField.delegate = self

        let searchView = SearchFieldView(searchField: searchField)
        let hostingView = NSHostingView(rootView: searchView)
        hostingView.frame = contentView!.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }
        updateSearchQuery(from: textField)
    }

    @objc private func searchFieldAction(_ sender: NSSearchField) {
        updateSearchQuery(from: sender)
    }

    private func updateSearchQuery(from field: NSTextField) {
        guard previewCoordinator?.searchQuery != field.stringValue else { return }
        previewCoordinator?.searchQuery = field.stringValue
    }

    func controlTextDidBeginEditing(_ obj: Notification) {
        setSearchPlaceholderVisible(false)
        configureFieldEditorForSingleLine()
    }

    func showSearch(relativeTo window: NSWindow) {
        guard window.isVisible else { return }

        if parent !== window {
            parent?.removeChildWindow(self)
            window.addChildWindow(self, ordered: .above)
        }

        let frame = window.frame
        if frame.width <= 0 || frame.height <= 0 {
            DispatchQueue.main.async { [weak self] in
                self?.showSearch(relativeTo: window)
            }
            return
        }

        setSearchPlaceholderVisible(!isFocused)
        setFrame(targetFrame(relativeTo: frame, on: window.screen), display: false)
        orderFront(nil)
    }

    func targetFrame(relativeTo frame: NSRect, on windowScreen: NSScreen?) -> NSRect {
        let searchWidth = Self.searchWidth
        let searchHeight = Self.searchHeight
        if (SharedPreviewWindowCoordinator.activeInstance?.spacesBarReservation ?? 0) > 0 {
            let screenFrame = windowScreen?.visibleFrame ?? frame
            return CGRect(x: max(screenFrame.minX, min((frame.midX - searchWidth / 2).rounded(), screenFrame.maxX - searchWidth)),
                          y: SpacesBarLayout.searchY(gridTop: frame.maxY), width: searchWidth, height: searchHeight)
        }
        let gap = Self.panelEdgeOffset
        let containerFrame = frame.insetBy(
            dx: HoverContainerPadding.container,
            dy: HoverContainerPadding.container
        )

        guard let screen = windowScreen ?? NSScreen.main else {
            return NSRect(
                x: containerFrame.midX - searchWidth / 2,
                y: containerFrame.maxY + gap,
                width: searchWidth,
                height: searchHeight
            )
        }

        let screenFrame = screen.visibleFrame
        let spaceAbove = screenFrame.maxY - containerFrame.maxY
        let spaceBelow = containerFrame.minY - screenFrame.minY
        let requiredVerticalSpace = searchHeight + gap

        var searchFrame: NSRect

        if spaceAbove >= requiredVerticalSpace {
            // Fits above
            searchFrame = NSRect(
                x: containerFrame.midX - searchWidth / 2,
                y: containerFrame.maxY + gap,
                width: searchWidth,
                height: searchHeight
            )
        } else if spaceBelow >= requiredVerticalSpace {
            // Fits below
            searchFrame = NSRect(
                x: containerFrame.midX - searchWidth / 2,
                y: containerFrame.minY - searchHeight - gap,
                width: searchWidth,
                height: searchHeight
            )
        } else {
            // Neither fits - position to the side
            let spaceRight = screenFrame.maxX - containerFrame.maxX
            let spaceLeft = containerFrame.minX - screenFrame.minX

            if spaceRight >= searchWidth + gap {
                // Position to the right
                searchFrame = NSRect(
                    x: containerFrame.maxX + gap,
                    y: containerFrame.maxY - searchHeight,
                    width: searchWidth,
                    height: searchHeight
                )
            } else if spaceLeft >= searchWidth + gap {
                // Position to the left
                searchFrame = NSRect(
                    x: containerFrame.minX - searchWidth - gap,
                    y: containerFrame.maxY - searchHeight,
                    width: searchWidth,
                    height: searchHeight
                )
            } else {
                // No room anywhere - overlay at top of window
                searchFrame = NSRect(
                    x: containerFrame.midX - searchWidth / 2,
                    y: containerFrame.maxY - searchHeight - gap,
                    width: searchWidth,
                    height: searchHeight
                )
            }
        }

        if searchFrame.minX < screenFrame.minX {
            searchFrame.origin.x = screenFrame.minX + 10
        } else if searchFrame.maxX > screenFrame.maxX {
            searchFrame.origin.x = screenFrame.maxX - searchWidth - 10
        }
        if searchFrame.minY < screenFrame.minY {
            searchFrame.origin.y = screenFrame.minY + 10
        } else if searchFrame.maxY > screenFrame.maxY {
            searchFrame.origin.y = screenFrame.maxY - searchHeight - 10
        }

        return searchFrame
    }

    func hideSearch() {
        unfocusSearchField()
        parent?.removeChildWindow(self)
        orderOut(nil)
        searchField.stringValue = ""
        previewCoordinator?.searchQuery = ""
    }

    func updateSearchText(_ text: String) {
        guard searchField.stringValue != text else { return }
        searchField.stringValue = text
        if let editor = searchField.currentEditor() {
            editor.selectedRange = NSRange(location: text.count, length: 0)
        }
    }

    func focusSearchField() {
        let requestID = UUID()
        focusRequestID = requestID
        setSearchPlaceholderVisible(false)
        makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let self, focusRequestID == requestID, isVisible, isKeyWindow else { return }
            _ = makeFirstResponder(searchField)
            configureFieldEditorForSingleLine()
        }
    }

    func unfocusSearchField() {
        focusRequestID = UUID()
        _ = makeFirstResponder(nil)
        setSearchPlaceholderVisible(true)
    }

    private func setSearchPlaceholderVisible(_ isVisible: Bool) {
        searchField.placeholderString = isVisible ? searchPlaceholder : ""
        searchField.needsDisplay = true
    }

    private func configureFieldEditorForSingleLine() {
        guard let editor = searchField.currentEditor() as? NSTextView else { return }
        editor.isHorizontallyResizable = true
        editor.isVerticallyResizable = false
        editor.maxSize = NSSize(width: .greatestFiniteMagnitude, height: searchField.bounds.height)
        editor.textContainerInset = .zero
        editor.textContainer?.widthTracksTextView = false
        editor.textContainer?.heightTracksTextView = true
        editor.textContainer?.lineBreakMode = .byClipping
        editor.textContainer?.containerSize = NSSize(width: .greatestFiniteMagnitude, height: searchField.bounds.height)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

enum SpacesBarLayout {
    static var scale: CGFloat { Defaults[.spacesBarItemSize].scale }
    static var clearSymbolSize: CGFloat { textFont.pointSize }
    static var minimumLabelWidth: CGFloat { max(20 * scale, clearSymbolSize) }
    static func titleParts(width: CGFloat, filtered: Bool, spacing: CGFloat) -> (button: CGFloat, text: CGFloat, spacing: CGFloat) {
        guard filtered else { return (0, width, 0) }
        let button = min(width, minimumLabelWidth)
        let gap = min(spacing, width - button)
        return (button, width - button - gap, gap)
    }

    static var font: Font { Defaults[.spacesBarItemSize].primaryFont }
    static var textFont: NSFont { Defaults[.spacesBarItemSize].primaryAppKitFont }
    static var headingTextFont: NSFont { PreviewHeaderLayout.textFont }
    static var headingInset: CGFloat { PreviewHeaderLayout.horizontalInset * Defaults[.globalPaddingMultiplier] }
    static var headingHeight: CGFloat { ceil(headingTextFont.ascender - headingTextFont.descender + headingTextFont.leading) }
    static let dividerWidth: CGFloat = 1
    static func sectionExtraWidth(displayCount: Int) -> CGFloat { CGFloat(max(0, displayCount - 1)) * (itemSpacing + dividerWidth) }
    static func titleInset(sectionWidth: CGFloat, titleWidth: CGFloat) -> CGFloat {
        min(headingInset, max(0, (sectionWidth - titleWidth) / 2))
    }

    static func pinnedTitleOffset(sectionStart: CGFloat, sectionWidth: CGFloat, titleWidth: CGFloat, scrollOffset: CGFloat) -> CGFloat {
        min(max(0, scrollOffset + innerPadding - sectionStart), max(0, sectionWidth - titleWidth - titleInset(sectionWidth: sectionWidth, titleWidth: titleWidth) * 2))
    }

    static var fullscreenWidth: CGFloat { 20 * scale }
    static let gap: CGFloat = 8
    static var searchGap: CGFloat { SearchWindow.panelEdgeOffset + HoverContainerPadding.dockStyleOuter }
    static var innerPadding: CGFloat {
        WindowPreviewHoverContainer.PreviewLayoutMetrics.resolve(compact: true, onlyWindowlessDockLikeRows: false,
                                                                 paddingMultiplier: Defaults[.globalPaddingMultiplier]).contentInset * scale
    }

    static var itemSpacing: CGFloat { HoverContainerPadding.compactItemSpacing * scale }
    static var minimumPillWidth: CGFloat { ceil(max(pillHeight * WindowStateIndicator.styledMinimumAspectRatio, minimumLabelWidth + horizontalInset * 2)) }
    static var horizontalInset: CGFloat { (MaterialPillStyle.horizontalInset + WindowStateIndicator.styledContentPadding) * scale }
    static func labelWidth(_ textWidth: CGFloat, fullscreen: Bool) -> CGFloat {
        max(minimumPillWidth, max(minimumLabelWidth, ceil(textWidth)) + horizontalInset * 2 + (fullscreen ? fullscreenWidth : 0) + WindowStateIndicator.styledContentPadding * scale)
    }

    static func searchY(gridTop: CGFloat) -> CGFloat { gridTop.rounded() - outerPadding + searchGap }
    static var pillHeight: CGFloat { 40 * scale }
    static var outerPadding: CGFloat { HoverContainerPadding.styledPanelInset }

    static func height(displayCount: Int) -> CGFloat {
        ceil(pillHeight + innerPadding * 2 + HoverContainerPadding.scrollOuter * 2 + outerPadding * 2 + (displayCount > 1 ? headingHeight + 4 * scale : 0))
    }

    // AppKit integralizes panel frames; size before anchoring so rounding cannot move the top edge.
    static func windowSize(_ size: CGSize, maximum: CGSize) -> CGSize {
        CGSize(width: min(ceil(size.width), floor(maximum.width)), height: min(ceil(size.height), floor(maximum.height)))
    }

    static func reservation(displayCount: Int, search: Bool) -> CGFloat {
        height(displayCount: displayCount) - outerPadding * 2 + (search ? searchGap : gap) + (search ? SearchWindow.searchHeight + searchGap : 0)
    }

    static func frame(grid: CGRect, size: CGSize, screen: CGRect, search: Bool, alignment: CGFloat) -> CGRect {
        let size = CGSize(width: ceil(size.width), height: ceil(size.height))
        let x = (grid.minX + (grid.width - size.width) * alignment).rounded()
        let lowerTop = search ? searchY(gridTop: grid.maxY) + SearchWindow.searchHeight : grid.maxY - outerPadding
        return CGRect(x: max(screen.minX, min(x, screen.maxX - size.width)),
                      y: min((lowerTop + (search ? searchGap : gap) - outerPadding).rounded(), screen.maxY - size.height),
                      width: size.width, height: size.height)
    }

    static func widths(ideal: [CGFloat], labels: [CGFloat], maximum: CGFloat, available: CGFloat, fixed: Bool, minimum: CGFloat = 0, preferDetails: Bool = false) -> [CGFloat] {
        let maximum = maximum.isFinite ? max(1, maximum) : 240
        guard !fixed else { return ideal.map { _ in maximum } }
        let minimum = minimum.isFinite ? max(0, minimum) : 0
        let floors = labels.map { min(maximum, max(minimum, minimumPillWidth, ceil($0))) }
        let natural = zip(ideal, floors).map { min(maximum, max($0, $1)) }
        guard !preferDetails else { return natural }
        let excess = max(0, natural.reduce(0, +) - available)
        let capacity = zip(natural, floors).reduce(0) { $0 + $1.0 - $1.1 }
        guard capacity > 0 else { return natural }
        let fraction = min(1, excess / capacity)
        return zip(natural, floors).map { $0 - ($0 - $1) * fraction }
    }
}

enum SpacesBarAppLayout {
    static var iconSize: CGFloat { 24 * SpacesBarLayout.scale }
    static var spacing: CGFloat { 6 * SpacesBarLayout.scale }
    static var countFontSize: CGFloat { 9 * SpacesBarLayout.scale }
}

struct SpacesBarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Default(.showAnimations) private var showAnimations
    @Default(.trafficLightTransitionDuration) private var controlAnimationDuration
    @Default(.enableMouseHoverInSwitcher) private var enableMouseHoverInSwitcher
    @Default(.spacesBarShowAppIcons) private var showAppIcons
    @Default(.spacesBarActivateAppIcons) private var activateAppIcons
    @Default(.uniformCardRadius) private var uniformCardRadius
    @Default(.hidePreviewCardBackground) private var hideCardBackground
    @Default(.globalPaddingMultiplier) private var paddingMultiplier
    @Default(.hoverHighlightColor) private var highlightColor
    @Default(.selectionOpacity) private var highlightOpacity
    @Default(.activeAppIndicatorColor) private var activeBorderColor
    @Default(.showActiveWindowBorder) private var showActiveWindowBorder
    @Default(.switcherShowAppIconBadges) private var showBadges
    @Default(.switcherAppIconBadgeScale) private var badgeScale
    @Default(.enableWindowSwitcherEdgeAutoScroll) private var edgeScrolling
    @Default(.mouseHoverAutoScrollSpeed) private var scrollSpeed
    @ObservedObject var viewport: SpacesBarViewport
    let viewportWidth: CGFloat
    let screen: NSScreen
    let sections: [ManagedSpacePresentation.Display]
    let widths: [CGSSpaceID: CGFloat]
    let initialSpace: CGSSpaceID?
    let highlightedSpace: CGSSpaceID?
    var previewCoordinator: PreviewStateCoordinator? = nil
    let labels: SpaceMenuDisplayMode
    let hover: (CGSSpaceID, Bool) -> Void
    let filteredSpace: CGSSpaceID?
    let clearFilter: () -> Void
    let activateApp: (ManagedSpacePresentation.App, ManagedSpacePresentation.Entry) -> Void
    let activate: (ManagedSpacePresentation.Entry) -> Void

    var body: some View {
        let entries = sections.flatMap(\.spaces)
        let contentWidth = entries.reduce(SpacesBarLayout.innerPadding * 2) { $0 + (widths[$1.id] ?? SpacesBarLayout.pillHeight) }
            + CGFloat(max(0, entries.count - 1)) * SpacesBarLayout.itemSpacing + SpacesBarLayout.sectionExtraWidth(displayCount: sections.count)
        let height = SpacesBarLayout.height(displayCount: sections.count) - SpacesBarLayout.outerPadding * 2 - HoverContainerPadding.scrollOuter * 2
        let target = highlightedSpace ?? initialSpace
        let preceding = entries.prefix { $0.id != target }
        let initialCenter = target.map { id in
            SpacesBarLayout.sectionExtraWidth(displayCount: (sections.firstIndex { $0.spaces.contains { $0.id == id } } ?? 0) + 1) + SpacesBarLayout.innerPadding + preceding.reduce(0) { $0 + (widths[$1.id] ?? 0) + SpacesBarLayout.itemSpacing } + (widths[id] ?? 0) / 2
        }
        BaseHoverContainer(bestGuessMonitor: screen, content: {
            SpacesBarScroll(content: AnyView(spaceContents.frame(width: max(contentWidth, viewportWidth), height: height, alignment: .topLeading)),
                            contentSize: CGSize(width: max(contentWidth, viewportWidth), height: height), headings: displayHeadings,
                            initialCenter: initialCenter, revealRange: highlightedSpace.flatMap { id in initialCenter.map { center in
                                let halfWidth = (widths[id] ?? 0) / 2
                                return (center - halfWidth) ... (center + halfWidth)
                            } }, viewport: viewport,
                            dropFrames: dropFrames, desktopDropIDs: Set(entries.filter { !$0.isFullscreen }.map(\.id)),
                            previewCoordinator: previewCoordinator,
                            filteredSpace: filteredSpace,
                            contentAnimation: PreviewControlAnimation.animation(duration: controlAnimationDuration, animationsEnabled: showAnimations, reduceMotion: reduceMotion),
                            edgeScrolling: edgeScrolling, speed: scrollSpeed)
                .frame(width: viewportWidth, height: height)
                .padding(HoverContainerPadding.scrollOuter)
                .fadeOnEdges(axis: .horizontal, fadeLength: HoverContainerPadding.edgeFadeLength, disableLeading: !viewport.fromStart, disableTrailing: viewport.toEnd)
                .clipShape(CardRadius.containerContentClip)
        }, backgroundAppearance: .resolve())
    }

    private var dropFrames: [CGSSpaceID: CGRect] {
        var x = SpacesBarLayout.innerPadding
        let y = SpacesBarLayout.innerPadding + (sections.count > 1 ? SpacesBarLayout.headingHeight + 4 * SpacesBarLayout.scale : 0)
        var frames: [CGSSpaceID: CGRect] = [:]
        for (index, display) in sections.enumerated() {
            if index > 0 { x += SpacesBarLayout.itemSpacing + SpacesBarLayout.dividerWidth }
            for entry in display.spaces {
                let width = widths[entry.id] ?? SpacesBarLayout.pillHeight
                frames[entry.id] = CGRect(x: x, y: y, width: width, height: SpacesBarLayout.pillHeight)
                x += width + SpacesBarLayout.itemSpacing
            }
        }
        return frames
    }

    private var displayHeadings: [SpacesBarDisplayHeading] {
        guard sections.count > 1 else { return [] }
        var start = SpacesBarLayout.innerPadding
        return sections.map { display in
            let width = display.spaces.reduce(0) { $0 + (widths[$1.id] ?? 0) } + CGFloat(max(0, display.spaces.count - 1)) * SpacesBarLayout.itemSpacing
            defer { start += width + SpacesBarLayout.itemSpacing * 2 + SpacesBarLayout.dividerWidth }
            return SpacesBarDisplayHeading(name: display.name, start: start, width: width)
        }
    }

    private var spaceContents: some View {
        HStack(spacing: SpacesBarLayout.itemSpacing) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, display in
                let sectionWidth = display.spaces.reduce(0) { $0 + (widths[$1.id] ?? 0) } + CGFloat(max(0, display.spaces.count - 1)) * SpacesBarLayout.itemSpacing
                if index > 0 {
                    Divider().frame(width: SpacesBarLayout.dividerWidth, height: SpacesBarLayout.pillHeight + SpacesBarLayout.headingHeight + 4 * SpacesBarLayout.scale)
                }
                VStack(alignment: .leading, spacing: 4 * SpacesBarLayout.scale) {
                    if sections.count > 1 {
                        Color.clear.frame(width: sectionWidth, height: SpacesBarLayout.headingHeight)
                    }
                    HStack(spacing: SpacesBarLayout.itemSpacing) {
                        ForEach(display.spaces) { entry in
                            pill(entry).id(entry.id)
                        }
                    }
                }
                .fixedSize(horizontal: true, vertical: true)
            }
        }
        .padding(SpacesBarLayout.innerPadding)
    }

    private func pill(_ entry: ManagedSpacePresentation.Entry) -> some View {
        let width = widths[entry.id] ?? 160
        let title = entry.title(mode: labels)
        let font = SpacesBarLayout.textFont
        let titleWidth = min(max(0, width - SpacesBarLayout.horizontalInset * 2 - (entry.isFullscreen ? SpacesBarLayout.fullscreenWidth : 0)), max(SpacesBarLayout.minimumLabelWidth, ceil((title as NSString).size(withAttributes: [.font: font]).width) + 2))
        let titleParts = SpacesBarLayout.titleParts(width: titleWidth, filtered: filteredSpace == entry.id, spacing: SpacesBarAppLayout.spacing)
        let iconRoom = max(0, width - titleWidth - SpacesBarLayout.horizontalInset * 2 - SpacesBarAppLayout.spacing - (entry.isFullscreen ? SpacesBarLayout.fullscreenWidth : 0))
        let apps = showAppIcons ? entry.apps : []
        let fittedCount = AppIconStripFormatting.visibleCount(
            total: apps.count, availableWidth: iconRoom, iconSize: SpacesBarAppLayout.iconSize,
            font: font, spacing: SpacesBarAppLayout.spacing
        )
        let count = fittedCount ?? 0
        return ZStack {
            Button { activate(entry) } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(title), \(entry.apps.reduce(0) { $0 + $1.windowCount }) windows"))
                .accessibilityValue(entry.isCurrent ? Text("Current") : Text(""))
            HStack(spacing: SpacesBarAppLayout.spacing) {
                if entry.isFullscreen { Image(systemName: "arrow.up.left.and.arrow.down.right").allowsHitTesting(false) }
                ZStack(alignment: .leading) {
                    Button(action: clearFilter) {
                        Image(systemName: "xmark.circle.fill")
                            .resizable().scaledToFit()
                            .frame(width: SpacesBarLayout.clearSymbolSize, height: SpacesBarLayout.clearSymbolSize)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: SpacesBarLayout.minimumLabelWidth)
                    .offset(x: filteredSpace == entry.id ? 0 : -SpacesBarLayout.minimumLabelWidth)
                    .opacity(filteredSpace == entry.id ? 1 : 0)
                    .allowsHitTesting(filteredSpace == entry.id)
                    .help(String(localized: "Clear Space filter"))
                    .accessibilityLabel(Text("Clear Space filter"))
                    .accessibilityHidden(filteredSpace != entry.id)
                    Text(title).lineLimit(1).truncationMode(.tail)
                        .frame(width: titleParts.text, alignment: .center).clipped()
                        .offset(x: titleParts.button + titleParts.spacing)
                        .opacity(titleParts.text > 0 ? 1 : 0).allowsHitTesting(false)
                }
                .frame(width: titleWidth, height: ceil(font.ascender - font.descender + font.leading), alignment: .leading)
                .clipped()
                .previewControlVisibilityAnimation(isVisible: filteredSpace == entry.id, duration: controlAnimationDuration, animationsEnabled: showAnimations)
                ForEach(Array(apps.prefix(count).enumerated()), id: \.element.application.processIdentifier) { _, app in
                    let icon = PreviewAppIcon(icon: app.application.icon, bundleURL: app.application.bundleURL,
                                              size: SpacesBarAppLayout.iconSize, showBadge: showBadges,
                                              badgeScale: badgeScale, mockPreviewActive: false)
                        .overlay(alignment: .bottomTrailing) {
                            if app.windowCount > 1 {
                                Text("\(app.windowCount)")
                                    .font(.system(size: SpacesBarAppLayout.countFontSize, weight: .bold))
                                    .foregroundStyle(.primary)
                                    .offset(x: 4 * SpacesBarLayout.scale, y: 4 * SpacesBarLayout.scale)
                            }
                        }
                        .accessibilityHidden(true)
                    if activateAppIcons, !app.windowIdentities.isEmpty {
                        Button { activateApp(app, entry) } label: { icon.contentShape(Rectangle()) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(app.application.localizedName ?? String(localized: "Application")))
                    } else {
                        icon.allowsHitTesting(false)
                    }
                }
                if fittedCount != nil, count < apps.count { Text("+\(apps.count - count)").foregroundStyle(.secondary).allowsHitTesting(false) }
            }
            .font(SpacesBarLayout.font)
            .padding(.horizontal, SpacesBarLayout.horizontalInset)
            .frame(width: width, height: SpacesBarLayout.pillHeight, alignment: .center)
        }
        .frame(width: width, height: SpacesBarLayout.pillHeight)
        .previewCardChrome(
            uniformCardRadius: uniformCardRadius, paddingMultiplier: paddingMultiplier,
            expansionEdges: [], hideBackground: hideCardBackground,
            isHighlighted: (enableMouseHoverInSwitcher && viewport.hoveredSpaceID == entry.id) || highlightedSpace == entry.id, isActiveWindow: showActiveWindowBorder && entry.isCurrent,
            highlightColor: highlightColor ?? Color(nsColor: .controlAccentColor), highlightOpacity: highlightOpacity,
            activeBorderColor: activeBorderColor, backgroundAppearance: .resolve()
        )
        .contentShape(RoundedRectangle(cornerRadius: CardRadius.previewCard(uniform: uniformCardRadius, paddingMultiplier: paddingMultiplier)))
        .onContinuousHover { phase in
            switch phase {
            case .active:
                if viewport.hoveredSpaceID != entry.id { viewport.hoveredSpaceID = entry.id }
                hover(entry.id, true)
            case .ended:
                if viewport.hoveredSpaceID == entry.id { viewport.hoveredSpaceID = nil }
                hover(entry.id, false)
            }
        }
        .overlay {
            if viewport.dropTargetID == entry.id {
                PreviewDragTargetHighlight(uniformCardRadius: uniformCardRadius, paddingMultiplier: paddingMultiplier, expansionEdges: [])
            }
        }
        .accessibilityElement(children: .contain)
    }
}

final class SpacesBarWindow: NSPanel {
    let viewport = SpacesBarViewport()
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        hidesOnDeactivate = false
    }
}

struct SpacesBarDisplayHeading: Equatable {
    let name: String
    let start: CGFloat
    let width: CGFloat
}

final class SpacesBarHeadingOverlay: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class SpacesBarViewport: ObservableObject {
    @Published var fromStart = false
    @Published var toEnd = true
    @Published var hoveredSpaceID: CGSSpaceID?
    @Published var dropTargetID: CGSSpaceID?
}

final class SpacesBarHostedState: ObservableObject {
    @Published var content = AnyView(EmptyView())
}

struct SpacesBarHostedContent: View {
    @ObservedObject var state: SpacesBarHostedState
    var body: some View { state.content }
}

struct SpacesBarScroll: NSViewRepresentable {
    let content: AnyView
    let contentSize: CGSize
    var headings: [SpacesBarDisplayHeading] = []
    let initialCenter: CGFloat?
    var revealRange: ClosedRange<CGFloat>? = nil
    let viewport: SpacesBarViewport
    var dropFrames: [CGSSpaceID: CGRect] = [:]
    var desktopDropIDs: Set<CGSSpaceID> = []
    var previewCoordinator: PreviewStateCoordinator? = nil
    var filteredSpace: CGSSpaceID? = nil
    var contentAnimation: Animation? = nil
    let edgeScrolling: Bool
    let speed: CGFloat

    func makeNSView(context: Context) -> ViewportView { ViewportView() }

    func updateNSView(_ view: ViewportView, context: Context) {
        view.dropFrames = dropFrames
        view.desktopDropIDs = desktopDropIDs
        previewCoordinator?.spaceDragViewport = view
        view.onDropTargetChanged = { [weak viewport] id in
            if viewport?.dropTargetID != id { viewport?.dropTargetID = id }
        }
        view.updateContent(content, filteredSpace: filteredSpace, animation: contentAnimation)
        let contentFrame = CGRect(origin: .zero, size: contentSize)
        if view.hosting.frame != contentFrame { view.hosting.frame = contentFrame }
        if view.scroller.contentSize != contentSize { view.scroller.contentSize = contentSize }
        view.initialCenter = initialCenter
        if view.lastRevealRange != revealRange {
            view.lastRevealRange = revealRange
            if let revealRange {
                let inset = SpacesBarLayout.innerPadding
                if revealRange.lowerBound < view.scroller.offset + inset {
                    view.scroller.scroll(to: revealRange.lowerBound - inset, animated: false)
                } else if revealRange.upperBound > view.scroller.offset + view.bounds.width - inset {
                    view.scroller.scroll(to: revealRange.upperBound + inset - view.bounds.width, animated: false)
                }
            }
        }
        view.edgeScrolling = edgeScrolling
        view.speed = speed
        view.updateHeadings(headings)
        view.scroller.onOffsetChange = { [weak view] _ in view?.positionHeadings(); view?.refreshDragTarget() }
        view.scroller.onScrollStateChange = { [weak viewport] fromStart, toEnd in
            guard let viewport, viewport.fromStart != fromStart || viewport.toEnd != toEnd else { return }
            DispatchQueue.main.async { [weak viewport] in
                guard let viewport else { return }
                if viewport.fromStart != fromStart { viewport.fromStart = fromStart }
                if viewport.toEnd != toEnd { viewport.toEnd = toEnd }
            }
        }
        view.updateScroll()
    }

    static func dismantleNSView(_ view: ViewportView, coordinator: ()) {
        view.scroller.onOffsetChange = nil
        view.scroller.onScrollStateChange = nil
        view.updateDrag(at: nil)
        view.onDropTargetChanged = nil
        view.scroller.stopEdgeScroll()
    }

    final class ViewportView: NSView {
        let scroller = CardGridScrollView.ContainerView(scrollsVertically: false)
        private let hostedState: SpacesBarHostedState
        let hosting: NSHostingView<SpacesBarHostedContent>
        private var presentedContent = false
        private var lastFilteredSpace: CGSSpaceID?

        func updateContent(_ content: AnyView, filteredSpace: CGSSpaceID?, animation: Animation?) {
            let transition = presentedContent && lastFilteredSpace != filteredSpace ? animation : nil
            presentedContent = true
            lastFilteredSpace = filteredSpace
            withAnimation(transition) { hostedState.content = content }
        }

        let headingOverlay = SpacesBarHeadingOverlay()
        private var headings: [SpacesBarDisplayHeading] = []
        private var headingLabels: [NSTextField] = []
        private var headingLabelWidths: [CGFloat] = []
        private var headingFont: NSFont?
        var initialCenter: CGFloat?
        var lastRevealRange: ClosedRange<CGFloat>?
        var edgeScrolling = false
        var speed: CGFloat = 0
        private var centered = false
        private var pointer: CGPoint?
        private var dragPointer: CGPoint?
        var dropFrames: [CGSSpaceID: CGRect] = [:]
        var desktopDropIDs: Set<CGSSpaceID> = []
        var onDropTargetChanged: ((CGSSpaceID?) -> Void)?

        func spaceForDrop(at screenPoint: CGPoint) -> CGSSpaceID? {
            guard let window, window.isVisible,
                  let point = scroller.contentPoint(for: scroller.convert(window.convertPoint(fromScreen: screenPoint), from: nil)) else { return nil }
            return dropFrames.first { $0.value.contains(point) }?.key
        }

        func updateDrag(at screenPoint: CGPoint?) {
            dragPointer = screenPoint
            refreshDragTarget()
            updateScroll()
        }

        func refreshDragTarget() {
            let id = dragPointer.flatMap { spaceForDrop(at: $0) }
            onDropTargetChanged?(id.flatMap { desktopDropIDs.contains($0) ? $0 : nil })
        }

        private var hoverArea: NSTrackingArea?

        override init(frame: NSRect) {
            let state = SpacesBarHostedState()
            hostedState = state
            hosting = NSHostingView(rootView: SpacesBarHostedContent(state: state))
            super.init(frame: frame)
            hosting.sizingOptions = []
            scroller.contentView.addSubview(hosting)
            addSubview(scroller)
            headingOverlay.wantsLayer = true
            headingOverlay.layer?.masksToBounds = true
            addSubview(headingOverlay)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            scroller.frame = bounds
            headingOverlay.frame = bounds
            positionHeadings()
            if !centered, bounds.width > 0, let initialCenter {
                centered = true
                scroller.scroll(to: initialCenter - bounds.width / 2, animated: false)
            }
            updateScroll()
        }

        func updateHeadings(_ headings: [SpacesBarDisplayHeading]) {
            let font = SpacesBarLayout.headingTextFont
            if self.headings != headings || headingFont != font {
                self.headings = headings
                headingFont = font
                headingLabels.forEach { $0.removeFromSuperview() }
                headingLabels = headings.map { heading in
                    let label = NSTextField(labelWithString: heading.name)
                    label.font = font
                    label.textColor = .labelColor
                    label.lineBreakMode = .byTruncatingTail
                    label.setAccessibilityLabel(heading.name)
                    label.sizeToFit()
                    headingOverlay.addSubview(label)
                    return label
                }
                headingLabelWidths = headingLabels.map(\.frame.width)
            }
            positionHeadings()
        }

        func positionHeadings() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (index, (heading, label)) in zip(headings, headingLabels).enumerated() {
                let width = min(headingLabelWidths[index], max(0, heading.width))
                let inset = SpacesBarLayout.titleInset(sectionWidth: heading.width, titleWidth: width)
                let shift = SpacesBarLayout.pinnedTitleOffset(sectionStart: heading.start, sectionWidth: heading.width,
                                                              titleWidth: width, scrollOffset: scroller.offset)
                label.frame = CGRect(x: heading.start + inset + shift - scroller.offset, y: SpacesBarLayout.innerPadding,
                                     width: width, height: SpacesBarLayout.headingHeight)
            }
            CATransaction.commit()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let hoverArea { removeTrackingArea(hoverArea) }
            let area = NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited], owner: self, userInfo: nil)
            addTrackingArea(area)
            hoverArea = area
        }

        override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }

        override func mouseMoved(with event: NSEvent) {
            pointer = convert(event.locationInWindow, from: nil)
            updateScroll()
        }

        override func mouseExited(with event: NSEvent) {
            pointer = nil
            scroller.stopEdgeScroll()
        }

        func updateScroll() {
            let request: CardGridScrollView.EdgeScrollRequest?
            let activePointer = dragPointer.flatMap { point in window.map { convert($0.convertPoint(fromScreen: point), from: nil) } } ?? pointer
            if edgeScrolling, let pointer = activePointer, bounds.contains(pointer), scroller.maxOffset > 1 {
                let zone = min(CardGridScrollView.edgeScrollZoneSize, bounds.width / 2)
                request = pointer.x < zone ? .backward : (pointer.x > bounds.width - zone ? .forward : nil)
            } else {
                request = nil
            }
            scroller.updateEdgeScroll(request: request, speed: speed)
        }
    }
}
