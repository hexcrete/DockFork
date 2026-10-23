import Defaults
import SwiftUI

enum AppIconStripFormatting {
    static let menuIconSize: CGFloat = 14

    static func width(iconCount: Int, iconSize: CGFloat, font: NSFont, spacing: CGFloat? = nil) -> CGFloat {
        let spacing = spacing ?? ("\u{00A0}" as NSString).size(withAttributes: [.font: font]).width
        return CGFloat(iconCount) * iconSize + CGFloat(max(0, iconCount - 1)) * spacing
    }

    static func visibleCount(total: Int, availableWidth: CGFloat, iconSize: CGFloat, font: NSFont, spacing: CGFloat? = nil) -> Int? {
        guard total > 0, availableWidth > 0 else { return nil }
        var count = min(total, Int(availableWidth / iconSize))
        while count >= 0 {
            let remaining = total - count
            let suffix = remaining > 0 ? (count > 0 ? " +\(remaining)" : "+\(remaining)") : ""
            var required = width(iconCount: count, iconSize: iconSize, font: font, spacing: spacing) +
                (suffix as NSString).size(withAttributes: [.font: font]).width
            if let spacing, remaining > 0, count > 0 {
                required += spacing - (" " as NSString).size(withAttributes: [.font: font]).width
            }
            if required <= availableWidth { return count }
            count -= 1
        }
        return nil
    }

    static func attributedIcons(_ icons: [NSImage], iconSize: CGFloat = menuIconSize,
                                maximumVisible: Int, leadingSpaces: Int = 2) -> NSAttributedString
    {
        let result = NSMutableAttributedString()
        let visible = min(icons.count, max(0, maximumVisible))
        for (index, image) in icons.prefix(visible).enumerated() {
            result.append(NSAttributedString(string: String(repeating: "\u{00A0}", count: index == 0 ? leadingSpaces : 1)))
            let attachment = NSTextAttachment()
            attachment.image = image.resizedToFit(in: NSSize(width: iconSize, height: iconSize))
            attachment.bounds = NSRect(x: 0, y: -3 * iconSize / menuIconSize, width: iconSize, height: iconSize)
            result.append(NSAttributedString(attachment: attachment))
        }
        let hidden = icons.count - visible
        if hidden > 0 {
            result.append(NSAttributedString(string: "\(visible > 0 || leadingSpaces > 0 ? " " : "")+\(hidden)"))
        }
        return result
    }
}

struct PreviewSelectedAppIcons: NSViewRepresentable {
    let pids: [pid_t]
    let font: NSFont

    func makeNSView(context: Context) -> SelectedAppIconStripView { SelectedAppIconStripView() }

    func updateNSView(_ nsView: SelectedAppIconStripView, context: Context) {
        nsView.configure(pids: pids, font: font)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SelectedAppIconStripView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: ceil(font.ascender - font.descender))
    }
}

final class SelectedAppIconStripView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let separator = NSBox()
    private var windowPIDs: [pid_t] = []
    private var icons: [NSImage] = []
    private var textFont: NSFont?
    private var visibleIconCount: Int?
    private var fullIconText = NSAttributedString(string: "")
    private var fullIconWidth: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        separator.boxType = .separator
        separator.isHidden = true
        label.alignment = .right
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.isSelectable = false
        label.isEditable = false
        label.setAccessibilityElement(false)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        addSubview(separator)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: textFont.map { ceil($0.ascender - $0.descender) } ?? 0)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        let previousSize = frame.size
        super.setFrameSize(newSize)
        if previousSize != newSize { needsLayout = true }
    }

    func configure(pids: [pid_t], font: NSFont) {
        guard windowPIDs != pids || textFont != font else { return }
        windowPIDs = pids
        textFont = font
        label.font = font
        var appIcons: [pid_t: NSImage] = [:]
        var appNames: [pid_t: String] = [:]
        for pid in Set(pids) {
            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            appIcons[pid] = app.icon
            appNames[pid] = app.localizedName
        }
        let fallbackIcon = NSImage(named: NSImage.applicationIconName) ?? NSImage()
        icons = pids.map { appIcons[$0] ?? fallbackIcon }
        setAccessibilityLabel(String(localized: "Selected windows"))
        setAccessibilityValue(pids.compactMap { appNames[$0] }.joined(separator: ", "))
        fullIconText = formattedIcons(count: icons.count, font: font)
        fullIconWidth = fullIconText.size().width
        visibleIconCount = nil
        label.attributedStringValue = NSAttributedString(string: "")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let font = textFont else { return }
        let size = ceil(font.ascender - font.descender)
        let separatorWidth: CGFloat = 1
        label.frame = bounds
        let fullWidth = label.cell?.drawingRect(forBounds: label.bounds).width ?? label.bounds.width
        let overflows = fullIconWidth > fullWidth
        if overflows {
            let labelX = separatorWidth + PreviewHeaderLayout.labelSpacing
            label.frame = NSRect(x: labelX, y: 0, width: max(0, bounds.width - labelX), height: bounds.height)
        }
        separator.frame = NSRect(x: 0, y: (bounds.height - size) / 2, width: separatorWidth, height: size)
        let availableWidth = label.cell?.drawingRect(forBounds: label.bounds).width ?? label.bounds.width
        let count = overflows
            ? AppIconStripFormatting.visibleCount(total: icons.count, availableWidth: availableWidth, iconSize: size, font: font)
            : (icons.isEmpty ? nil : icons.count)
        if count != visibleIconCount {
            visibleIconCount = count
            if let count {
                label.attributedStringValue = count == icons.count ? fullIconText : formattedIcons(count: count, font: font)
            } else {
                label.attributedStringValue = NSAttributedString(string: "")
            }
        }
        separator.isHidden = !overflows || count == nil
    }

    private func formattedIcons(count: Int, font: NSFont) -> NSAttributedString {
        let size = ceil(font.ascender - font.descender)
        let text = NSMutableAttributedString(attributedString: AppIconStripFormatting.attributedIcons(icons, iconSize: size, maximumVisible: count, leadingSpaces: 0))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineBreakMode = .byClipping
        text.addAttributes([.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph], range: NSRange(location: 0, length: text.length))
        return text
    }
}

@MainActor
final class SpaceMoveMenuController: NSObject {
    static let shared = SpaceMoveMenuController()

    private weak var activeMenu: NSMenu?

    private struct MoveRequest {
        let window: WindowInfo
        let destination: ManagedSpaceDestination
        let dismissPreviews: (() -> Void)?
        let usesCheckedSelection: Bool
    }

    private struct FullscreenExitRequest {
        let window: WindowInfo
        let usesCheckedSelection: Bool
    }

    func present(for window: WindowInfo, dismissPreviews: (() -> Void)?) {
        let menu = makeMenu(for: window, dismissPreviews: dismissPreviews)
        guard !menu.items.isEmpty else { return }

        activeMenu?.cancelTracking()
        activeMenu = menu
        defer {
            if activeMenu === menu {
                activeMenu = nil
            }
        }

        if let event = NSApp.currentEvent,
           let contentView = event.window?.contentView
        {
            NSMenu.popUpContextMenu(menu, with: event, for: contentView)
        } else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    func dismiss() {
        activeMenu?.cancelTracking()
        activeMenu = nil
    }

    func makeMenu(for window: WindowInfo, dismissPreviews: (() -> Void)?, showShortcutHints: Bool = true) -> NSMenu {
        let menu = NSMenu(title: String(localized: "Move to Space", comment: "Space destination menu title"))
        let displays = WindowSpaces.managedDisplays(includeOwners: true)
        let sourceValidation = WindowSpaces.validateMoveSource(window, in: displays)
        let sourceSpaceIDs = WindowSpaces.sourceSpaceIDs(for: window)
        let targets = showShortcutHints ? SharedPreviewWindowCoordinator.activeInstance?.windowSwitcherCoordinator.checkedActionTargets(for: window) ?? [window] : [window]

        if sourceValidation == .fullscreen {
            let item = NSMenuItem(
                title: String(localized: "Exit Full Screen to move this window", comment: "Action that exits fullscreen before moving a window between Spaces"),
                action: #selector(exitFullScreen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = FullscreenExitRequest(window: window, usesCheckedSelection: showShortcutHints)
            menu.addItem(item)
            return menu
        }

        if sourceValidation == .multipleDesktopSpaces {
            addInformationalItem(
                String(localized: "Windows available on all Spaces cannot be moved", comment: "Unavailable Space movement explanation"),
                to: menu
            )
            return menu
        }

        let cachedWindows = WindowUtil.collapseNativeTabsIfNeeded(WindowUtil.getAllWindowsIgnoringSwitcherFilters())
        let presentation = ManagedSpacePresentation.snapshot(
            displays: displays,
            orderedWindows: cachedWindows
        )
        let showUnavailable = Defaults[.showUnavailableSpacesInMenu]
        let visibleDisplays = presentation.compactMap { display -> (String, [ManagedSpacePresentation.Entry])? in
            let spaces = display.spaces.filter { entry in
                !entry.isFullscreen || showUnavailable
            }
            return spaces.isEmpty ? nil : (display.name, spaces)
        }
        let showsDisplayHeadings = visibleDisplays.count > 1

        for (displayIndex, entry) in visibleDisplays.enumerated() {
            if displayIndex > 0 {
                menu.addItem(.separator())
            }
            if showsDisplayHeadings {
                addInformationalItem(entry.0, to: menu)
            }

            for presentedSpace in entry.1 {
                let destination = presentedSpace.destination
                let space = destination.space
                let apps = presentedSpace.apps
                let title = presentedSpace.title(mode: Defaults[.spaceMenuDisplayMode])
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.attributedTitle = attributedTitle(
                    title,
                    apps: apps,
                    includesFullscreenSymbol: presentedSpace.isFullscreen,
                    appearance: menu.effectiveAppearance
                )
                if presentedSpace.isCurrent,
                   Defaults[.showCurrentSpaceBadgeInMenu]
                {
                    if #available(macOS 14.0, *) {
                        item.badge = NSMenuItemBadge(
                            string: String(localized: "Current", comment: "Badge identifying the currently active Space")
                        )
                    } else {
                        item.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
                    }
                }

                if space.kind == .desktop {
                    let isCurrent = targets.count > 1
                        ? targets.allSatisfy { WindowSpaces.sourceSpaceIDs(for: $0).contains(space.id) }
                        : sourceSpaceIDs.contains(space.id)
                    item.state = isCurrent ? .on : .off
                    item.isEnabled = !isCurrent
                    if !isCurrent {
                        item.action = #selector(moveWindow(_:))
                        item.target = self
                        item.representedObject = MoveRequest(
                            window: window,
                            destination: destination,
                            dismissPreviews: dismissPreviews,
                            usesCheckedSelection: showShortcutHints
                        )
                    }
                } else {
                    item.isEnabled = false
                }

                if showShortcutHints {
                    applyNumberedSpaceShortcut(to: item, spaceNumber: space.number)
                }

                menu.addItem(item)
            }
        }

        if menu.items.isEmpty {
            addInformationalItem(
                String(localized: "No available Spaces", comment: "Empty Space destination menu"),
                to: menu
            )
        }
        return menu
    }

    private func attributedTitle(
        _ title: String,
        apps: [ManagedSpacePresentation.App],
        includesFullscreenSymbol: Bool,
        appearance: NSAppearance
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: title)
        var attachmentCount = 0

        func appendImage(_ image: NSImage, usesPrimaryColor: Bool = false) {
            result.append(NSAttributedString(string: attachmentCount == 0 ? "\u{00A0}\u{00A0}" : "\u{00A0}"))
            let attachment = NSTextAttachment()
            let resizedImage = image.resizedToFit(in: NSSize(width: AppIconStripFormatting.menuIconSize, height: AppIconStripFormatting.menuIconSize))
            var attachmentImage = resizedImage
            if usesPrimaryColor {
                appearance.performAsCurrentDrawingAppearance {
                    attachmentImage = resizedImage.tint(color: .labelColor)
                }
            }
            attachment.image = attachmentImage
            attachment.bounds = NSRect(x: 0, y: -3, width: AppIconStripFormatting.menuIconSize, height: AppIconStripFormatting.menuIconSize)
            result.append(NSAttributedString(attachment: attachment))
            attachmentCount += 1
        }

        if includesFullscreenSymbol,
           let symbol = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)
        {
            appendImage(symbol, usesPrimaryColor: true)
        }

