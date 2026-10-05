import Defaults
import SwiftUI

@MainActor
final class SpaceMoveMenuController: NSObject {
    static let shared = SpaceMoveMenuController()

    private weak var activeMenu: NSMenu?

    private struct MoveRequest {
        let window: WindowInfo
        let destination: ManagedSpaceDestination
        let dismissPreviews: (() -> Void)?
    }

    private struct FullscreenExitRequest {
        let window: WindowInfo
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

        if sourceValidation == .fullscreen {
            let item = NSMenuItem(
                title: String(localized: "Exit Full Screen to move this window", comment: "Action that exits fullscreen before moving a window between Spaces"),
                action: #selector(exitFullScreen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = FullscreenExitRequest(window: window)
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

        let cachedWindows = WindowUtil.getAllWindowsIgnoringSwitcherFilters().filter { !$0.isWindowlessApp }
        let showUnavailable = Defaults[.showUnavailableSpacesInMenu]
        let visibleDisplays = displays.compactMap { display -> (ManagedDisplayDescriptor, [ManagedSpaceDescriptor])? in
            let spaces = display.spaces.filter { space in
                space.kind == .desktop || (showUnavailable && space.kind == .fullscreen)
            }
            return spaces.isEmpty ? nil : (display, spaces)
        }
        let showsDisplayHeadings = visibleDisplays.count > 1

        for (displayIndex, entry) in visibleDisplays.enumerated() {
            if displayIndex > 0 {
                menu.addItem(.separator())
            }
            if showsDisplayHeadings {
                let fallback = String(localized: "Display \(displayIndex + 1)", comment: "Fallback display name in Space destination menu")
                addInformationalItem(WindowSpaces.displayName(for: entry.0.identifier) ?? fallback, to: menu)
            }

            for space in entry.1 {
                let destination = ManagedSpaceDestination(display: entry.0, space: space)
                let apps = apps(on: space, cachedWindows: cachedWindows)
                let title = menuTitle(for: space, apps: apps)
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.attributedTitle = attributedTitle(
                    title,
                    apps: apps,
                    includesFullscreenSymbol: space.kind == .fullscreen,
                    appearance: menu.effectiveAppearance
                )
                if entry.0.currentSpaceID == space.id,
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
                    let isCurrent = sourceSpaceIDs.contains(space.id)
                    item.state = isCurrent ? .on : .off
                    item.isEnabled = !isCurrent
                    if !isCurrent {
                        item.action = #selector(moveWindow(_:))
                        item.target = self
                        item.representedObject = MoveRequest(
                            window: window,
                            destination: destination,
                            dismissPreviews: dismissPreviews
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

    private func apps(on space: ManagedSpaceDescriptor, cachedWindows: [WindowInfo]) -> [NSRunningApplication] {
        var pids = space.ownerPIDs
        pids.formUnion(cachedWindows.compactMap { window in
            window.spaceID == Int(space.id) ? window.app.processIdentifier : nil
        })

        var seenApps = Set<String>()
        return pids.compactMap { pid in
            cachedWindows.first(where: { $0.app.processIdentifier == pid })?.app ??
                NSRunningApplication(processIdentifier: pid)
        }
        .filter { app in
            let identity = app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
            return seenApps.insert(identity).inserted
        }
        .sorted {
            ($0.localizedName ?? "").localizedStandardCompare($1.localizedName ?? "") == .orderedAscending
        }
    }

    private func menuTitle(for space: ManagedSpaceDescriptor, apps: [NSRunningApplication]) -> String {
        switch Defaults[.spaceMenuDisplayMode] {
        case .numberOnly:
            return "\(space.number)"
        case .fullName:
            if space.kind == .desktop {
                return String(localized: "Desktop \(space.desktopNumber ?? space.number)", comment: "Desktop name in Space destination menu")
            }
            let appNames = apps.compactMap(\.localizedName)
            return appNames.isEmpty
                ? String(localized: "Full Screen", comment: "Fallback fullscreen Space name")
                : appNames.joined(separator: " + ")
        }
    }

    private func attributedTitle(
        _ title: String,
        apps: [NSRunningApplication],
        includesFullscreenSymbol: Bool,
        appearance: NSAppearance
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(string: title)
        var attachmentCount = 0

        func appendImage(_ image: NSImage, usesPrimaryColor: Bool = false) {
            result.append(NSAttributedString(string: attachmentCount == 0 ? "\u{00A0}\u{00A0}" : "\u{00A0}"))
            let attachment = NSTextAttachment()
            let resizedImage = image.resizedToFit(in: NSSize(width: 14, height: 14))
            var attachmentImage = resizedImage
            if usesPrimaryColor {
                appearance.performAsCurrentDrawingAppearance {
                    attachmentImage = resizedImage.tint(color: .labelColor)
                }
            }
            attachment.image = attachmentImage
            attachment.bounds = NSRect(x: 0, y: -3, width: 14, height: 14)
            result.append(NSAttributedString(attachment: attachment))
            attachmentCount += 1
        }

        if includesFullscreenSymbol,
           let symbol = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: nil)
        {
            appendImage(symbol, usesPrimaryColor: true)
        }

        let appIcons = apps.compactMap(\.icon)
        let visibleAppIcons = appIcons.prefix(max(0, 5 - attachmentCount))
        for image in visibleAppIcons {
            appendImage(image)
        }
        let hiddenAppIconCount = appIcons.count - visibleAppIcons.count
        if hiddenAppIconCount > 0 {
            result.append(NSAttributedString(string: " +\(hiddenAppIconCount)"))
        }
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
        WindowUtil.performConfirmedSpaceMove(
            request.window,
            to: request.destination,
            dismissPreviews: request.dismissPreviews
        )
    }

    @objc private func exitFullScreen(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? FullscreenExitRequest,
              WindowUtil.exitFullScreenWithoutActivation(request.window)
        else {
            NSSound.beep()
            return
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
    if windowInfo.hasLimitedWindowControls {
        return configuredButtons.intersection([.quit, .close])
    }
    guard windowInfo.closeButton != nil || windowInfo.isMinimized || windowInfo.isEffectivelyHiddenForUI else {
        return configuredButtons.intersection([.quit])
    }
    return configuredButtons
}

enum WindowStateSymbolResolver {
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

extension View {
    func embeddedPreviewContrastShadow(_ isEnabled: Bool) -> some View {
        modifier(EmbeddedPreviewContrastShadow(isEnabled: isEnabled))
    }
}

struct WindowStateIndicator: View {
    static let unstyledControlLineHeight: CGFloat = 24
    private static let styledBadgeMinimumSize: CGFloat = 14
    private static let styledContentPadding: CGFloat = 4

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

struct PreviewAppearanceSettings: Equatable {
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
    let showWindowlessAppQuitButton: Bool
    let titleOverflowStyle: TitleOverflowStyle

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

    static let observedKeys: [Defaults._AnyKey] = [
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
        .showActiveWindowBorder, .activeAppIndicatorColor, .showAnimations, .globalPaddingMultiplier,
        .uniformCardRadius, .previewCornerRadius,
        .windowTitleFontSize, .windowStateIndicatorFontSize, .switcherAppIconSize, .trafficLightButtonScale,
        .previewWidth, .compactModeWidth, .compactModeTitleFormat, .compactModeItemSize, .compactModeHideTrafficLights,
        .showWindowlessAppQuitButton, .titleOverflowStyle,
    ]

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

        return PreviewAppearanceSettings(
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

    @State private var isHoveringOverDockPeekPreview = false
    @State private var isHoveringOverWindowSwitcherPreview = false

    private var effectiveTrafficLightButtons: Set<WindowAction> {
        resolvedTrafficLightButtons(
            for: windowInfo,
            configuredButtons: appearance.enabledTrafficLightButtons,
            showWindowlessQuitButton: appearance.showWindowlessAppQuitButton
        )
    }

    private var isEffectivelyHidden: Bool {
        windowInfo.isEffectivelyHiddenForUI
    }

    private var windowStateLabel: String? {
        guard appearance.windowStateIndicatorPlacement == .onWindowPreviews else { return nil }
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
        WindowStateSymbolResolver.symbols(
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
        guard appearance.windowStateIndicatorPlacement == .onWindowPreviews else { return nil }
        if windowInfo.isMinimized {
            return "minus.circle"
        } else if isEffectivelyHidden {
            return "eye.slash"
        } else if windowInfo.isFullscreen == true {
            return "arrow.up.left.and.arrow.down.right"
        }
        return nil
    }

    private var embeddedControlsAreLeading: Bool {
        let topConfiguration = appearance.controlPosition.topConfiguration
        return topConfiguration.showControls
            ? topConfiguration.isLeadingControls
            : appearance.controlPosition.bottomConfiguration.isLeadingControls
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
        @ViewBuilder content: () -> some View
    ) -> some View {
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
                windowStateIndicator
            } else {
                windowStateIndicator
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
        if hasAdjacentControl {
            return hasVisibleTrafficLights && appearance.disableDockStyleTrafficLights ? 6 : 8
        }
        return !appearance.useEmbeddedElements && appearance.disableDockStyleWindowStateIndicator ? 8 : 0
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
        l.index == r.index && l.isSelected == r.isSelected && l.useLivePreview == r.useLivePreview
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
        guard appearance.showActiveWindowBorder else { return false }
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

    private func switcherAppIconSize(hasSecondaryLabel: Bool) -> CGFloat {
        if appearance.switcherAppIconSize > 0 {
            return min(max(appearance.switcherAppIconSize, 16), 64)
        }

        return hasSecondaryLabel ? 35 : 20
    }

    @ViewBuilder
    private func titleLabel(_ text: String, adaptsToAvailableWidth: Bool = false, scrolls: Bool = true) -> some View {
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

    @ViewBuilder
    private func windowContent(isMinimized: Bool, isHidden: Bool, isSelected: Bool) -> some View {
        let inactive = (isMinimized || isHidden) && appearance.dimMinimizedHiddenPreviews
        let stateSymbol = windowStateSymbol
        let quality = appearance.livePreviewQuality
        let frameRate = appearance.livePreviewFrameRate

        Group {
            if skeletonMode {
                Color.clear
            } else if useLivePreview {
                LivePreviewImage(windowID: windowInfo.id, fallbackImage: windowInfo.image, quality: quality, frameRate: frameRate)
            } else if let cgImage = windowInfo.image {
                Image(decorative: cgImage, scale: 1.0)
                    .resizable()
                    .scaledToFit()
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
            allowDynamicSizing: appearance.allowDynamicImageSizing,
            dimensions: dimensions,
            dockPosition: dockPosition,
            windowSwitcherActive: windowSwitcherActive
        )
        .opacity(isSelected ? 1.0 : appearance.unselectedContentOpacity)
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
            hasTitleContent: appearance.showAppHeader,
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
        let titleToShow: String? = if let windowTitle = windowInfo.windowName, !windowTitle.isEmpty {
            windowTitle
        } else {
            windowInfo.app.localizedName
        }

        let titlePresentation = WindowTitlePresentation.resolve(
            title: titleToShow,
            showWindowTitle: appearance.showWindowTitle,
            visibility: appearance.windowTitleVisibility,
            isHighlighted: selected
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
        let controlsHeight = controlClusterHeight(adjacentControlHeight: configuredAdjacentHeight)
        let titleIsConfigured = appearance.showWindowTitle && titleToShow != nil
        let sharesToolbarRow = switch appearance.controlPosition {
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing: true
        default: false
        }
        let edgeInsets = sharesToolbarRow
            ? rowEdgeInsets(
                titleHeight: titleIsConfigured ? dockTitleControlHeight() : nil,
                controlsHeight: controlsHeight
            )
            : (title: 0, controls: 0)
        let titleTextAlignment: TextAlignment = appearance.controlPosition.titleIsTrailing ? .trailing : .leading
        let titleContent = Group {
            if titlePresentation.reservesSpace, let title = titleToShow {
                titleLabel(title, adaptsToAvailableWidth: true, scrolls: titlePresentation.isVisible)
                    .font(appearance.windowTitleFontSize.font)
                    .multilineTextAlignment(titleTextAlignment)
                    .padding(4)
                    .if(!appearance.disableDockStyleTitles) { view in
                        view.materialPill(backgroundAppearance: backgroundAppearance)
                    }
                    .frame(minWidth: 0)
                    .clipped()
                    .embeddedPreviewContrastShadow(appearance.usesEmbeddedTitleContrastShadow)
                    .opacity(titlePresentation.isVisible ? 1 : 0)
            }
        }
        .previewOuterEdgePadding(edgeInsets.title, onLeadingEdge: !embeddedControlsAreLeading, enabled: titlePresentation.reservesSpace)

        let controlsContent = controlsWithWindowStateIndicator(
            controlsAreLeading: embeddedControlsAreLeading,
            hasAdjacentControl: hasVisibleAdjacentControl,
            adjacentControlHeight: configuredAdjacentHeight,
            spacing: controlsSpacing(
                hasAdjacentControl: hasVisibleAdjacentControl,
                hasVisibleTrafficLights: hasTrafficLights && showTrafficLights
            )
        ) {
            if hasTrafficLights {
                TrafficLightButtons(
                    previewAppearance: appearance,
                    hoveringOverParentWindow: selected || isHoveringOverDockPeekPreview,
                    onWindowAction: handleWindowAction,
                    mockPreviewActive: mockPreviewActive,
                    enabledButtons: effectiveTrafficLightButtons,
                    backgroundAppearance: backgroundAppearance
                )
                .frame(width: showTrafficLights ? nil : 0)
                .clipped()
                .embeddedPreviewContrastShadow(appearance.usesEmbeddedTrafficLightContrastShadow)
                .animation(nil, value: showTrafficLights)
            } else if let stateLabel = visibleWindowStateLabel,
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
        .previewOuterEdgePadding(
            edgeInsets.controls,
            onLeadingEdge: embeddedControlsAreLeading,
            enabled: hasWindowStateIndicator || hasVisibleAdjacentControl
        )

        if titlePresentation.reservesSpace || hasTrafficLights || hasWindowStateIndicator {
            switch appearance.controlPosition {
            case .topLeading, .topTrailing:
                VStack {
                    HStack(spacing: 0) {
                        if appearance.controlPosition == .topLeading {
                            titleContent
                            Spacer(minLength: 8)
                            controlsContent
                        } else {
                            controlsContent
                            Spacer(minLength: 8)
                            titleContent
                        }
                    }
                    .padding(8)
                    Spacer()
                }
            case .bottomLeading, .bottomTrailing:
                VStack {
                    Spacer()
                    HStack(spacing: 0) {
                        if appearance.controlPosition == .bottomLeading {
                            titleContent
                            Spacer(minLength: 8)
                            controlsContent
                        } else {
                            controlsContent
                            Spacer(minLength: 8)
                            titleContent
                        }
                    }
                    .padding(8)
                }
            case .centeredTitleTopControlsBottom:
                VStack {
                    HStack {
                        Spacer()
                        titleContent
                        Spacer()
                    }
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        Spacer()
                        controlsContent
                        Spacer()
                    }
                    .padding(.bottom, 8)
                }
            case .centeredControlsTopTitleBottom:
                VStack {
                    HStack {
                        Spacer()
                        controlsContent
                        Spacer()
                    }
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        Spacer()
                        titleContent
                        Spacer()
                    }
                    .padding(.bottom, 8)
                }
            case .diagonalTopLeftBottomRight:
                VStack {
                    HStack {
                        titleContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        Spacer()
                        controlsContent
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
            case .diagonalTopRightBottomLeft:
                VStack {
                    HStack {
                        Spacer()
                        titleContent
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        controlsContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
                }
            case .diagonalBottomLeftTopRight:
                VStack {
                    HStack {
                        Spacer()
                        controlsContent
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        titleContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
                }
            case .diagonalBottomRightTopLeft:
                VStack {
                    HStack {
                        controlsContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        Spacer()
                        titleContent
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
            case .parallelTopLeftBottomLeft:
                VStack {
                    HStack {
                        titleContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        controlsContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
                }
            case .parallelTopRightBottomRight:
                VStack {
                    HStack {
                        Spacer()
                        titleContent
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        Spacer()
                        controlsContent
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
            case .parallelBottomLeftTopLeft:
                VStack {
                    HStack {
                        controlsContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        titleContent
                        Spacer()
                    }
                    .padding(.leading, 8)
                    .padding(.bottom, 8)
                }
            case .parallelBottomRightTopRight:
                VStack {
                    HStack {
                        Spacer()
                        controlsContent
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 8)
                    Spacer()
                    HStack {
                        Spacer()
                        titleContent
                    }
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func windowSwitcherContent(
        _ selected: Bool,
        isLeadingControls: Bool,
        showTitleContent: Bool = true,
        showControlsContent: Bool = true
    ) -> some View {
        let shouldShowAppHeader = appearance.showAppHeader && showTitleContent
        let shouldShowControls = showControlsContent && hasWindowSwitcherControlContent
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
        let windowTitle = windowInfo.windowName
        let hasWindowTitleLabel = shouldShowWindowTitle &&
            windowTitle?.isEmpty == false &&
            windowTitle != windowInfo.app.localizedName
        let appIconSize = switcherAppIconSize(hasSecondaryLabel: hasWindowTitleLabel)
        let configuredWindowTitle = appearance.showWindowTitle &&
            windowTitle?.isEmpty == false &&
            windowTitle != windowInfo.app.localizedName
        let labelsHeight = showAppIconOnly
            ? 0
            : WindowTitleFontSize.bodyLineHeight +
            (configuredWindowTitle ? appearance.windowTitleFontSize.measuredLineHeight : 0)
        let titleHeight = shouldShowAppHeader ? max(appIconSize, labelsHeight) : nil
        let controlsHeight = shouldShowControls
            ? controlClusterHeight(adjacentControlHeight: configuredAdjacentHeight)
            : nil
        let edgeInsets = rowEdgeInsets(titleHeight: titleHeight, controlsHeight: controlsHeight)

        let titleOnRight = appearance.controlPosition.titleIsTrailing
        let titleAlignment: HorizontalAlignment = titleOnRight ? .trailing : .leading
        let textAlignment: TextAlignment = titleOnRight ? .trailing : .leading
        let titleAndSubtitleContent = VStack(alignment: titleAlignment, spacing: 0) {
            if !showAppIconOnly {
                Text(windowInfo.app.localizedName ?? "Unknown")
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(1)
            }

            if let windowTitle, hasWindowTitleLabel {
                titleLabel(windowTitle, adaptsToAvailableWidth: true)
                    .font(appearance.windowTitleFontSize.font)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(textAlignment)
            }
        }
        .embeddedPreviewContrastShadow(appearance.usesEmbeddedTitleContrastShadow)

        let appIconContent = Group {
            if let appIcon = windowInfo.app.icon {
                PreviewAppIcon(
                    icon: appIcon,
                    bundleURL: windowInfo.app.bundleURL,
                    size: appIconSize,
                    showBadge: windowSwitcherActive && appearance.showAppIconBadges,
                    badgeScale: appearance.appIconBadgeScale,
                    mockPreviewActive: mockPreviewActive
                )
            }
        }

        let controlsContent = controlsWithWindowStateIndicator(
            controlsAreLeading: isLeadingControls,
            hasAdjacentControl: hasVisibleAdjacentControl,
            adjacentControlHeight: configuredAdjacentHeight,
            spacing: controlsSpacing(
                hasAdjacentControl: hasVisibleAdjacentControl,
                hasVisibleTrafficLights: canRenderTrafficLightButtons && showTrafficLights
            )
        ) {
            if canRenderTrafficLightButtons {
                TrafficLightButtons(
                    previewAppearance: appearance,
                    hoveringOverParentWindow: selected || isHoveringOverWindowSwitcherPreview,
                    onWindowAction: handleWindowAction,
                    mockPreviewActive: mockPreviewActive,
                    enabledButtons: effectiveTrafficLightButtons,
                    backgroundAppearance: backgroundAppearance
                )
                .frame(width: showTrafficLights ? nil : 0)
                .clipped()
                .embeddedPreviewContrastShadow(appearance.usesEmbeddedTrafficLightContrastShadow)
            } else if let stateLabel = visibleWindowStateLabel,
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

        let controlsGap: CGFloat = (canRenderTrafficLightButtons && showTrafficLights) ? 0 : 8

        let titleContent = PreviewTitleCluster(iconOnRight: titleOnRight) {
            appIconContent
        } labels: {
            titleAndSubtitleContent
        }
        .layoutPriority(1)
        .previewOuterEdgePadding(edgeInsets.title, onLeadingEdge: !isLeadingControls, enabled: shouldShowAppHeader)

        if !shouldShowAppHeader, !shouldShowControls {
            return AnyView(EmptyView())
        } else if appearance.controlPosition.isCentered {
            return AnyView(
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    if shouldShowAppHeader {
                        titleContent
                    }
                    if shouldShowControls { controlsContent }
                    Spacer(minLength: 0)
                }
                .frame(width: dimensions.size.width)
                .animation(nil, value: showTrafficLights)
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
                .frame(width: dimensions.size.width)
                .animation(nil, value: showTrafficLights)
            )
        }
    }

    private func dockPreviewContent(
        _ selected: Bool,
        isLeadingControls: Bool,
        showTitleContent: Bool = true,
        showControlsContent: Bool = true
    ) -> some View {
        // Determine what title to show: window name first, then app name as fallback
        let titleToShow: String? = if let windowTitle = windowInfo.windowName, !windowTitle.isEmpty {
            windowTitle
        } else {
            windowInfo.app.localizedName
        }

        let titlePresentation = WindowTitlePresentation.resolve(
            title: titleToShow,
            showWindowTitle: appearance.showWindowTitle && showTitleContent,
            visibility: appearance.windowTitleVisibility,
            isHighlighted: selected
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
        let titleIsConfigured = appearance.showWindowTitle && titleToShow != nil && showTitleContent
        let controlsHeight = showControlsContent
            ? controlClusterHeight(adjacentControlHeight: configuredAdjacentHeight)
            : nil
        let edgeInsets = rowEdgeInsets(
            titleHeight: titleIsConfigured ? dockTitleControlHeight() : nil,
            controlsHeight: controlsHeight
        )
        let titleTextAlignment: TextAlignment = appearance.controlPosition.titleIsTrailing ? .trailing : .leading
        let titleContent = Group {
            if titlePresentation.reservesSpace, let title = titleToShow {
                titleLabel(title, adaptsToAvailableWidth: true, scrolls: titlePresentation.isVisible)
                    .font(appearance.windowTitleFontSize.font)
                    .multilineTextAlignment(titleTextAlignment)
                    .padding(4)
                    .if(!appearance.disableDockStyleTitles) { view in
                        view.materialPill(backgroundAppearance: backgroundAppearance)
                    }
                    .frame(minWidth: 0)
                    .clipped()
                    .embeddedPreviewContrastShadow(appearance.usesEmbeddedTitleContrastShadow)
                    .opacity(titlePresentation.isVisible ? 1 : 0)
            }
        }
        .previewOuterEdgePadding(edgeInsets.title, onLeadingEdge: !isLeadingControls, enabled: titlePresentation.reservesSpace)

        let controlsContent = controlsWithWindowStateIndicator(
            controlsAreLeading: isLeadingControls,
            hasAdjacentControl: hasVisibleAdjacentControl,
            adjacentControlHeight: configuredAdjacentHeight,
            spacing: controlsSpacing(
                hasAdjacentControl: hasVisibleAdjacentControl,
                hasVisibleTrafficLights: hasTrafficLights && showTrafficLights
            )
        ) {
            if hasTrafficLights {
                TrafficLightButtons(
                    previewAppearance: appearance,
                    hoveringOverParentWindow: selected || isHoveringOverDockPeekPreview,
                    onWindowAction: handleWindowAction,
                    mockPreviewActive: mockPreviewActive,
                    enabledButtons: effectiveTrafficLightButtons,
                    backgroundAppearance: backgroundAppearance
                )
                .frame(width: showTrafficLights ? nil : 0)
                .clipped()
                .embeddedPreviewContrastShadow(appearance.usesEmbeddedTrafficLightContrastShadow)
            } else if let stateLabel = visibleWindowStateLabel,
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

        if titlePresentation.reservesSpace || (showControlsContent && (hasTrafficLights || hasWindowStateIndicator)) {
            if appearance.controlPosition.isCentered {
                return AnyView(
                    HStack(spacing: 4) {
                        Spacer(minLength: 0)
                        if showTitleContent { titleContent }
                        if showControlsContent { controlsContent }
                        Spacer(minLength: 0)
                    }
                    .frame(width: dimensions.size.width)
                    .animation(nil, value: showTrafficLights)
                )
            } else {
                return AnyView(
                    HStack(spacing: 0) {
                        if isLeadingControls {
                            if showControlsContent { controlsContent }
                            Spacer(minLength: 8)
                            if showTitleContent { titleContent }
                        } else {
                            if showTitleContent { titleContent }
                            Spacer(minLength: 8)
                            if showControlsContent { controlsContent }
                        }
                    }
                    .frame(width: dimensions.size.width)
                    .animation(nil, value: showTrafficLights)
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
            VStack(alignment: .leading, spacing: 0) {
                if !appearance.useEmbeddedElements,
                   appearance.controlPosition.showsOnTop
                {
                    let config = appearance.controlPosition.topConfiguration
                    let shouldShowTopToolbar = !windowSwitcherActive || (config.showControls && hasWindowSwitcherControlContent) || (config.showTitle && appearance.showAppHeader)
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
                    let shouldShowBottomToolbar = !windowSwitcherActive || (config.showControls && hasWindowSwitcherControlContent) || (config.showTitle && appearance.showAppHeader)
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
                onDragHoverIndexChange: onDragHoverIndexChange
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