        let appIcons = apps.compactMap(\.application.icon)
        result.append(AppIconStripFormatting.attributedIcons(appIcons, maximumVisible: max(0, 5 - attachmentCount), leadingSpaces: attachmentCount == 0 ? 2 : 1))
        return result
    }

    private func addInformationalItem(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private func applyNumberedSpaceShortcut(to item: NSMenuItem, spaceNumber: Int) {
        guard Defaults[.enableSpacesShortcuts],
              (1 ... 10).contains(spaceNumber)
        else { return }

        let keybind = SharedPreviewWindowCoordinator.activeInstance?.effectivePreviewShortcutKeybind(forSpaces: true)
            ?? WindowSwitcherShortcutResolver.dependentShortcutKeybind(Defaults[.UserKeybind])
        item.keyEquivalent = spaceNumber == 10 ? "0" : String(spaceNumber)
        item.keyEquivalentModifierMask = WindowSwitcherShortcutResolver.appKitModifierMask(for: keybind)
    }

    @objc private func moveWindow(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? MoveRequest else { return }
        if request.usesCheckedSelection,
           SharedPreviewWindowCoordinator.activeInstance?.performCheckedSpaceMove(request.window, to: request.destination, dismissPreviews: request.dismissPreviews) == true
        { return }
        let feedback = ActionFeedbackController.space(request.destination.space.number, window: request.window, keyboard: NSApp.currentEvent?.type == .keyDown, usePreviews: request.usesCheckedSelection)
        WindowUtil.performConfirmedSpaceMove(
            request.window,
            to: request.destination,
            dismissPreviews: request.dismissPreviews,
            feedback: feedback,
            completion: { success in feedback?.finishRemaining(success ? .completed : .failed) }
        )
    }

    @objc private func exitFullScreen(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? FullscreenExitRequest else { return }
        if request.usesCheckedSelection,
           SharedPreviewWindowCoordinator.activeInstance?.performCheckedWindowAction(.toggleFullScreen, on: request.window, preservePreviews: true) != nil
        { return }
        let feedback = ActionFeedbackController.begin(.toggleFullScreen, windows: [request.window], keyboard: NSApp.currentEvent?.type == .keyDown, usePreviews: request.usesCheckedSelection)
        Task { @MainActor in
            let confirmed = await WindowUtil.exitFullScreenWithoutActivation(request.window)
            feedback?.finishRemaining(Task.isCancelled ? .cancelled : (confirmed ? .completed : .failed))
            if !confirmed, !Task.isCancelled { NSSound.beep() }
        }
    }
}

struct SpaceMoveIndicatorControl<Label: View>: View {
    let window: WindowInfo
    let spaceNumber: Int?
    let isEnabled: Bool
    let dismissPreviews: (() -> Void)?
    let label: Label

    init(
        window: WindowInfo,
        spaceNumber: Int?,
        isEnabled: Bool,
        dismissPreviews: (() -> Void)?,
        @ViewBuilder label: () -> Label
    ) {
        self.window = window
        self.spaceNumber = spaceNumber
        self.isEnabled = isEnabled
        self.dismissPreviews = dismissPreviews
        self.label = label()
    }

    var body: some View {
        if isEnabled, spaceNumber != nil {
            Button {
                SpaceMoveMenuController.shared.present(for: window, dismissPreviews: dismissPreviews)
            } label: {
                label
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture())
            .accessibilityLabel(Text("Move window to another Space"))
        } else {
            label
        }
    }
}

func resolvedTrafficLightButtons(
    for windowInfo: WindowInfo,
    configuredButtons: Set<WindowAction>,
    showWindowlessQuitButton: Bool
) -> Set<WindowAction> {
    if windowInfo.isWindowlessApp {
        return showWindowlessQuitButton ? configuredButtons.intersection([.quit]) : []
    }
    if windowInfo.isWineWindow {
        return configuredButtons.filter { $0.isSupported(for: windowInfo) }
    }
    if windowInfo.hasLimitedWindowControls {
        return configuredButtons.intersection([.quit, .close])
    }
    guard windowInfo.closeButton != nil || windowInfo.isMinimized || windowInfo.isEffectivelyHiddenForUI else {
        return configuredButtons.intersection([.quit])
    }
    return configuredButtons
}

enum WindowStateSymbolResolver {
    static func labels(for window: WindowInfo) -> [String] {
        var labels: [String] = []
        if window.isWindowlessApp { labels.append(String(localized: "No Open Windows")) }
        if window.isMinimized { labels.append(String(localized: "Minimized")) }
        if window.isEffectivelyHiddenForUI { labels.append(String(localized: "Hidden")) }
        if window.isFullscreen == true { labels.append(String(localized: "Full Screen")) }
        return labels
    }

    static func symbols(
        for windowInfo: WindowInfo,
        isEffectivelyHidden: Bool
    ) -> [String] {
        if windowInfo.isMinimized {
            return ["minus.circle"]
        } else if isEffectivelyHidden {
            return ["eye.slash"]
        } else if windowInfo.isFullscreen == true {
            return ["arrow.up.left.and.arrow.down.right"]
        }
        return []
    }
}

enum PreviewToolbarStage: Hashable {
    case full, titlesOmitted, actionsMenu, actionsMenuWithoutTitles, indicatorsMenu, indicatorsMenuWithoutTitles, combined
    case partialActions(count: Int, showsTitles: Bool)

    var showsTitles: Bool {
        if case let .partialActions(_, showsTitles) = self { return showsTitles }
        return self == .full || self == .actionsMenu || self == .indicatorsMenu
    }

    private var visibleActionCount: Int? {
        switch self {
        case .full, .titlesOmitted: nil
        case let .partialActions(count, _): count
        default: 0
        }
    }

    var overflowsActions: Bool { visibleActionCount != nil }
    var showsTrafficLights: Bool { visibleActionCount != 0 }
    var overflowsIndicators: Bool { self == .indicatorsMenu || self == .indicatorsMenuWithoutTitles || self == .combined }

    func visibleActions(in actions: Set<WindowAction>) -> Set<WindowAction> {
        guard let visibleActionCount else { return actions }
        return Set(TrafficLightButtons.actionOrder.filter(actions.contains).prefix(visibleActionCount))
    }

    func overflowActions(in actions: Set<WindowAction>) -> Set<WindowAction> {
        actions.subtracting(visibleActions(in: actions))
    }
}

private struct PreviewToolbarStageKey: PreferenceKey {
    static var defaultValue: PreviewToolbarStage? { nil }

    static func reduce(value: inout PreviewToolbarStage?, nextValue: () -> PreviewToolbarStage?) {
        value = nextValue() ?? value
    }
}

struct PreviewAdaptiveToolbar<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage: PreviewToolbarStage?

    var allowsTitleOmission = false
    var partialActionCounts: [Int] = []
    let controlsVisible: Bool
    let animationDuration: Double
    let animationsEnabled: Bool
    @ViewBuilder let content: (_ stage: PreviewToolbarStage, _ isMeasuring: Bool) -> Content

    var body: some View {
        // Measure current content separately without replacing the rendered row.
        ViewThatFits(in: .horizontal) {
            measuredRow(.full)
            if allowsTitleOmission { measuredRow(.titlesOmitted) }
            ForEach(partialActionCounts, id: \.self) { count in
                measuredRow(.partialActions(count: count, showsTitles: true))
                if allowsTitleOmission { measuredRow(.partialActions(count: count, showsTitles: false)) }
            }
            measuredRow(.actionsMenu)
            if allowsTitleOmission { measuredRow(.actionsMenuWithoutTitles) }
            measuredRow(.indicatorsMenu)
            if allowsTitleOmission { measuredRow(.indicatorsMenuWithoutTitles) }
            measuredRow(.combined)
        }
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .transaction { $0.disablesAnimations = true }
        .overlay {
            if let stage { content(stage, false) }
        }
        .onPreferenceChange(PreviewToolbarStageKey.self) { newStage in
            guard let newStage, newStage != stage else { return }
            let animation = stage == nil ? nil : PreviewControlAnimation.animation(
                duration: animationDuration, animationsEnabled: animationsEnabled, reduceMotion: reduceMotion
            )
            withAnimation(animation) { stage = newStage }
        }
        .previewControlVisibilityAnimation(isVisible: controlsVisible, duration: animationDuration, animationsEnabled: animationsEnabled)
    }

    private func measuredRow(_ stage: PreviewToolbarStage) -> some View {
        content(stage, true).preference(key: PreviewToolbarStageKey.self, value: stage)
    }
}

struct PreviewToolbarTitle<Content: View>: View {
    var font: Font = .body
    @ViewBuilder let content: () -> Content

    var body: some View {
        PreviewToolbarTitleLayout {
            content()
            Text(verbatim: "\u{2026}").fixedSize().hidden().accessibilityHidden(true)
        }
        .font(font)
    }
}

private struct PreviewToolbarTitleLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let minimum = subviews[1].sizeThatFits(.unspecified).width
        let naturalWidth = subviews[0].sizeThatFits(.unspecified).width
        // Fitting tests need only an ellipsis; finite proposals retain the title's intrinsic width.
        let width = proposal.width.map { max(minimum, min($0, naturalWidth)) } ?? minimum
        let size = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

struct PreviewControlOverflow {
    let actions: Set<WindowAction>
    let includesIndicator: Bool
    let includesSelection: Bool
    let spaceNumber: Int?
    let allowsSpaceMoving: Bool
}

struct PreviewControlReplacement<Controls: View, Replacement: View>: View {
    let controlsVisible: Bool
    let replacementVisible: Bool
    let spacing: CGFloat
    var usesControlsContrastShadow = false
    @ViewBuilder let controls: () -> Controls
    @ViewBuilder let replacement: () -> Replacement

    var body: some View {
        HStack(spacing: controlsVisible && replacementVisible ? spacing : 0) {
            controls().previewControlVisibility(isVisible: controlsVisible)
                .embeddedPreviewContrastShadow(usesControlsContrastShadow)
            replacement().previewControlVisibility(isVisible: replacementVisible)
        }
    }
}

struct PreviewOverflowButton: View {
    @State private var isHovering = false

    let window: WindowInfo
    let appearance: PreviewAppearanceSettings
    let backgroundAppearance: BackgroundAppearance
    let overflow: PreviewControlOverflow
    let circularDiameter: CGFloat?
    var usesCircularMaterial = true
    let isChecked: Bool
    let mockPreviewActive: Bool
    let handleWindowAction: (WindowAction) -> Void
    let dismissPreviews: (() -> Void)?

    var body: some View {
        Button {
            PreviewContextMenuController.shared.presentOverflow(for: window, overflow: overflow,
                                                                handleWindowAction: handleWindowAction, dismissPreviews: dismissPreviews)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: circularDiameter.map { $0 * 0.55 } ?? 13 * appearance.trafficLightButtonScale, weight: .bold))
                .opacity(circularDiameter == nil && !mockPreviewActive && !isHovering &&
                    (appearance.trafficLightVisibility == .dimmedOnPreviewHover || appearance.trafficLightVisibility == .dimmedUntilButtonHover) ? 0.25 : 1)
                .frame(width: circularDiameter ?? TrafficLightButtons.buttonFrameSize * appearance.trafficLightButtonScale,
                       height: circularDiameter ?? TrafficLightButtons.buttonFrameSize * appearance.trafficLightButtonScale)
                .padding(circularDiameter == nil ? TrafficLightButtons.contentPadding : 0)
                .if(circularDiameter != nil) {
                    $0.background {
                        if usesCircularMaterial { Color.clear.materialPill(backgroundAppearance: backgroundAppearance) }
                    }
                    .clipShape(Circle())
                    .overlay { if isChecked { Circle().strokeBorder(appearance.activeAppIndicatorColor, lineWidth: 2.5) } }
                    .contentShape(Circle())
                }
                .if(circularDiameter == nil && !appearance.disableDockStyleTrafficLights) {
                    $0.materialPill(backgroundAppearance: backgroundAppearance)
                }
                .embeddedPreviewContrastShadow(appearance.usesEmbeddedTrafficLightContrastShadow)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .previewControlVisibilityAnimation(isVisible: isHovering, duration: appearance.trafficLightTransitionDuration, animationsEnabled: appearance.showAnimations)
        .help(String(localized: "More window actions"))
        .accessibilityLabel(String(localized: "More window actions"))
        .accessibilityAddTraits(isChecked && overflow.includesSelection ? .isSelected : [])
        .fixedSize()
        .allowsHitTesting(!mockPreviewActive)
    }
}

private struct EmbeddedPreviewContrastShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.shadow(
                color: colorScheme == .dark ? .black.opacity(0.6) : .white.opacity(0.85),
                radius: 3,
                y: 2
            )
        } else {
            content
        }
    }
}

private struct EmbeddedSwitcherTitleShadow: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.appHeaderTextShadow(color: colorScheme == .dark ? .black : .white)
        } else {
            content
        }
    }
}

extension View {
    func previewControlVisibility(isVisible: Bool) -> some View {
        frame(width: isVisible ? nil : 0)
            .clipped()
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
    }

    func embeddedPreviewContrastShadow(_ isEnabled: Bool) -> some View {
        modifier(EmbeddedPreviewContrastShadow(isEnabled: isEnabled))
    }
}

struct WindowStateIndicator: View {
    static let unstyledControlLineHeight: CGFloat = 24
    private static let styledBadgeMinimumSize: CGFloat = 14
    static let styledContentPadding: CGFloat = 4
    static var styledMinimumAspectRatio: CGFloat {
        let content = fontMetrics[.system]!.styledMinimumSize + 2 * styledContentPadding
        return (content + 2 * MaterialPillStyle.horizontalInset) / (content + 2 * MaterialPillStyle.verticalInset)
    }

    private struct FontMetrics {
        let pointSize: CGFloat
        let lineHeight: CGFloat

        var circleSize: CGFloat { max(18, lineHeight + 4) }
        var styledMinimumSize: CGFloat { max(styledBadgeMinimumSize, lineHeight) }
        var unstyledHeight: CGFloat { max(unstyledControlLineHeight, circleSize + 6) }
    }

    private static let fontMetrics = Dictionary(uniqueKeysWithValues: WindowTitleFontSize.allCases.map { size in
        let pointSize: CGFloat = size == .system ? 10 : NSFont.preferredFont(forTextStyle: size.appKitTextStyle, options: [:]).pointSize
        let font = NSFont.systemFont(ofSize: pointSize, weight: .semibold)
        return (size, FontMetrics(pointSize: pointSize, lineHeight: ceil(font.ascender - font.descender + font.leading)))
    })

    static func controlHeight(disableDockStyling: Bool, fontSize: WindowTitleFontSize) -> CGFloat {
        let metrics = fontMetrics[fontSize]!
        if disableDockStyling {
            return metrics.unstyledHeight
        }
        return metrics.styledMinimumSize + 2 * styledContentPadding + 2 * MaterialPillStyle.verticalPadding
    }

    let number: Int?
    let stateSymbols: [String]
    let disableDockStyling: Bool
    let fontSize: WindowTitleFontSize
    let backgroundAppearance: BackgroundAppearance
    let highlightsCurrentSpace: Bool
    let highlightColor: Color
    let highlightOpacity: Double
    let activeBorderColor: Color

    private var metrics: FontMetrics { Self.fontMetrics[fontSize]! }
    private var indicatorFont: Font { .system(size: metrics.pointSize, weight: .semibold, design: .rounded) }

    @ViewBuilder
    private func badgeContent(minimumWidth: CGFloat?, minimumHeight: CGFloat) -> some View {
        if let number {
            Text("\(number)")
                .font(indicatorFont)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .frame(minWidth: minimumWidth, minHeight: minimumHeight)
                .padding(.horizontal, number > 9 ? 2 : 0)
        }
    }

    @ViewBuilder
    private func stateIcons() -> some View {
        ForEach(stateSymbols, id: \.self) { symbol in
            Image(systemName: symbol)
                .font(indicatorFont)
                .foregroundStyle(.primary)
        }
    }

    var body: some View {
        Group {
            if disableDockStyling {
                HStack(spacing: 4) {
                    if number != nil {
                        badgeContent(minimumWidth: metrics.circleSize, minimumHeight: metrics.circleSize)
                            .overlay {
                                Capsule().strokeBorder(
                                    highlightsCurrentSpace ? activeBorderColor : .secondary,
                                    lineWidth: highlightsCurrentSpace ? 2.5 : 1
                                )
                            }
                    }
                    stateIcons()
                }
                .frame(height: metrics.unstyledHeight)
            } else {
                HStack(spacing: 4) {
                    badgeContent(minimumWidth: nil, minimumHeight: 0)
                    stateIcons()
                }
                .frame(
                    minWidth: metrics.styledMinimumSize,
                    minHeight: metrics.styledMinimumSize
                )
                .padding(Self.styledContentPadding)
                .materialPill(
                    backgroundAppearance: backgroundAppearance,
                    highlightColor: highlightsCurrentSpace ? highlightColor : nil,
                    highlightOpacity: highlightOpacity
                )
            }
        }
        .accessibilityLabel(Text(number.map { "Space \($0), window state" } ?? "Window state"))
    }
}

struct PreviewSelectionInteraction {
    let isDragOrigin: Bool
    let toggle: () -> Void
    let drag: AnyGesture<DragGesture.Value>
    let end: () -> Void
}

struct PreviewSelectionCheckbox: View {
    let isChecked: Bool
    let isVisible: Bool
    let color: Color
    var diameter: CGFloat = 20
    var drawingScale: CGFloat = 1
    var backgroundAppearance: BackgroundAppearance? = nil
    var animationsEnabled: Bool = false
    var interaction: PreviewSelectionInteraction? = nil
    let toggle: () -> Void
    @GestureState private var isSelecting = false

    static func iconDiameter(for iconSize: CGFloat) -> CGFloat {
        20 + max(0, iconSize - 16) / 4
    }

    var body: some View {
        ZStack {
            if isVisible {
                Button(action: { if !isSelecting { (interaction?.toggle ?? toggle)() } }) {
                    Circle()
                        .fill(isChecked ? color : Color.clear)
                        .overlay {
                            Circle().strokeBorder(Color.secondary, lineWidth: 1)
                            if isChecked {
                                Image(systemName: "checkmark")
                                    .font(.system(size: diameter * 0.55, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: diameter, height: diameter)
                        .background {
                            if let backgroundAppearance {
                                Color.clear
                                    .frame(width: max(0, diameter - 2 * MaterialPillStyle.horizontalPadding),
                                           height: max(0, diameter - 2 * MaterialPillStyle.verticalPadding))
                                    .materialPill(backgroundAppearance: backgroundAppearance)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .highPriorityGesture(interaction?.drag.updating($isSelecting) { _, selecting, _ in selecting = true })
                .scaleEffect(drawingScale)
                .accessibilityLabel(isChecked ? String(localized: "Remove window from selection") : String(localized: "Add window to selection"))
                .accessibilityAddTraits(isChecked ? .isSelected : [])
                .transition(.opacity)
            }
        }
        .onChange(of: isSelecting) { selecting in if !selecting { interaction?.end() } }
        .onDisappear { if isSelecting { interaction?.end() } }
        .previewControlVisibilityAnimation(isVisible: isVisible, duration: 0.15, animationsEnabled: animationsEnabled)
    }
}

struct PreviewAppearanceSettings: Equatable {
    let enableMultiWindowSelection: Bool
    let enableWindowlessAppSelection: Bool
    let enableWindowDragTiling: Bool
    let showWindowSelectionSummary: Bool
    let showUncheckedSelectionCheckboxes: Bool
    let selectionCheckboxVisibility: SelectionCheckboxVisibility
    let trafficLightVisibility: TrafficLightButtonsVisibility
    let enabledTrafficLightButtons: Set<WindowAction>
    let useMonochromeTrafficLights: Bool
    let showAppHeader: Bool
    let showAppIconBadges: Bool
    let showCompactAppIconBadges: Bool
    let appIconBadgeScale: CGFloat
    let showWindowTitle: Bool
    let windowTitleVisibility: WindowTitleVisibility
    let controlPosition: WindowSwitcherControlPosition
    let useEmbeddedElements: Bool
    let disableDockStyleTrafficLights: Bool
    let disableDockStyleTitles: Bool
    let dimMinimizedHiddenPreviews: Bool
    let selectionOpacity: Double
    let unselectedContentOpacity: Double
    let hoverHighlightColor: Color?
    let allowDynamicImageSizing: Bool
    let hidePreviewCardBackground: Bool
    let tapEquivalentInterval: Double
    let previewHoverAction: PreviewHoverAction
    let keepPreviewOnHoverActivation: Bool
    let showActiveWindowBorder: Bool
    let activeAppIndicatorColor: Color
    let showAnimations: Bool
    let trafficLightTransitionDuration: Double
    let globalPaddingMultiplier: CGFloat
    let radii: CardRadius.Resolved
    let windowTitleFontSize: WindowTitleFontSize
    let windowStateIndicatorFontSize: WindowTitleFontSize
    let switcherAppIconSize: CGFloat
    let trafficLightButtonScale: CGFloat
    let livePreviewQuality: LivePreviewQuality
    let livePreviewFrameRate: LivePreviewFrameRate
    let previewWidth: CGFloat
    let compactModeWidth: CGFloat
    let compactModeTitleFormat: CompactModeTitleFormat
    let compactModeItemSize: CompactModeItemSize
    let compactModeHideTrafficLights: Bool
    let showSpaceNumberIndicator: Bool
    let enableSpaceIndicatorWindowMoving: Bool
    let highlightCurrentSpaceNumberIndicator: Bool
    let windowStateIndicatorPlacement: WindowStateIndicatorPlacement
    let disableDockStyleWindowStateIndicator: Bool
    let swapTrafficLightsAndWindowStateIndicator: Bool
    let limitIndicatorSwapToCompactMode: Bool
    let showFullSizeWindowlessPreviews: Bool
    let showWindowlessAppQuitButton: Bool
    let titleOverflowStyle: TitleOverflowStyle

    var controlElementSpacing: CGFloat {
        disableDockStyleTrafficLights ? 6 : 8
    }

    func partialTrafficLightCounts(for actions: Set<WindowAction>, isVisible: Bool) -> [Int] {
        guard isVisible else { return [] }
        return TrafficLightButtons.partialOverflowCounts(for: actions, buttonScale: trafficLightButtonScale,
                                                         pillStyling: !disableDockStyleTrafficLights, spacing: controlElementSpacing)
    }

    func resolvedSwitcherAppIconSize(windowTitleIsVisible: Bool) -> CGFloat {
        if switcherAppIconSize > 0 {
            return min(max(switcherAppIconSize, 16), 64)
        }
        return windowTitleIsVisible ? 35 : 20
    }

    var isDiagonalPosition: Bool {
        switch controlPosition {
        case .diagonalTopLeftBottomRight, .diagonalTopRightBottomLeft,
             .diagonalBottomLeftTopRight, .diagonalBottomRightTopLeft:
            true
        default:
            false
        }
    }

    var usesEmbeddedTitleContrastShadow: Bool {
        useEmbeddedElements && disableDockStyleTitles
    }

    var usesEmbeddedTrafficLightContrastShadow: Bool {
        useEmbeddedElements && disableDockStyleTrafficLights
    }

    var usesEmbeddedWindowStateContrastShadow: Bool {
        useEmbeddedElements && disableDockStyleWindowStateIndicator
    }

    var windowStateIndicatorControlHeight: CGFloat {
        WindowStateIndicator.controlHeight(disableDockStyling: disableDockStyleWindowStateIndicator, fontSize: windowStateIndicatorFontSize)
    }

    func compactRowHeight(hasWindowStateIndicator: Bool) -> CGFloat {
        max(compactModeItemSize.rowHeight, hasWindowStateIndicator ? windowStateIndicatorControlHeight + 2 : 0)
    }

    func compactControlAlignmentEdgeInset(
        hasWindowStateIndicator: Bool,
        hasTrafficLightButtons: Bool,
        windowStateIndicatorIsOutermost: Bool
    ) -> CGFloat {
        let outerControlHeight: CGFloat? = if windowStateIndicatorIsOutermost {
            windowStateIndicatorControlHeight
        } else if hasTrafficLightButtons {
            TrafficLightButtons.controlHeight(
                buttonScale: trafficLightButtonScale,
                pillStyling: !disableDockStyleTrafficLights
            )
        } else if hasWindowStateIndicator {
            windowStateIndicatorControlHeight
        } else {
            nil
        }
        guard let outerControlHeight else { return 0 }

        let outerControlUsesPill = windowStateIndicatorIsOutermost
            ? !disableDockStyleWindowStateIndicator
            : hasTrafficLightButtons && !disableDockStyleTrafficLights
        let opticalInset: CGFloat = windowStateIndicatorIsOutermost && disableDockStyleWindowStateIndicator ? 2 : 0
        let pillInsetReduction: CGFloat = outerControlUsesPill ? 1 : 0
        let edgeInset = max(
            0,
            (compactRowHeight(hasWindowStateIndicator: hasWindowStateIndicator) - outerControlHeight) / 2 - pillInsetReduction + opticalInset
        )
        return max(-CGFloat(CardRadius.innerPadding), edgeInset - CGFloat(CardRadius.innerPadding))
    }

    static var observedKeys: [Defaults._AnyKey] {
        let keys: [Defaults._AnyKey] = [
            .enableMultiWindowSelection,
            .enableWindowDragTiling,
            .trafficLightButtonsVisibility, .switcherTrafficLightButtonsVisibility, .cmdTabTrafficLightButtonsVisibility,
            .enabledTrafficLightButtons, .switcherEnabledTrafficLightButtons, .cmdTabEnabledTrafficLightButtons,
            .useMonochromeTrafficLights, .switcherUseMonochromeTrafficLights, .cmdTabUseMonochromeTrafficLights,
            .switcherShowAppHeader,
            .switcherShowAppIconBadges, .switcherShowCompactAppIconBadges, .switcherAppIconBadgeScale,
            .showWindowTitle, .switcherShowWindowTitle, .cmdTabShowWindowTitle,
            .windowTitleVisibility, .switcherWindowTitleVisibility, .cmdTabWindowTitleVisibility,
            .dockPreviewControlPosition, .windowSwitcherControlPosition, .cmdTabControlPosition,
            .useEmbeddedDockPreviewElements, .switcherUseEmbeddedDockPreviewElements, .cmdTabUseEmbeddedDockPreviewElements,
            .disableDockStyleTrafficLights, .switcherDisableDockStyleTrafficLights, .cmdTabDisableDockStyleTrafficLights,
            .disableDockStyleTitles, .cmdTabDisableDockStyleTitles,
            .dockLivePreviewQuality, .windowSwitcherLivePreviewQuality,
            .dockLivePreviewFrameRate, .windowSwitcherLivePreviewFrameRate,
            .showDockPreviewSpaceNumberIndicator, .showSwitcherSpaceNumberIndicator, .showCmdTabSpaceNumberIndicator,
            .enableSpaceIndicatorWindowMoving,
            .highlightDockPreviewCurrentSpaceIndicator, .highlightSwitcherCurrentSpaceIndicator, .highlightCmdTabCurrentSpaceIndicator,
            .dockPreviewWindowStateIndicatorPlacement, .switcherWindowStateIndicatorPlacement, .cmdTabWindowStateIndicatorPlacement,
            .disableDockStyleWindowStateIndicator, .switcherDisableDockStyleWindowStateIndicator, .cmdTabDisableDockStyleWindowStateIndicator,
            .swapDockPreviewTrafficLightsAndWindowStateIndicator, .swapSwitcherTrafficLightsAndWindowStateIndicator, .swapCmdTabTrafficLightsAndWindowStateIndicator,
            .limitDockPreviewIndicatorSwapToCompactMode, .limitSwitcherIndicatorSwapToCompactMode, .limitCmdTabIndicatorSwapToCompactMode,
            .dimMinimizedHiddenPreviews, .selectionOpacity, .unselectedContentOpacity, .hoverHighlightColor,
            .allowDynamicImageSizing, .hidePreviewCardBackground,
            .tapEquivalentInterval, .switcherTapEquivalentInterval, .cmdTabTapEquivalentInterval,
            .previewHoverAction, .switcherPreviewHoverAction, .cmdTabPreviewHoverAction,
            .keepPreviewOnHoverActivation,
            .showActiveWindowBorder, .activeAppIndicatorColor, .showAnimations, .trafficLightTransitionDuration, .globalPaddingMultiplier,
            .uniformCardRadius, .previewCornerRadius,
            .windowTitleFontSize, .windowStateIndicatorFontSize, .switcherAppIconSize, .trafficLightButtonScale,
            .previewWidth, .compactModeWidth, .compactModeTitleFormat, .compactModeItemSize, .compactModeHideTrafficLights,
            .showFullSizeWindowlessDockPreviews, .showFullSizeWindowlessCmdTabPreviews,
            .showWindowlessAppQuitButton, .titleOverflowStyle,
        ]
        return keys + (Defaults[.enableMultiWindowSelection]
            ? [.enableWindowlessAppSelection, .showUncheckedSelectionCheckboxes, .selectionCheckboxVisibility, .showWindowSelectionSummary] : [])
    }

    static func resolve(windowSwitcherActive: Bool, dockPosition: DockPosition) -> PreviewAppearanceSettings {
        let isCmdTab = dockPosition == .cmdTab
        func pick<T: Defaults.Serializable>(
            _ base: Defaults.Key<T>,
            switcher: Defaults.Key<T>? = nil,
            cmdTab: Defaults.Key<T>? = nil
        ) -> T {
            if windowSwitcherActive, let switcher { return Defaults[switcher] }
            if isCmdTab, let cmdTab { return Defaults[cmdTab] }
            return Defaults[base]
        }

        let selectionEnabled = Defaults[.enableMultiWindowSelection]
        return PreviewAppearanceSettings(
            enableMultiWindowSelection: selectionEnabled,
            enableWindowlessAppSelection: selectionEnabled && windowSwitcherActive && Defaults[.enableWindowlessAppSelection],
            enableWindowDragTiling: Defaults[.enableWindowDragTiling],
            showWindowSelectionSummary: selectionEnabled && Defaults[.showWindowSelectionSummary],
            showUncheckedSelectionCheckboxes: selectionEnabled ? Defaults[.showUncheckedSelectionCheckboxes] : Defaults.Keys.showUncheckedSelectionCheckboxes.defaultValue,
            selectionCheckboxVisibility: selectionEnabled ? Defaults[.selectionCheckboxVisibility] : Defaults.Keys.selectionCheckboxVisibility.defaultValue,
            trafficLightVisibility: pick(.trafficLightButtonsVisibility, switcher: .switcherTrafficLightButtonsVisibility, cmdTab: .cmdTabTrafficLightButtonsVisibility),
            enabledTrafficLightButtons: pick(.enabledTrafficLightButtons, switcher: .switcherEnabledTrafficLightButtons, cmdTab: .cmdTabEnabledTrafficLightButtons),
            useMonochromeTrafficLights: pick(.useMonochromeTrafficLights, switcher: .switcherUseMonochromeTrafficLights, cmdTab: .cmdTabUseMonochromeTrafficLights),
            showAppHeader: windowSwitcherActive ? Defaults[.switcherShowAppHeader] : true,
            showAppIconBadges: windowSwitcherActive && Defaults[.switcherShowAppIconBadges],
            showCompactAppIconBadges: windowSwitcherActive && Defaults[.switcherShowCompactAppIconBadges],
            appIconBadgeScale: Defaults[.switcherAppIconBadgeScale],
            showWindowTitle: pick(.showWindowTitle, switcher: .switcherShowWindowTitle, cmdTab: .cmdTabShowWindowTitle),
            windowTitleVisibility: pick(.windowTitleVisibility, switcher: .switcherWindowTitleVisibility, cmdTab: .cmdTabWindowTitleVisibility),
            controlPosition: pick(.dockPreviewControlPosition, switcher: .windowSwitcherControlPosition, cmdTab: .cmdTabControlPosition),
            useEmbeddedElements: pick(.useEmbeddedDockPreviewElements, switcher: .switcherUseEmbeddedDockPreviewElements, cmdTab: .cmdTabUseEmbeddedDockPreviewElements),
            disableDockStyleTrafficLights: pick(.disableDockStyleTrafficLights, switcher: .switcherDisableDockStyleTrafficLights, cmdTab: .cmdTabDisableDockStyleTrafficLights),
            disableDockStyleTitles: windowSwitcherActive ? true : pick(.disableDockStyleTitles, cmdTab: .cmdTabDisableDockStyleTitles),
            dimMinimizedHiddenPreviews: Defaults[.dimMinimizedHiddenPreviews],
            selectionOpacity: Defaults[.selectionOpacity],
            unselectedContentOpacity: Defaults[.unselectedContentOpacity],
            hoverHighlightColor: Defaults[.hoverHighlightColor],
            allowDynamicImageSizing: Defaults[.allowDynamicImageSizing],
            hidePreviewCardBackground: Defaults[.hidePreviewCardBackground],
            tapEquivalentInterval: pick(.tapEquivalentInterval, switcher: .switcherTapEquivalentInterval, cmdTab: .cmdTabTapEquivalentInterval),
            previewHoverAction: pick(.previewHoverAction, switcher: .switcherPreviewHoverAction, cmdTab: .cmdTabPreviewHoverAction),
            keepPreviewOnHoverActivation: Defaults[.keepPreviewOnHoverActivation],
            showActiveWindowBorder: Defaults[.showActiveWindowBorder],
            activeAppIndicatorColor: Defaults[.activeAppIndicatorColor],
            showAnimations: Defaults[.showAnimations],
            trafficLightTransitionDuration: Defaults[.trafficLightTransitionDuration],
            globalPaddingMultiplier: Defaults[.globalPaddingMultiplier],
            radii: .current(),
            windowTitleFontSize: Defaults[.windowTitleFontSize],
            windowStateIndicatorFontSize: Defaults[.windowStateIndicatorFontSize],
            switcherAppIconSize: Defaults[.switcherAppIconSize],
            trafficLightButtonScale: Defaults[.trafficLightButtonScale],
            livePreviewQuality: pick(.dockLivePreviewQuality, switcher: .windowSwitcherLivePreviewQuality),
            livePreviewFrameRate: pick(.dockLivePreviewFrameRate, switcher: .windowSwitcherLivePreviewFrameRate),
            previewWidth: Defaults[.previewWidth],
            compactModeWidth: Defaults[.compactModeWidth],
            compactModeTitleFormat: Defaults[.compactModeTitleFormat],
            compactModeItemSize: Defaults[.compactModeItemSize],
            compactModeHideTrafficLights: Defaults[.compactModeHideTrafficLights],
            showSpaceNumberIndicator: pick(.showDockPreviewSpaceNumberIndicator, switcher: .showSwitcherSpaceNumberIndicator, cmdTab: .showCmdTabSpaceNumberIndicator),
            enableSpaceIndicatorWindowMoving: Defaults[.enableSpaceIndicatorWindowMoving],
            highlightCurrentSpaceNumberIndicator: pick(.highlightDockPreviewCurrentSpaceIndicator, switcher: .highlightSwitcherCurrentSpaceIndicator, cmdTab: .highlightCmdTabCurrentSpaceIndicator),
            windowStateIndicatorPlacement: pick(.dockPreviewWindowStateIndicatorPlacement, switcher: .switcherWindowStateIndicatorPlacement, cmdTab: .cmdTabWindowStateIndicatorPlacement),
            disableDockStyleWindowStateIndicator: pick(.disableDockStyleWindowStateIndicator, switcher: .switcherDisableDockStyleWindowStateIndicator, cmdTab: .cmdTabDisableDockStyleWindowStateIndicator),
            swapTrafficLightsAndWindowStateIndicator: pick(.swapDockPreviewTrafficLightsAndWindowStateIndicator, switcher: .swapSwitcherTrafficLightsAndWindowStateIndicator, cmdTab: .swapCmdTabTrafficLightsAndWindowStateIndicator),
            limitIndicatorSwapToCompactMode: pick(.limitDockPreviewIndicatorSwapToCompactMode, switcher: .limitSwitcherIndicatorSwapToCompactMode, cmdTab: .limitCmdTabIndicatorSwapToCompactMode),
            showFullSizeWindowlessPreviews: (windowSwitcherActive && !isCmdTab) || pick(.showFullSizeWindowlessDockPreviews, cmdTab: .showFullSizeWindowlessCmdTabPreviews),
            showWindowlessAppQuitButton: Defaults[.showWindowlessAppQuitButton],
            titleOverflowStyle: Defaults[.titleOverflowStyle]
        )
    }
}

extension TrafficLightButtons {
    init(
        previewAppearance appearance: PreviewAppearanceSettings,
        hoveringOverParentWindow: Bool,
        onWindowAction: @escaping (WindowAction) -> Void,
        pillStyling: Bool? = nil,
        mockPreviewActive: Bool,
        enabledButtons: Set<WindowAction>,
        backgroundAppearance: BackgroundAppearance
    ) {
        self.init(
            displayMode: appearance.trafficLightVisibility,
            hoveringOverParentWindow: hoveringOverParentWindow,
            onWindowAction: onWindowAction,
            pillStyling: pillStyling ?? !appearance.disableDockStyleTrafficLights,
            mockPreviewActive: mockPreviewActive,
            enabledButtons: enabledButtons,
            useMonochrome: appearance.useMonochromeTrafficLights,
            buttonScale: appearance.trafficLightButtonScale,
            backgroundAppearance: backgroundAppearance
        )
    }
}

struct EmbeddedSwitcherControlsLayout<Content: View>: View {
    let controlPosition: WindowSwitcherControlPosition
    let hasTitleContent: Bool
    let hasControlsContent: Bool
    @ViewBuilder let content: (_ isLeadingControls: Bool, _ showTitle: Bool, _ showControls: Bool) -> Content

    var body: some View {
        VStack(spacing: 0) {
            if controlPosition.showsOnTop {
                let config = controlPosition.topConfiguration
                if (config.showTitle && hasTitleContent) || (config.showControls && hasControlsContent) {
                    content(config.isLeadingControls, config.showTitle, config.showControls)
                        .padding(8)
                }
            }

            Spacer()

            if controlPosition.showsOnBottom {
                let config = controlPosition.bottomConfiguration
                if (config.showTitle && hasTitleContent) || (config.showControls && hasControlsContent) {
                    content(config.isLeadingControls, config.showTitle, config.showControls)
                        .padding(8)
                }
            }
        }
    }
}

struct PreviewTitleCluster<Icon: View, Labels: View>: View {
    let iconOnRight: Bool
    @ViewBuilder let icon: () -> Icon
    @ViewBuilder let labels: () -> Labels

    var body: some View {
        HStack(spacing: 4) {
            if iconOnRight {
                labels()
                icon()
            } else {
                icon()
                labels()
            }
        }
    }
}

private extension WindowTitleFontSize {
    static let measuredLineHeights = Dictionary(uniqueKeysWithValues: allCases.map { size in
        let font = NSFont.preferredFont(forTextStyle: size.appKitTextStyle, options: [:])
        return (size, ceil(font.ascender - font.descender + font.leading))
    })

    static let bodyLineHeight = ceil(
        NSFont.preferredFont(forTextStyle: .body, options: [:]).boundingRectForFont.height
    )

    var measuredLineHeight: CGFloat {
        Self.measuredLineHeights[self] ?? Self.bodyLineHeight
    }

    var appKitTextStyle: NSFont.TextStyle {
        switch self {
        case .system, .subheadline: .subheadline
        case .caption2: .caption2
        case .caption: .caption1
        case .footnote: .footnote
        case .body: .body
        case .headline: .headline
        case .title3: .title3
        case .title2: .title2
        case .title: .title1
        }
    }
}

private extension View {
    func previewOuterEdgePadding(_ amount: CGFloat, onLeadingEdge: Bool, enabled: Bool = true) -> some View {
        padding(.leading, enabled && onLeadingEdge ? amount : 0)
            .padding(.trailing, enabled && !onLeadingEdge ? amount : 0)
    }
}

struct WindowTitlePresentation: Equatable {
    let isVisible: Bool
    let reservesSpace: Bool

    static func resolve(
        title: String?,
        showWindowTitle: Bool,
        visibility: WindowTitleVisibility,
        isHighlighted: Bool
    ) -> Self {
        let hasTitle = showWindowTitle && title != nil
        let isVisible = hasTitle && (visibility == .alwaysVisible || isHighlighted)
        let reservesSpace = hasTitle
        return Self(isVisible: isVisible, reservesSpace: reservesSpace)
    }
}

struct WindowPreview: View, Equatable {
    let windowInfo: WindowInfo
    let onTap: (() -> Void)?
    let index: Int
    let dockPosition: DockPosition
    let bestGuessMonitor: NSScreen
    let uniformCardRadius: Bool
    let handleWindowAction: (WindowAction) -> Void
    var isSelected: Bool
    var windowSwitcherActive: Bool
    let dimensions: WindowPreviewHoverContainer.WindowDimensions
    let showAppIconOnly: Bool
    let mockPreviewActive: Bool
    let onHoverIndexChange: ((Int?, CGPoint?) -> Bool)?
    let onDragHoverIndexChange: ((Int?) -> Void)?
    let useLivePreview: Bool
    var skeletonMode: Bool = false
    var appearance: PreviewAppearanceSettings
    let backgroundAppearance: BackgroundAppearance
    let focusedWindowID: CGWindowID?
    let currentSpaceNumbers: Set<Int>
    var spaceNumber: Int? = nil
    var isChecked = false
    var dragSelection: SwitcherSelectionState? = nil
    var previewBodyDrag: AnyGesture<DragGesture.Value>? = nil
    var selectionInteraction: PreviewSelectionInteraction? = nil

    @State private var isHoveringOverDockPeekPreview = false
    @State private var isHoveringOverWindowSwitcherPreview = false
    @State private var isHoveringTitle = false

    private var hasSelectionControl: Bool {
        appearance.enableMultiWindowSelection && !mockPreviewActive && (!windowInfo.isWindowlessApp || appearance.enableWindowlessAppSelection) &&
            (appearance.showUncheckedSelectionCheckboxes || isChecked || selectionInteraction?.isDragOrigin == true)
    }

    private func selectionCheckboxIsVisible(titleAvailable: Bool) -> Bool {
        if selectionInteraction?.isDragOrigin == true { return true }
        let pointerHovered = isHoveringOverDockPeekPreview || isHoveringOverWindowSwitcherPreview
        let previewHovered = isSelected || pointerHovered
        return appearance.selectionCheckboxVisibility.showsCheckbox(
            checked: isChecked,
            previewHovered: previewHovered,
            titleHovered: isHoveringTitle && pointerHovered,
            titleAvailable: titleAvailable,
            compact: false
        )
    }

    private var showsSelectionControl: Bool {
        guard hasSelectionControl else { return false }
        let titleAvailable = windowSwitcherActive ? appearance.showAppHeader : WindowTitlePresentation.resolve(
            title: previewTitle,
            showWindowTitle: appearance.showWindowTitle,
            visibility: appearance.windowTitleVisibility,
            isHighlighted: isSelected
        ).isVisible
        return selectionCheckboxIsVisible(titleAvailable: titleAvailable)
    }

    private func selectionCheckbox(titleAvailable: Bool, iconSize: CGFloat? = nil) -> some View {
        PreviewSelectionCheckbox(
            isChecked: isChecked,
            isVisible: selectionCheckboxIsVisible(titleAvailable: titleAvailable),
            color: appearance.activeAppIndicatorColor,
            diameter: iconSize.map(PreviewSelectionCheckbox.iconDiameter) ?? appearance.windowTitleFontSize.measuredLineHeight,
            drawingScale: iconSize == nil ? 1.2 : 1,
            backgroundAppearance: iconSize == nil ? nil : backgroundAppearance,
            animationsEnabled: appearance.showAnimations,
            interaction: selectionInteraction,
            toggle: { handleWindowAction(.toggleWindowSelection) }
        )
        .transition(.opacity)
    }

    @ViewBuilder
    private func dockTitleContent(title: String?, visible: Bool, reservesSpace: Bool, stage: PreviewToolbarStage,
                                  combinesControls: Bool, isMeasuring: Bool) -> some View
    {
        let titleAvailable = visible && title != nil && stage.showsTitles
        let showsCheckbox = hasSelectionControl && selectionCheckboxIsVisible(titleAvailable: titleAvailable)
        let showsTitle = reservesSpace && stage.showsTitles
        Group {
            if showsTitle || showsCheckbox || combinesControls {
                HStack(spacing: 4) {
                    if combinesControls {
                        overflowButton(stage: stage, includesSelection: true,
                                       circularDiameter: appearance.windowTitleFontSize.measuredLineHeight * 1.2,
                                       usesCircularMaterial: false)
                    } else if showsCheckbox, !appearance.controlPosition.titleIsTrailing {
                        selectionCheckbox(titleAvailable: titleAvailable)
                    }
                    if showsTitle, let title {
                        PreviewToolbarTitle(font: appearance.windowTitleFontSize.font) {
                            titleLabel(title, adaptsToAvailableWidth: true, scrolls: visible, isMeasuring: isMeasuring)
                                .if(windowInfo.isWindowlessApp) { $0.italic() }
                                .opacity(visible ? 1 : 0)
                        }
                    }
                    if !combinesControls, showsCheckbox, appearance.controlPosition.titleIsTrailing {
                        selectionCheckbox(titleAvailable: titleAvailable)
                    }
                }
                .font(appearance.windowTitleFontSize.font)
                .multilineTextAlignment(appearance.controlPosition.titleIsTrailing ? .trailing : .leading)
                .padding(4)
                .if(!appearance.disableDockStyleTitles) { $0.materialPill(backgroundAppearance: backgroundAppearance) }
                .frame(minWidth: 0)
                .clipped()
                .embeddedPreviewContrastShadow(appearance.usesEmbeddedTitleContrastShadow)
                .opacity(combinesControls || visible || showsCheckbox ? 1 : 0)
                .if(hasSelectionControl) { $0.onHover { isHoveringTitle = $0 } }
            }
        }
        .previewControlVisibilityAnimation(isVisible: showsCheckbox, duration: appearance.trafficLightTransitionDuration, animationsEnabled: appearance.showAnimations)
    }

    private func overflowButton(stage: PreviewToolbarStage, includesSelection: Bool = false,
                                circularDiameter: CGFloat? = nil, usesCircularMaterial: Bool = true) -> some View
    {
        let hovered = isSelected || isHoveringOverDockPeekPreview || isHoveringOverWindowSwitcherPreview
        return PreviewOverflowButton(window: windowInfo, appearance: appearance, backgroundAppearance: backgroundAppearance,
                                     overflow: PreviewControlOverflow(
                                         actions: canRenderTrafficLightButtons && shouldShowTrafficLightButtons(parentHovered: hovered) ? stage.overflowActions(in: effectiveTrafficLightButtons) : [],
                                         includesIndicator: stage.overflowsIndicators && (hasWindowStateIndicator || visibleWindowStateLabel != nil),
                                         includesSelection: includesSelection && appearance.enableMultiWindowSelection,
                                         spaceNumber: appearance.showSpaceNumberIndicator ? windowInfo.spaceNumber : nil,
                                         allowsSpaceMoving: appearance.enableSpaceIndicatorWindowMoving && appearance.showSpaceNumberIndicator
                                     ),
                                     circularDiameter: circularDiameter, usesCircularMaterial: usesCircularMaterial, isChecked: isChecked,
                                     mockPreviewActive: mockPreviewActive, handleWindowAction: handleWindowAction,
                                     dismissPreviews: onTap)
    }

    private var effectiveTrafficLightButtons: Set<WindowAction> {
        resolvedTrafficLightButtons(
            for: windowInfo,
            configuredButtons: appearance.enabledTrafficLightButtons,
            showWindowlessQuitButton: appearance.showWindowlessAppQuitButton
        )
    }

    private var previewTitle: String? {
        if windowInfo.isWindowlessApp {
            return String(localized: "No Open Windows", comment: "Label for running apps without any open windows in the window switcher")
        }
        if let title = windowInfo.windowName, !title.isEmpty {
            return title
        }
        return windowInfo.app.localizedName
    }

    private var isEffectivelyHidden: Bool {
        !windowInfo.isWindowlessApp && windowInfo.isEffectivelyHiddenForUI
    }

    private var windowStateLabel: String? {
        guard !windowInfo.isWindowlessApp, appearance.windowStateIndicatorPlacement == .onWindowPreviews else { return nil }
        if windowInfo.isMinimized {
            return String(localized: "Minimized", comment: "Window state label")
        } else if isEffectivelyHidden {
            return String(localized: "Hidden", comment: "Window state label")
        } else if windowInfo.isFullscreen == true {
            return String(localized: "Full Screen", comment: "Window state label")
        }
        return nil
    }

    private var hasWindowStateIndicator: Bool {
        let hasSpaceNumber = appearance.showSpaceNumberIndicator && windowInfo.spaceNumber != nil
        let hasState = appearance.windowStateIndicatorPlacement == .nextToTrafficLightButtons &&
            !windowStateSymbols.isEmpty
        return hasSpaceNumber || hasState
    }

    private var windowStateSymbols: [String] {
        guard !windowInfo.isWindowlessApp else { return [] }
        return WindowStateSymbolResolver.symbols(
            for: windowInfo,
            isEffectivelyHidden: isEffectivelyHidden
        )
    }

    private var movesWindowStateToIndicator: Bool {
        appearance.windowStateIndicatorPlacement == .nextToTrafficLightButtons &&
            !windowStateSymbols.isEmpty
    }

    private var visibleWindowStateLabel: String? {
        windowStateLabel
    }

    private var windowStateSymbol: String? {
        guard !windowInfo.isWindowlessApp, appearance.windowStateIndicatorPlacement == .onWindowPreviews else { return nil }
        if windowInfo.isMinimized {
            return "minus.circle"
        } else if isEffectivelyHidden {
            return "eye.slash"
        } else if windowInfo.isFullscreen == true {
            return "arrow.up.left.and.arrow.down.right"
        }
        return nil
    }

    @ViewBuilder
    private var windowStateIndicator: some View {
        let stateSymbols = movesWindowStateToIndicator ? windowStateSymbols : []
        let spaceNumber = appearance.showSpaceNumberIndicator ? windowInfo.spaceNumber : nil
        if spaceNumber != nil || !stateSymbols.isEmpty {
            SpaceMoveIndicatorControl(
                window: windowInfo,
                spaceNumber: spaceNumber,
                isEnabled: appearance.enableSpaceIndicatorWindowMoving && !mockPreviewActive,
                dismissPreviews: onTap
            ) {
                WindowStateIndicator(
                    number: spaceNumber,
                    stateSymbols: stateSymbols,
                    disableDockStyling: appearance.disableDockStyleWindowStateIndicator,
                    fontSize: appearance.windowStateIndicatorFontSize,
                    backgroundAppearance: backgroundAppearance,
                    highlightsCurrentSpace: appearance.highlightCurrentSpaceNumberIndicator &&
                        spaceNumber.map(currentSpaceNumbers.contains) == true,
                    highlightColor: appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor),
                    highlightOpacity: appearance.selectionOpacity,
                    activeBorderColor: appearance.activeAppIndicatorColor
                )
                .embeddedPreviewContrastShadow(appearance.usesEmbeddedWindowStateContrastShadow)
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
        }
    }

    @ViewBuilder
    private func controlsWithWindowStateIndicator(
        controlsAreLeading: Bool,
        hasAdjacentControl: Bool,
        adjacentControlHeight: CGFloat?,
        spacing: CGFloat = 8,
        includesIndicator: Bool = true,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let hasWindowStateIndicator = includesIndicator && hasWindowStateIndicator
        let swapsIndicators = appearance.swapTrafficLightsAndWindowStateIndicator && !appearance.limitIndicatorSwapToCompactMode
        let controlsComeFirst = controlsAreLeading != swapsIndicators
        let stateIndicatorIsOutermost = hasWindowStateIndicator &&
            (!hasAdjacentControl || controlsAreLeading != controlsComeFirst)
        let opticalEdgeInset: CGFloat = stateIndicatorIsOutermost && appearance.disableDockStyleWindowStateIndicator ? 2 : 0
        let stateIndicatorHeight = hasWindowStateIndicator
            ? appearance.windowStateIndicatorControlHeight
            : nil
        let clusterHeight = max(stateIndicatorHeight ?? 0, adjacentControlHeight ?? 0)
        let outerControlHeight = stateIndicatorIsOutermost ? stateIndicatorHeight : adjacentControlHeight
        let heightAlignmentInset = max(
            0,
            (clusterHeight - (outerControlHeight ?? clusterHeight)) / 2
        )
        let edgeInset = heightAlignmentInset + opticalEdgeInset
        HStack(spacing: spacing) {
            if controlsComeFirst {
                content()
                if includesIndicator { windowStateIndicator }
            } else {
                if includesIndicator { windowStateIndicator }
                content()
            }
        }
        .padding(.leading, controlsAreLeading ? edgeInset : 0)
        .padding(.trailing, controlsAreLeading ? 0 : edgeInset)
    }

    private func dockTitleControlHeight() -> CGFloat {
        let contentHeight = appearance.windowTitleFontSize.measuredLineHeight + 8
        return contentHeight + (appearance.disableDockStyleTitles ? 0 : 2 * MaterialPillStyle.verticalPadding)
    }

    private func controlClusterHeight(adjacentControlHeight: CGFloat?) -> CGFloat? {
        let stateIndicatorHeight = hasWindowStateIndicator
            ? appearance.windowStateIndicatorControlHeight
            : nil
        guard stateIndicatorHeight != nil || adjacentControlHeight != nil else { return nil }
        return max(stateIndicatorHeight ?? 0, adjacentControlHeight ?? 0)
    }

    private func rowEdgeInsets(
        titleHeight: CGFloat?,
        controlsHeight: CGFloat?
    ) -> (title: CGFloat, controls: CGFloat) {
        let rowHeight = max(titleHeight ?? 0, controlsHeight ?? 0)
        return (
            titleHeight.map { max(0, (rowHeight - $0) / 2) } ?? 0,
            controlsHeight.map { max(0, (rowHeight - $0) / 2) } ?? 0
        )
    }

    private func controlsSpacing(hasAdjacentControl: Bool, hasVisibleTrafficLights: Bool) -> CGFloat {
        // Hover-hidden buttons retain a zero-width view, but must not leave a gap.
        guard hasAdjacentControl else { return 0 }
        return hasVisibleTrafficLights ? appearance.controlElementSpacing : 8
    }

    private func configuredAdjacentControlHeight(
        hasTrafficLights: Bool,
        stateLabelHeight: CGFloat
    ) -> CGFloat? {
        if hasTrafficLights {
            return TrafficLightButtons.controlHeight(
                buttonScale: appearance.trafficLightButtonScale,
                pillStyling: !appearance.disableDockStyleTrafficLights
            )
        }
        guard !hasTrafficLights, visibleWindowStateLabel != nil,
              appearance.trafficLightVisibility != .never
        else { return nil }
        return appearance.disableDockStyleTitles ? stateLabelHeight + 8 : 34
    }

    private var canRenderTrafficLightButtons: Bool {
        appearance.trafficLightVisibility != .never &&
            !effectiveTrafficLightButtons.isEmpty
    }

    private func shouldShowTrafficLightButtons(parentHovered: Bool) -> Bool {
        appearance.trafficLightVisibility.isVisible(
            hoveringOverParentWindow: parentHovered
        )
    }

    static func == (l: Self, r: Self) -> Bool {
        l.index == r.index && l.isSelected == r.isSelected && l.isChecked == r.isChecked && l.useLivePreview == r.useLivePreview
            && l.dragSelection === r.dragSelection
            && l.selectionInteraction?.isDragOrigin == r.selectionInteraction?.isDragOrigin
            && l.skeletonMode == r.skeletonMode && l.dimensions == r.dimensions
            && l.uniformCardRadius == r.uniformCardRadius && l.showAppIconOnly == r.showAppIconOnly
            && l.windowSwitcherActive == r.windowSwitcherActive
            && l.appearance == r.appearance && l.windowInfo.viewSnapshot == r.windowInfo.viewSnapshot
            && l.backgroundAppearance == r.backgroundAppearance
            && l.focusedWindowID == r.focusedWindowID
            && l.currentSpaceNumbers == r.currentSpaceNumbers
            && l.spaceNumber == r.spaceNumber
    }

    private var isActiveWindow: Bool {
        guard !windowInfo.isWindowlessApp, appearance.showActiveWindowBorder else { return false }
        guard windowInfo.app.isActive else { return false }
        return windowInfo.id == focusedWindowID
    }

    private var dynamicSwitcherCardWidth: CGFloat? {
        guard windowSwitcherActive, appearance.allowDynamicImageSizing, dimensions.size.width > 0 else {
            return nil
        }
        let chromeWidth = min(
            dimensions.maxDimensions.width,
            WindowPreviewHoverContainer.dynamicSwitcherMinimumCardWidth
        )
        return max(dimensions.size.width, chromeWidth)
    }

    private var switcherToolbarHorizontalPadding: CGFloat {
        CardRadius.switcherToolbarHorizontalPadding(
            uniformCardRadius: windowSwitcherActive && uniformCardRadius
        )
    }

    private var hasWindowSwitcherControlContent: Bool {
        canRenderTrafficLightButtons ||
            (visibleWindowStateLabel != nil && appearance.trafficLightVisibility != .never) ||
            hasWindowStateIndicator
    }

    @ViewBuilder
    private func titleLabel(_ text: String, adaptsToAvailableWidth: Bool = false, scrolls: Bool = true, isMeasuring: Bool = false) -> some View {
        if isMeasuring {
            Text(verbatim: "\u{2026}").fixedSize()
        } else {
            switch appearance.titleOverflowStyle {
            case .marquee:
                MarqueeText(text: text, startDelay: 1, enableScrolling: scrolls, adaptsToAvailableWidth: adaptsToAvailableWidth)
            case .truncateTail:
                MarqueeText(
                    text: text,
                    truncationMode: .tail,
                    enableScrolling: false,
                    adaptsToAvailableWidth: adaptsToAvailableWidth
                )
            case .truncateMiddle:
                MarqueeText(
                    text: text,
                    truncationMode: .middle,
                    enableScrolling: false,
                    adaptsToAvailableWidth: adaptsToAvailableWidth
                )
            case .truncateHead:
                MarqueeText(
                    text: text,
                    truncationMode: .head,
                    enableScrolling: false,
                    adaptsToAvailableWidth: adaptsToAvailableWidth
                )
            }
        }
    }

    @ViewBuilder
    private func windowContent(isMinimized: Bool, isHidden: Bool, isSelected: Bool) -> some View {
        let inactive = (isMinimized || isHidden) && appearance.dimMinimizedHiddenPreviews
        let stateSymbol = windowStateSymbol
        let quality = appearance.livePreviewQuality
        let frameRate = appearance.livePreviewFrameRate

        Group {
            if skeletonMode {
                Color.clear
            } else if useLivePreview, !windowInfo.isWindowlessApp {
                LivePreviewImage(windowID: windowInfo.id, fallbackImage: windowInfo.image, quality: quality, frameRate: frameRate, context: windowSwitcherActive ? .windowSwitcher : .dock, placeholderIcon: windowInfo.image == nil ? windowInfo.app.icon : nil)
            } else if let cgImage = windowInfo.image {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .scaledToFit()
            } else {
                PreviewPlaceholderImage(appIcon: windowInfo.app.icon)
            }
        }
        .markHidden(isHidden: inactive || (windowSwitcherActive && !isSelected))
        .overlay {
            if let stateSymbol {
                Image(systemName: stateSymbol)
                    .font(.largeTitle)
                    .foregroundColor(.primary)
                    .shadow(radius: 2)
                    .transition(.opacity)
            }
        }
        .animation(appearance.showAnimations ? .easeInOut(duration: 0.15) : nil, value: stateSymbol)
        .clipShape(RoundedRectangle(cornerRadius: appearance.radii.image, style: .continuous))
        .overlay(alignment: spaceBadgeAlignment) {
            if let spaceNumber, !skeletonMode {
                SpaceNumberBadge(
                    number: spaceNumber,
                    font: appearance.windowTitleFontSize.font,
                    backgroundAppearance: backgroundAppearance
                )
                .padding(8)
            }
        }
        .dynamicWindowFrame(
            allowDynamicSizing: appearance.allowDynamicImageSizing && windowInfo.image != nil,
            dimensions: dimensions,
            dockPosition: dockPosition,
            windowSwitcherActive: windowSwitcherActive
        )
        .opacity(isSelected || isChecked ? 1.0 : appearance.unselectedContentOpacity)
        .contentShape(Rectangle())
        .gesture(skeletonMode ? nil : previewBodyDrag)
    }

    private var spaceBadgeAlignment: Alignment {
        switch appearance.controlPosition {
        case .topLeading, .topTrailing:
            .bottomTrailing
        case .diagonalTopRightBottomLeft, .diagonalBottomLeftTopRight,
             .parallelTopRightBottomRight, .parallelBottomRightTopRight:
            .topLeading
        default:
            .topTrailing
        }
    }

    @ViewBuilder
    private func embeddedControlsOverlay(_ selected: Bool) -> some View {
        if windowSwitcherActive {
            embeddedWindowSwitcherControls(selected)
        } else {
            embeddedDockPreviewControls(selected)
        }
    }

    @ViewBuilder
    private func embeddedWindowSwitcherControls(_ selected: Bool) -> some View {
        EmbeddedSwitcherControlsLayout(
            controlPosition: appearance.controlPosition,
            hasTitleContent: appearance.showAppHeader || showsSelectionControl,
            hasControlsContent: hasWindowSwitcherControlContent
        ) { isLeadingControls, showTitle, showControls in
            windowSwitcherContent(
                selected,
                isLeadingControls: isLeadingControls,
                showTitleContent: showTitle,
                showControlsContent: showControls
            )
        }
    }

    @ViewBuilder
    private func embeddedDockPreviewControls(_ selected: Bool) -> some View {
        EmbeddedSwitcherControlsLayout(
            controlPosition: appearance.controlPosition,
            hasTitleContent: appearance.showWindowTitle || showsSelectionControl,
            hasControlsContent: canRenderTrafficLightButtons || hasWindowStateIndicator || visibleWindowStateLabel != nil
        ) { leading, title, controls in
            dockPreviewContent(selected, isLeadingControls: leading, showTitleContent: title, showControlsContent: controls)
        }
    }

    private func windowSwitcherContent(_ selected: Bool, isLeadingControls: Bool,
                                       showTitleContent: Bool = true, showControlsContent: Bool = true) -> some View
    {
        let appIcon = windowInfo.app.icon
        let controlsVisible = canRenderTrafficLightButtons && shouldShowTrafficLightButtons(parentHovered: selected || isHoveringOverWindowSwitcherPreview)
        return PreviewAdaptiveToolbar(
            allowsTitleOmission: showTitleContent && appearance.showAppHeader && (!showAppIconOnly || appearance.showWindowTitle),
            partialActionCounts: appearance.partialTrafficLightCounts(for: effectiveTrafficLightButtons, isVisible: showControlsContent && controlsVisible),
            controlsVisible: controlsVisible,
            animationDuration: appearance.trafficLightTransitionDuration, animationsEnabled: appearance.showAnimations
        ) { stage, isMeasuring in
            windowSwitcherRow(selected, isLeadingControls: isLeadingControls,
                              showTitleContent: showTitleContent, showControlsContent: showControlsContent, stage: stage, appIcon: appIcon, isMeasuring: isMeasuring)
        }
        .frame(width: appearance.useEmbeddedElements ? nil : dimensions.size.width)
    }

    private func windowSwitcherRow(
        _ selected: Bool,
        isLeadingControls: Bool,
        showTitleContent: Bool = true,
        showControlsContent: Bool = true,
        stage: PreviewToolbarStage,
        appIcon: NSImage?,
        isMeasuring: Bool
    ) -> some View {
        let combinesControls = stage == .combined && showTitleContent && showControlsContent && hasWindowSwitcherControlContent
        let shouldShowAppHeader = (appearance.showAppHeader || showsSelectionControl || combinesControls) && showTitleContent
        let shouldShowControls = showControlsContent && hasWindowSwitcherControlContent && !combinesControls
        let shouldShowWindowTitle = appearance.showWindowTitle &&
            (appearance.windowTitleVisibility == .alwaysVisible || selected || isHoveringOverWindowSwitcherPreview)
        let showTrafficLights = shouldShowTrafficLightButtons(
            parentHovered: selected || isHoveringOverWindowSwitcherPreview
        )
        let hasVisibleAdjacentControl = (canRenderTrafficLightButtons && showTrafficLights) ||
            (!canRenderTrafficLightButtons && visibleWindowStateLabel != nil && appearance.trafficLightVisibility != .never)
        let configuredAdjacentHeight = configuredAdjacentControlHeight(
            hasTrafficLights: canRenderTrafficLightButtons,
            stateLabelHeight: 17
        )
        let windowTitle = windowInfo.isWindowlessApp ? previewTitle : windowInfo.windowName
        let hasWindowTitleLabel = shouldShowWindowTitle &&
            windowTitle?.isEmpty == false &&
            windowTitle != windowInfo.app.localizedName
        let appIconSize = appearance.resolvedSwitcherAppIconSize(windowTitleIsVisible: shouldShowWindowTitle)
        let configuredWindowTitle = appearance.showWindowTitle &&
            windowTitle?.isEmpty == false &&
            windowTitle != windowInfo.app.localizedName
        let labelsHeight = showAppIconOnly
            ? 0
            : WindowTitleFontSize.bodyLineHeight +
            (configuredWindowTitle ? appearance.windowTitleFontSize.measuredLineHeight : 0)
        let titleHeight = shouldShowAppHeader ? (appearance.showAppHeader ? max(appIconSize, labelsHeight) : appearance.windowTitleFontSize.measuredLineHeight) : nil
        let controlsHeight = shouldShowControls
            ? controlClusterHeight(adjacentControlHeight: configuredAdjacentHeight)
            : nil
        let edgeInsets = rowEdgeInsets(titleHeight: titleHeight, controlsHeight: controlsHeight)

        let titleOnRight = appearance.controlPosition.titleIsTrailing
        let titleAlignment: HorizontalAlignment = titleOnRight ? .trailing : .leading
        let textAlignment: TextAlignment = titleOnRight ? .trailing : .leading
        let titleAndSubtitleContent = PreviewToolbarTitle {
            VStack(alignment: titleAlignment, spacing: 0) {
                if !showAppIconOnly, appearance.showAppHeader, stage.showsTitles {
                    titleLabel(windowInfo.app.localizedName ?? "Unknown", adaptsToAvailableWidth: true, isMeasuring: isMeasuring)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(textAlignment)
                        .lineLimit(1)
                }

                if let windowTitle, hasWindowTitleLabel, appearance.showAppHeader, stage.showsTitles {
                    titleLabel(windowTitle, adaptsToAvailableWidth: true, isMeasuring: isMeasuring)
                        .if(windowInfo.isWindowlessApp) { $0.italic() }
                        .font(appearance.windowTitleFontSize.font)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(textAlignment)
                }
            }
        }
        .modifier(EmbeddedSwitcherTitleShadow(isEnabled: appearance.usesEmbeddedTitleContrastShadow))

        let appIconContent = Group {
            if appearance.showAppHeader {
                PreviewAppIcon(
                    icon: appIcon,
                    bundleURL: windowInfo.app.bundleURL,
                    size: appIconSize,
                    showBadge: !isMeasuring && windowSwitcherActive && appearance.showAppIconBadges,
                    badgeScale: appearance.appIconBadgeScale,
                    mockPreviewActive: mockPreviewActive
                )
                .overlay {
                    if combinesControls {
                        overflowButton(stage: stage, includesSelection: true,
                                       circularDiameter: PreviewSelectionCheckbox.iconDiameter(for: appIconSize))
                    } else if hasSelectionControl { selectionCheckbox(titleAvailable: true, iconSize: appIconSize) }
                }
            } else if combinesControls {
                overflowButton(stage: stage, includesSelection: true,
                               circularDiameter: appearance.windowTitleFontSize.measuredLineHeight * 1.2)
            } else if hasSelectionControl {
                selectionCheckbox(titleAvailable: false)
            }
        }

        let controlsContent = controlsWithWindowStateIndicator(
            controlsAreLeading: isLeadingControls,
            hasAdjacentControl: hasVisibleAdjacentControl,
            adjacentControlHeight: configuredAdjacentHeight,
            spacing: controlsSpacing(
                hasAdjacentControl: hasVisibleAdjacentControl,
                hasVisibleTrafficLights: canRenderTrafficLightButtons && showTrafficLights
            ),
            includesIndicator: !stage.overflowsIndicators
        ) {
            if canRenderTrafficLightButtons {
                PreviewControlReplacement(
                    controlsVisible: stage.showsTrafficLights && showTrafficLights,
                    replacementVisible: stage.overflowsActions && (showTrafficLights || (stage.overflowsIndicators && (hasWindowStateIndicator || visibleWindowStateLabel != nil))),
                    spacing: appearance.controlElementSpacing,
                    usesControlsContrastShadow: appearance.usesEmbeddedTrafficLightContrastShadow
                ) {
                    TrafficLightButtons(
                        previewAppearance: appearance,
                        hoveringOverParentWindow: selected || isHoveringOverWindowSwitcherPreview,
                        onWindowAction: handleWindowAction,
                        mockPreviewActive: mockPreviewActive,
                        enabledButtons: stage.visibleActions(in: effectiveTrafficLightButtons),
                        backgroundAppearance: backgroundAppearance
                    )
                } replacement: {
                    overflowButton(stage: stage)
                }
            } else if stage.overflowsIndicators, hasWindowStateIndicator || visibleWindowStateLabel != nil {
                overflowButton(stage: stage)
            } else if !stage.overflowsIndicators, let stateLabel = visibleWindowStateLabel,
                      appearance.trafficLightVisibility != .never
            {
                Text(stateLabel)
                    .font(appearance.windowTitleFontSize.font)
                    .italic()
                    .foregroundStyle(.secondary)
                    .frame(height: 17)
                    .padding(4)
                    .if(!appearance.disableDockStyleTitles) { view in
                        view.materialPill(backgroundAppearance: backgroundAppearance)
                            .frame(height: 34)
                    }
                    .embeddedPreviewContrastShadow(appearance.usesEmbeddedTitleContrastShadow)
            }
        }
        .fixedSize()
        .previewOuterEdgePadding(
            edgeInsets.controls,
            onLeadingEdge: isLeadingControls,
            enabled: shouldShowControls && (hasWindowStateIndicator || hasVisibleAdjacentControl)
        )

        let hasVisibleControls = hasWindowStateIndicator || hasVisibleAdjacentControl ||
            (stage.overflowsIndicators && visibleWindowStateLabel != nil)
        let controlsGap: CGFloat = shouldShowControls && shouldShowAppHeader && hasVisibleControls ? appearance.controlElementSpacing : 0

        let titleContent = PreviewTitleCluster(iconOnRight: titleOnRight) {
            appIconContent
        } labels: {
            if stage.showsTitles, appearance.showAppHeader, !showAppIconOnly || hasWindowTitleLabel {
                titleAndSubtitleContent
            }
        }
        .if(hasSelectionControl) { $0.onHover { isHoveringTitle = $0 } }
        .layoutPriority(1)
        .previewOuterEdgePadding(edgeInsets.title, onLeadingEdge: !isLeadingControls, enabled: shouldShowAppHeader)

        if !shouldShowAppHeader, !shouldShowControls {
            return AnyView(EmptyView())
        } else if appearance.controlPosition.isCentered {
            return AnyView(
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    HStack(spacing: controlsGap) {
                        if shouldShowAppHeader { titleContent }
                        if shouldShowControls { controlsContent }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            )
        } else {
            return AnyView(
                HStack(spacing: 0) {
                    if isLeadingControls {
                        if shouldShowControls { controlsContent }
                        Spacer(minLength: controlsGap)
                        if shouldShowAppHeader { titleContent }
                    } else {
                        if shouldShowAppHeader { titleContent }
                        Spacer(minLength: controlsGap)
                        if shouldShowControls { controlsContent }
                    }
                }
                .frame(maxWidth: .infinity)
            )
        }
    }

    private func dockPreviewContent(_ selected: Bool, isLeadingControls: Bool,
                                    showTitleContent: Bool = true, showControlsContent: Bool = true) -> some View
    {
        let controlsVisible = canRenderTrafficLightButtons && shouldShowTrafficLightButtons(parentHovered: selected || isHoveringOverDockPeekPreview)
        return PreviewAdaptiveToolbar(
            allowsTitleOmission: showTitleContent && appearance.showWindowTitle && previewTitle != nil,
            partialActionCounts: appearance.partialTrafficLightCounts(for: effectiveTrafficLightButtons, isVisible: showControlsContent && controlsVisible),
            controlsVisible: controlsVisible,
            animationDuration: appearance.trafficLightTransitionDuration, animationsEnabled: appearance.showAnimations
        ) { stage, isMeasuring in
            dockPreviewRow(selected, isLeadingControls: isLeadingControls,
                           showTitleContent: showTitleContent, showControlsContent: showControlsContent, stage: stage, isMeasuring: isMeasuring)
        }
        .frame(width: appearance.useEmbeddedElements ? nil : dimensions.size.width)
    }

    private func dockPreviewRow(
        _ selected: Bool,
        isLeadingControls: Bool,
        showTitleContent: Bool = true,
        showControlsContent: Bool = true,
        stage: PreviewToolbarStage,
        isMeasuring: Bool
    ) -> some View {
        let combinesControls = stage == .combined && showTitleContent && showControlsContent && (canRenderTrafficLightButtons || hasWindowStateIndicator)
        let displaysControls = showControlsContent && !combinesControls
        let titleToShow = previewTitle

        let titlePresentation = WindowTitlePresentation.resolve(
            title: titleToShow,
            showWindowTitle: appearance.showWindowTitle && showTitleContent,
            visibility: appearance.windowTitleVisibility,
            isHighlighted: selected
        )
        let showsTitleSelectionControl = hasSelectionControl && selectionCheckboxIsVisible(
            titleAvailable: titlePresentation.isVisible && stage.showsTitles
        )

        let hasTrafficLights = canRenderTrafficLightButtons
        let showTrafficLights = shouldShowTrafficLightButtons(
            parentHovered: selected || isHoveringOverDockPeekPreview
        )
        let hasVisibleAdjacentControl = (hasTrafficLights && showTrafficLights) ||
            (!hasTrafficLights && visibleWindowStateLabel != nil && appearance.trafficLightVisibility != .never)
        let configuredAdjacentHeight = configuredAdjacentControlHeight(
            hasTrafficLights: hasTrafficLights,
            stateLabelHeight: 17 * appearance.trafficLightButtonScale
        )
        let titleIsConfigured = ((stage.showsTitles && appearance.showWindowTitle && titleToShow != nil) || showsTitleSelectionControl || combinesControls) && showTitleContent
        let controlsHeight = displaysControls
            ? controlClusterHeight(adjacentControlHeight: configuredAdjacentHeight)
            : nil
        let edgeInsets = rowEdgeInsets(
            titleHeight: titleIsConfigured ? dockTitleControlHeight() : nil,
            controlsHeight: controlsHeight
        )
        let titleContent = dockTitleContent(
            title: titleToShow,
            visible: titlePresentation.isVisible,
            reservesSpace: titlePresentation.reservesSpace,
            stage: stage, combinesControls: combinesControls, isMeasuring: isMeasuring
        )
        .previewOuterEdgePadding(edgeInsets.title, onLeadingEdge: !isLeadingControls, enabled: (stage.showsTitles && titlePresentation.reservesSpace) || showsTitleSelectionControl || combinesControls)

        let controlsContent = controlsWithWindowStateIndicator(
            controlsAreLeading: isLeadingControls,
            hasAdjacentControl: hasVisibleAdjacentControl,
            adjacentControlHeight: configuredAdjacentHeight,
            spacing: controlsSpacing(
                hasAdjacentControl: hasVisibleAdjacentControl,
                hasVisibleTrafficLights: hasTrafficLights && showTrafficLights
            ),
            includesIndicator: !stage.overflowsIndicators
        ) {
            if hasTrafficLights {
                PreviewControlReplacement(
                    controlsVisible: stage.showsTrafficLights && showTrafficLights,
                    replacementVisible: stage.overflowsActions && (showTrafficLights || (stage.overflowsIndicators && (hasWindowStateIndicator || visibleWindowStateLabel != nil))),
                    spacing: appearance.controlElementSpacing,
                    usesControlsContrastShadow: appearance.usesEmbeddedTrafficLightContrastShadow
                ) {
                    TrafficLightButtons(
                        previewAppearance: appearance,
                        hoveringOverParentWindow: selected || isHoveringOverDockPeekPreview,
                        onWindowAction: handleWindowAction,
                        mockPreviewActive: mockPreviewActive,
                        enabledButtons: stage.visibleActions(in: effectiveTrafficLightButtons),
                        backgroundAppearance: backgroundAppearance
                    )
                } replacement: {
                    overflowButton(stage: stage)
                }
            } else if stage.overflowsIndicators, hasWindowStateIndicator || visibleWindowStateLabel != nil {
                overflowButton(stage: stage)
            } else if !stage.overflowsIndicators, let stateLabel = visibleWindowStateLabel,
                      appearance.trafficLightVisibility != .never
            {
                Text(stateLabel)
                    .font(appearance.windowTitleFontSize.font)
                    .italic()
                    .foregroundStyle(.secondary)
                    .frame(height: 17 * appearance.trafficLightButtonScale)
                    .padding(4)
                    .if(!appearance.disableDockStyleTitles) { view in
                        view.materialPill(backgroundAppearance: backgroundAppearance)
                            .frame(height: 34)
                    }
                    .embeddedPreviewContrastShadow(appearance.usesEmbeddedTitleContrastShadow)
            }
        }
        .fixedSize()
        .previewOuterEdgePadding(
            edgeInsets.controls,
            onLeadingEdge: isLeadingControls,
            enabled: showControlsContent && (hasWindowStateIndicator || hasVisibleAdjacentControl)
        )

        if titlePresentation.reservesSpace || (showTitleContent && showsTitleSelectionControl) || (showControlsContent && (hasTrafficLights || hasWindowStateIndicator)) {
            if appearance.controlPosition.isCentered {
                return AnyView(
                    HStack(spacing: 4) {
                        Spacer(minLength: 0)
                        if showTitleContent { titleContent }
                        if displaysControls { controlsContent }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                )
            } else {
                return AnyView(
                    HStack(spacing: 0) {
                        if isLeadingControls {
                            if displaysControls { controlsContent }
                            Spacer(minLength: displaysControls && (stage.showsTitles || showsTitleSelectionControl) ? 8 : 0)
                            if showTitleContent { titleContent }
                        } else {
                            if showTitleContent { titleContent }
                            Spacer(minLength: displaysControls && (stage.showsTitles || showsTitleSelectionControl) ? 8 : 0)
                            if displaysControls { controlsContent }
                        }
                    }
                    .frame(maxWidth: .infinity)
                )
            }
        } else {
            return AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private var previewCoreContent: some View {
        let finalIsSelected = isSelected
        let switcherCardWidth = dynamicSwitcherCardWidth

        ZStack(alignment: .topLeading) {
            // Padded toolbars must not shift the narrower image toward one edge.
            VStack(alignment: .center, spacing: 0) {
                if !appearance.useEmbeddedElements,
                   appearance.controlPosition.showsOnTop
                {
                    let config = appearance.controlPosition.topConfiguration
                    let shouldShowTopToolbar = !windowSwitcherActive || (config.showControls && hasWindowSwitcherControlContent) || (config.showTitle && (appearance.showAppHeader || showsSelectionControl))
                    if shouldShowTopToolbar {
                        Group {
                            if windowSwitcherActive {
                                windowSwitcherContent(
                                    finalIsSelected,
                                    isLeadingControls: config.isLeadingControls,
                                    showTitleContent: config.showTitle,
                                    showControlsContent: config.showControls
                                )
                            } else {
                                dockPreviewContent(
                                    finalIsSelected,
                                    isLeadingControls: config.isLeadingControls,
                                    showTitleContent: config.showTitle,
                                    showControlsContent: config.showControls
                                )
                            }
                        }
                        .padding(.horizontal, switcherToolbarHorizontalPadding)
                        .padding(.bottom, 4)
                    }
                }

                windowContent(
                    isMinimized: windowInfo.isMinimized,
                    isHidden: isEffectivelyHidden,
                    isSelected: finalIsSelected
                )
                .if(switcherCardWidth != nil) { view in
                    view.frame(width: switcherCardWidth, alignment: .center)
                }

                if !appearance.useEmbeddedElements,
                   appearance.controlPosition.showsOnBottom
                {
                    let config = appearance.controlPosition.bottomConfiguration
                    let shouldShowBottomToolbar = !windowSwitcherActive || (config.showControls && hasWindowSwitcherControlContent) || (config.showTitle && (appearance.showAppHeader || showsSelectionControl))
                    if shouldShowBottomToolbar {
                        Group {
                            if windowSwitcherActive {
                                windowSwitcherContent(
                                    finalIsSelected,
                                    isLeadingControls: config.isLeadingControls,
                                    showTitleContent: config.showTitle,
                                    showControlsContent: config.showControls
                                )
                            } else {
                                dockPreviewContent(
                                    finalIsSelected,
                                    isLeadingControls: config.isLeadingControls,
                                    showTitleContent: config.showTitle,
                                    showControlsContent: config.showControls
                                )
                            }
                        }
                        .padding(.horizontal, switcherToolbarHorizontalPadding)
                        .padding(.top, 4)
                    }
                }
            }
            .if(switcherCardWidth != nil) { view in
                view.frame(width: switcherCardWidth, alignment: .center)
            }
            .if(switcherCardWidth == nil) { view in
                view.frame(maxWidth: dimensions.maxDimensions.width > 0 ? dimensions.maxDimensions.width : nil)
            }
            .previewCardChrome(
                uniformCardRadius: uniformCardRadius,
                paddingMultiplier: appearance.globalPaddingMultiplier,
                hideBackground: appearance.hidePreviewCardBackground,
                isHighlighted: finalIsSelected,
                isActiveWindow: isActiveWindow,
                highlightColor: appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor),
                highlightOpacity: appearance.selectionOpacity,
                activeBorderColor: appearance.activeAppIndicatorColor,
                backgroundAppearance: backgroundAppearance
            )
        }
        .overlay {
            if appearance.useEmbeddedElements {
                embeddedControlsOverlay(finalIsSelected)
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            let setHoverState: (Bool) -> Void = { newState in
                if appearance.showAnimations {
                    withAnimation(.snappy(duration: 0.175)) {
                        if windowSwitcherActive { isHoveringOverWindowSwitcherPreview = newState }
                        else { isHoveringOverDockPeekPreview = newState }
                    }
                } else {
                    if windowSwitcherActive { isHoveringOverWindowSwitcherPreview = newState }
                    else { isHoveringOverDockPeekPreview = newState }
                }
            }

            let currentHoverState = windowSwitcherActive ? isHoveringOverWindowSwitcherPreview : isHoveringOverDockPeekPreview

            switch phase {
            case let .active(location):
                let shouldShowHover = onHoverIndexChange?(index, location) ?? true
                if currentHoverState != shouldShowHover { setHoverState(shouldShowHover) }
            case .ended:
                _ = onHoverIndexChange?(nil, nil)
                if currentHoverState {
                    setHoverState(false)
                }
            }
        }
    }

    var body: some View {
        previewCoreContent
            .externalDragSpringLoading(
                windowInfo: windowInfo,
                index: index,
                uniformCardRadius: uniformCardRadius,
                appearance: appearance,
                windowSwitcherActive: windowSwitcherActive,
                handleWindowAction: handleWindowAction,
                onTap: onTap,
                onDragHoverIndexChange: onDragHoverIndexChange,
                dragSelection: dragSelection
            )
            .windowPreviewInteractions(
                windowInfo: windowInfo,
                windowSwitcherActive: windowSwitcherActive,
                dockPosition: dockPosition,
                pointerHoverActive: windowSwitcherActive
                    ? isHoveringOverWindowSwitcherPreview
                    : isHoveringOverDockPeekPreview,
                handleWindowAction: handleWindowAction,
                onTap: onTap
            )
            .fixedSize()
            .opacity(skeletonMode ? 0 : 1)
            .allowsHitTesting(!skeletonMode && !mockPreviewActive)
    }
}
