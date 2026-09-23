import Defaults
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SpaceMoveMenuController: NSObject {
    static let shared = SpaceMoveMenuController()

    private weak var activeMenu: NSMenu?

    private struct MoveRequest {
        let window: WindowInfo
        let destinationSpaceID: CGSSpaceID
        let dismissPreviews: (() -> Void)?
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

    private func makeMenu(for window: WindowInfo, dismissPreviews: (() -> Void)?) -> NSMenu {
        let menu = NSMenu(title: String(localized: "Move to Space", comment: "Space destination menu title"))
        let displays = WindowSpaces.managedDisplays(includeOwners: true)
        let availableSpaces = displays.flatMap(\.spaces).filter { $0.kind == .desktop }
        let availableSpaceIDs = Set(availableSpaces.map(\.id))
        let reportedSpaceIDs = Set(window.id.cgsSpaces())
        let sourceSpaceIDs = reportedSpaceIDs.isEmpty
            ? Set(window.spaceID.map { [CGSSpaceID($0)] } ?? [])
            : reportedSpaceIDs
        let sourceDesktopSpaceIDs = sourceSpaceIDs.intersection(availableSpaceIDs)

        if window.isFullscreen == true || (try? window.axElement.isFullscreen()) == true {
            addInformationalItem(
                String(localized: "Exit Full Screen to move this window", comment: "Unavailable Space movement explanation"),
                to: menu
            )
            return menu
        }

        if sourceDesktopSpaceIDs.count > 1 {
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
                let apps = apps(on: space, cachedWindows: cachedWindows)
                let title = menuTitle(for: space, apps: apps)
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.attributedTitle = attributedTitle(
                    title,
                    apps: apps,
                    includesFullscreenSymbol: space.kind == .fullscreen,
                    appearance: menu.effectiveAppearance
                )

                if space.kind == .desktop {
                    let isCurrent = sourceSpaceIDs.contains(space.id)
                    item.state = isCurrent ? .on : .off
                    item.isEnabled = !isCurrent
                    if !isCurrent {
                        item.action = #selector(moveWindow(_:))
                        item.target = self
                        item.representedObject = MoveRequest(
                            window: window,
                            destinationSpaceID: space.id,
                            dismissPreviews: dismissPreviews
                        )
                    }
                } else {
                    item.isEnabled = false
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

    @objc private func moveWindow(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? MoveRequest else { return }

        WindowUtil.moveWindowConfirmed(request.window, toManagedSpace: request.destinationSpaceID) { success in
            guard success, Defaults[.switchToDestinationSpaceAfterMoving] else { return }

            request.dismissPreviews?()
            var movedWindow = request.window
            if movedWindow.app.isHidden {
                movedWindow.app.unhide()
                WindowUtil.updateCachedWindowState(movedWindow, isHidden: false)
            }
            if movedWindow.isMinimized {
                try? movedWindow.axElement.setAttribute(kAXMinimizedAttribute, false)
                movedWindow.isMinimized = false
                WindowUtil.updateCachedWindowState(movedWindow, isMinimized: false)
            }
            movedWindow.bringToFront()
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

struct WindowStateIndicator: View {
    static let unstyledControlLineHeight: CGFloat = 24
    private static let styledBadgeMinimumSize = CGSize(width: 14, height: 14)

    let number: Int?
    let stateSymbols: [String]
    let disableDockStyling: Bool
    let backgroundAppearance: BackgroundAppearance
    let highlightsCurrentSpace: Bool
    let highlightColor: Color
    let highlightOpacity: Double
    let activeBorderColor: Color

    @ViewBuilder
    private func badgeContent(minimumWidth: CGFloat?, minimumHeight: CGFloat) -> some View {
        if let number {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
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
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    var body: some View {
        Group {
            if disableDockStyling {
                HStack(spacing: 4) {
                    if number != nil {
                        badgeContent(minimumWidth: 18, minimumHeight: 18)
                            .overlay {
                                Capsule().stroke(
                                    highlightsCurrentSpace ? activeBorderColor : .secondary,
                                    lineWidth: highlightsCurrentSpace ? 2.5 : 1
                                )
                            }
                    }
                    stateIcons()
                }
                .frame(height: Self.unstyledControlLineHeight)
                .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
            } else {
                HStack(spacing: 4) {
                    badgeContent(minimumWidth: nil, minimumHeight: 0)
                    stateIcons()
                }
                .frame(
                    minWidth: Self.styledBadgeMinimumSize.width,
                    minHeight: Self.styledBadgeMinimumSize.height
                )
                .padding(4)
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
    let windowTitleFontSize: WindowTitleFontSize
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

    static let observedKeys: [Defaults._AnyKey] = [
        .trafficLightButtonsVisibility, .switcherTrafficLightButtonsVisibility, .cmdTabTrafficLightButtonsVisibility,
        .enabledTrafficLightButtons, .switcherEnabledTrafficLightButtons, .cmdTabEnabledTrafficLightButtons,
        .useMonochromeTrafficLights, .switcherUseMonochromeTrafficLights, .cmdTabUseMonochromeTrafficLights,
        .switcherShowAppHeader,
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
        .dimMinimizedHiddenPreviews, .selectionOpacity, .unselectedContentOpacity, .hoverHighlightColor,
        .allowDynamicImageSizing, .hidePreviewCardBackground,
        .tapEquivalentInterval, .switcherTapEquivalentInterval, .cmdTabTapEquivalentInterval,
        .previewHoverAction, .switcherPreviewHoverAction, .cmdTabPreviewHoverAction,
        .keepPreviewOnHoverActivation,
        .showActiveWindowBorder, .activeAppIndicatorColor, .showAnimations, .globalPaddingMultiplier,
        .windowTitleFontSize, .switcherAppIconSize, .trafficLightButtonScale,
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
            showWindowTitle: pick(.showWindowTitle, switcher: .switcherShowWindowTitle, cmdTab: .cmdTabShowWindowTitle),
            windowTitleVisibility: pick(.windowTitleVisibility, switcher: .switcherWindowTitleVisibility, cmdTab: .cmdTabWindowTitleVisibility),
            controlPosition: pick(.dockPreviewControlPosition, switcher: .windowSwitcherControlPosition, cmdTab: .cmdTabControlPosition),
            useEmbeddedElements: pick(.useEmbeddedDockPreviewElements, switcher: .switcherUseEmbeddedDockPreviewElements, cmdTab: .cmdTabUseEmbeddedDockPreviewElements),
            disableDockStyleTrafficLights: pick(.disableDockStyleTrafficLights, switcher: .switcherDisableDockStyleTrafficLights, cmdTab: .cmdTabDisableDockStyleTrafficLights),
            disableDockStyleTitles: pick(.disableDockStyleTitles, cmdTab: .cmdTabDisableDockStyleTitles),
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
            windowTitleFontSize: Defaults[.windowTitleFontSize],
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
            showWindowlessAppQuitButton: Defaults[.showWindowlessAppQuitButton],
            titleOverflowStyle: Defaults[.titleOverflowStyle]
        )
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
    let onHoverIndexChange: ((Int?, CGPoint?) -> Void)?
    let onDragHoverIndexChange: ((Int?) -> Void)?
    let useLivePreview: Bool
    var skeletonMode: Bool = false
    var appearance: PreviewAppearanceSettings
    let backgroundAppearance: BackgroundAppearance
    let focusedWindowID: CGWindowID?
    let currentSpaceNumbers: Set<Int>

    @State private var isHoveringOverDockPeekPreview = false
    @State private var isHoveringOverWindowSwitcherPreview = false
    @State private var isDraggingOver = false
    @State private var dragTimer: Timer?
    @State private var highlightOpacity = 0.0

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
    private func windowStateIndicator(
        controlsAreLeading: Bool,
        nonAlignmentPadding: CGFloat
    ) -> some View {
        let stateSymbols = movesWindowStateToIndicator ? windowStateSymbols : []
        let spaceNumber = appearance.showSpaceNumberIndicator ? windowInfo.spaceNumber : nil
        if spaceNumber != nil || !stateSymbols.isEmpty {
            let adjustedPadding = stateSymbols.isEmpty ? max(0, nonAlignmentPadding) : 0
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
                    backgroundAppearance: backgroundAppearance,
                    highlightsCurrentSpace: appearance.highlightCurrentSpaceNumberIndicator &&
                        spaceNumber.map(currentSpaceNumbers.contains) == true,
                    highlightColor: appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor),
                    highlightOpacity: appearance.selectionOpacity,
                    activeBorderColor: appearance.activeAppIndicatorColor
                )
            }
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .padding(.leading, controlsAreLeading ? 0 : -adjustedPadding)
            .padding(.trailing, controlsAreLeading ? -adjustedPadding : 0)
        }
    }

    @ViewBuilder
    private func controlsWithWindowStateIndicator(
        controlsAreLeading: Bool,
        nonAlignmentPadding: CGFloat = 0,
        spacing: CGFloat = 8,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let sideInset: CGFloat = nonAlignmentPadding > 0 ? 2 : 0
        HStack(spacing: spacing) {
            if controlsAreLeading {
                content()
                windowStateIndicator(
                    controlsAreLeading: true,
                    nonAlignmentPadding: nonAlignmentPadding
                )
            } else {
                windowStateIndicator(
                    controlsAreLeading: false,
                    nonAlignmentPadding: nonAlignmentPadding
                )
                content()
            }
        }
        .padding(.leading, controlsAreLeading ? 0 : sideInset)
        .padding(.trailing, controlsAreLeading ? sideInset : 0)
    }

    private func controlsSpacing(hasAdjacentControl: Bool) -> CGFloat {
        appearance.disableDockStyleWindowStateIndicator || hasAdjacentControl ? 8 : 0
    }

    private var canRenderTrafficLightButtons: Bool {
        appearance.trafficLightVisibility != .never &&
            !effectiveTrafficLightButtons.isEmpty
    }

    private func shouldShowTrafficLightButtons(parentHovered: Bool) -> Bool {
        appearance.trafficLightVisibility.isVisible(
            hoveringOverParentWindow: parentHovered,
            mockPreviewActive: mockPreviewActive
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
    private func titleLabel(_ text: String, adaptsToAvailableWidth: Bool = false) -> some View {
        switch appearance.titleOverflowStyle {
        case .marquee:
            MarqueeText(text: text, startDelay: 1, adaptsToAvailableWidth: adaptsToAvailableWidth)
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
        .clipShape(RoundedRectangle(cornerRadius: CardRadius.image, style: .continuous))
        .dynamicWindowFrame(
            allowDynamicSizing: appearance.allowDynamicImageSizing,
            dimensions: dimensions,
            dockPosition: dockPosition,
            windowSwitcherActive: windowSwitcherActive
        )
        .opacity(isSelected ? 1.0 : appearance.unselectedContentOpacity)
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
        VStack(spacing: 0) {
            if appearance.controlPosition.showsOnTop {
                let config = appearance.controlPosition.topConfiguration
                let shouldShowTopToolbar = (config.showControls && hasWindowSwitcherControlContent) || (config.showTitle && appearance.showAppHeader)
                if shouldShowTopToolbar {
                    windowSwitcherContent(
                        selected,
                        isLeadingControls: config.isLeadingControls,
                        showTitleContent: config.showTitle,
                        showControlsContent: config.showControls
                    )
                    .padding(8)
                }
            }

            Spacer()

            if appearance.controlPosition.showsOnBottom {
                let config = appearance.controlPosition.bottomConfiguration
                let shouldShowBottomToolbar = (config.showControls && hasWindowSwitcherControlContent) || (config.showTitle && appearance.showAppHeader)
                if shouldShowBottomToolbar {
                    windowSwitcherContent(
                        selected,
                        isLeadingControls: config.isLeadingControls,
                        showTitleContent: config.showTitle,
                        showControlsContent: config.showControls
                    )
                    .padding(8)
                }
            }
        }
    }

    @ViewBuilder
    private func embeddedDockPreviewControls(_ selected: Bool) -> some View {
        let titleToShow: String? = if let windowTitle = windowInfo.windowName, !windowTitle.isEmpty {
            windowTitle
        } else {
            windowInfo.app.localizedName
        }

        let hasTitle = appearance.showWindowTitle &&
            titleToShow != nil &&
            (appearance.windowTitleVisibility == .alwaysVisible || selected)

        let hasTrafficLights = canRenderTrafficLightButtons
        let showTrafficLights = shouldShowTrafficLightButtons(
            parentHovered: selected || isHoveringOverDockPeekPreview
        )
        let hasVisibleAdjacentControl = (hasTrafficLights && showTrafficLights) ||
            (!hasTrafficLights && visibleWindowStateLabel != nil && appearance.trafficLightVisibility != .never)
        let titleContent = Group {
            if hasTitle, let title = titleToShow {
                titleLabel(title, adaptsToAvailableWidth: true)
                    .font(appearance.windowTitleFontSize.font)
                    .padding(4)
                    .if(!appearance.disableDockStyleTitles) { view in
                        view.materialPill(backgroundAppearance: backgroundAppearance)
                    }
                    .frame(minWidth: 0)
                    .clipped()
            }
        }

        let controlsContent = controlsWithWindowStateIndicator(
            controlsAreLeading: embeddedControlsAreLeading,
            nonAlignmentPadding: hasTrafficLights && showTrafficLights ? 10 : 0,
            spacing: controlsSpacing(hasAdjacentControl: hasVisibleAdjacentControl)
        ) {
            if hasTrafficLights {
                TrafficLightButtons(
                    displayMode: appearance.trafficLightVisibility,
                    hoveringOverParentWindow: selected || isHoveringOverDockPeekPreview,
                    onWindowAction: handleWindowAction,
                    pillStyling: !appearance.disableDockStyleTrafficLights,
                    mockPreviewActive: mockPreviewActive,
                    enabledButtons: effectiveTrafficLightButtons,
                    useMonochrome: appearance.useMonochromeTrafficLights,
                    buttonScale: appearance.trafficLightButtonScale,
                    backgroundAppearance: backgroundAppearance
                )
                .frame(width: showTrafficLights ? nil : 0)
                .clipped()
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
            }
        }

        if hasTitle || hasTrafficLights || hasWindowStateIndicator {
            switch appearance.controlPosition {
            case .topLeading, .topTrailing:
                VStack {
                    HStack(spacing: 4) {
                        if appearance.controlPosition == .topLeading {
                            titleContent
                            Spacer()
                            controlsContent
                        } else {
                            controlsContent
                            Spacer()
                            titleContent
                        }
                    }
                    .padding(8)
                    Spacer()
                }
            case .bottomLeading, .bottomTrailing:
                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        if appearance.controlPosition == .bottomLeading {
                            titleContent
                            Spacer()
                            controlsContent
                        } else {
                            controlsContent
                            Spacer()
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

    private func windowSwitcherContent(_ selected: Bool, isLeadingControls: Bool, showTitleContent: Bool = true, showControlsContent: Bool = true) -> some View {
        let shouldShowAppHeader = appearance.showAppHeader && showTitleContent
        let shouldShowControls = showControlsContent && hasWindowSwitcherControlContent
        let shouldShowWindowTitle = appearance.showWindowTitle &&
            (appearance.windowTitleVisibility == .alwaysVisible || selected || isHoveringOverWindowSwitcherPreview)
        let showTrafficLights = shouldShowTrafficLightButtons(
            parentHovered: selected || isHoveringOverWindowSwitcherPreview
        )
        let hasVisibleAdjacentControl = (canRenderTrafficLightButtons && showTrafficLights) ||
            (!canRenderTrafficLightButtons && visibleWindowStateLabel != nil && appearance.trafficLightVisibility != .never)
        let windowTitle = windowInfo.windowName
        let hasWindowTitleLabel = shouldShowWindowTitle &&
            windowTitle?.isEmpty == false &&
            windowTitle != windowInfo.app.localizedName
        let appIconSize = switcherAppIconSize(hasSecondaryLabel: hasWindowTitleLabel)

        let titleAndSubtitleContent = VStack(alignment: .leading, spacing: 0) {
            if !showAppIconOnly {
                Text(windowInfo.app.localizedName ?? "Unknown")
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if let windowTitle, hasWindowTitleLabel {
                titleLabel(windowTitle, adaptsToAvailableWidth: true)
                    .font(appearance.windowTitleFontSize.font)
                    .foregroundStyle(.secondary)
            }
        }

        let appIconContent = Group {
            if let appIcon = windowInfo.app.icon {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: appIconSize, height: appIconSize)
            }
        }

        let controlsContent = controlsWithWindowStateIndicator(
            controlsAreLeading: isLeadingControls,
            nonAlignmentPadding: 0,
            spacing: controlsSpacing(hasAdjacentControl: hasVisibleAdjacentControl)
        ) {
            if canRenderTrafficLightButtons {
                TrafficLightButtons(
                    displayMode: appearance.trafficLightVisibility,
                    hoveringOverParentWindow: selected || isHoveringOverWindowSwitcherPreview,
                    onWindowAction: handleWindowAction,
                    pillStyling: !appearance.disableDockStyleTrafficLights,
                    mockPreviewActive: mockPreviewActive,
                    enabledButtons: effectiveTrafficLightButtons,
                    useMonochrome: appearance.useMonochromeTrafficLights,
                    backgroundAppearance: backgroundAppearance
                )
                .frame(width: showTrafficLights ? nil : 0)
                .clipped()
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
            }
        }
        .fixedSize()

        let controlsGap: CGFloat = (canRenderTrafficLightButtons && showTrafficLights) ? 0 : 8

        let titleContent = HStack(spacing: 4) {
            appIconContent
            titleAndSubtitleContent
        }
        .layoutPriority(1)

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

    private func dockPreviewContent(_ selected: Bool, isLeadingControls: Bool, showTitleContent: Bool = true, showControlsContent: Bool = true) -> some View {
        // Determine what title to show: window name first, then app name as fallback
        let titleToShow: String? = if let windowTitle = windowInfo.windowName, !windowTitle.isEmpty {
            windowTitle
        } else {
            windowInfo.app.localizedName
        }

        let hasTitle = appearance.showWindowTitle &&
            titleToShow != nil &&
            (appearance.windowTitleVisibility == .alwaysVisible || selected)

        let hasTrafficLights = canRenderTrafficLightButtons
        let showTrafficLights = shouldShowTrafficLightButtons(
            parentHovered: selected || isHoveringOverDockPeekPreview
        )
        let hasVisibleAdjacentControl = (hasTrafficLights && showTrafficLights) ||
            (!hasTrafficLights && visibleWindowStateLabel != nil && appearance.trafficLightVisibility != .never)
        let titleContent = Group {
            if hasTitle, let title = titleToShow {
                titleLabel(title, adaptsToAvailableWidth: true)
                    .font(appearance.windowTitleFontSize.font)
                    .padding(4)
                    .if(!appearance.disableDockStyleTitles) { view in
                        view.materialPill(backgroundAppearance: backgroundAppearance)
                    }
                    .frame(minWidth: 0)
                    .clipped()
            }
        }

        let controlsContent = controlsWithWindowStateIndicator(
            controlsAreLeading: isLeadingControls,
            nonAlignmentPadding: 0,
            spacing: controlsSpacing(hasAdjacentControl: hasVisibleAdjacentControl)
        ) {
            if hasTrafficLights {
                TrafficLightButtons(
                    displayMode: appearance.trafficLightVisibility,
                    hoveringOverParentWindow: selected || isHoveringOverDockPeekPreview,
                    onWindowAction: handleWindowAction,
                    pillStyling: !appearance.disableDockStyleTrafficLights,
                    mockPreviewActive: mockPreviewActive,
                    enabledButtons: effectiveTrafficLightButtons,
                    useMonochrome: appearance.useMonochromeTrafficLights,
                    buttonScale: appearance.trafficLightButtonScale,
                    backgroundAppearance: backgroundAppearance
                )
                .frame(width: showTrafficLights ? nil : 0)
                .clipped()
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
            }
        }
        .fixedSize()

        if hasTitle || hasTrafficLights || hasWindowStateIndicator {
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
                                windowSwitcherContent(finalIsSelected, isLeadingControls: config.isLeadingControls, showTitleContent: config.showTitle, showControlsContent: config.showControls)
                            } else {
                                dockPreviewContent(finalIsSelected, isLeadingControls: config.isLeadingControls, showTitleContent: config.showTitle, showControlsContent: config.showControls)
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
                                windowSwitcherContent(finalIsSelected, isLeadingControls: config.isLeadingControls, showTitleContent: config.showTitle, showControlsContent: config.showControls)
                            } else {
                                dockPreviewContent(finalIsSelected, isLeadingControls: config.isLeadingControls, showTitleContent: config.showTitle, showControlsContent: config.showControls)
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
            .background {
                let cornerRadius = uniformCardRadius ? CardRadius.base + (CardRadius.innerPadding * appearance.globalPaddingMultiplier) : 8.0

                if !appearance.hidePreviewCardBackground {
                    BlurView(cornerRadius: cornerRadius, appearance: backgroundAppearance)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .borderedBackground(.primary.opacity(0.1), lineWidth: 1.75, cornerRadius: cornerRadius)
                        .padding(-CardRadius.innerPadding)
                        .overlay {
                            if finalIsSelected {
                                let highlightColor = appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor)
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .fill(highlightColor.opacity(appearance.selectionOpacity))
                                    .padding(-CardRadius.innerPadding)
                            }
                        }
                        .overlay {
                            if isActiveWindow {
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .strokeBorder(appearance.activeAppIndicatorColor, lineWidth: 2.5)
                                    .padding(-CardRadius.innerPadding)
                            }
                        }
                }

                // Selection border drawn outside the card-background branch so the
                // selected item stays visible when hidePreviewCardBackground is on.
                if appearance.hidePreviewCardBackground, finalIsSelected {
                    let highlightColor = appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(highlightColor, lineWidth: 2.5)
                        .padding(-CardRadius.innerPadding)
                }
            }
        }
        .overlay {
            if isDraggingOver {
                let dragRadius = uniformCardRadius ? CardRadius.base + (CardRadius.innerPadding * appearance.globalPaddingMultiplier) : CardRadius.fallback
                RoundedRectangle(cornerRadius: dragRadius)
                    .fill(Color(nsColor: .controlAccentColor).opacity(0.3))
                    .padding(-CardRadius.innerPadding)
                    .opacity(highlightOpacity)
            }

            if appearance.useEmbeddedElements {
                embeddedControlsOverlay(finalIsSelected)
            }
        }
        .onDrop(of: [UTType.item], isTargeted: $isDraggingOver) { providers in
            if !isDraggingOver { return false }
            handleWindowTap()
            return true
        }
        .onChange(of: isDraggingOver) { isOver in
            if isOver {
                if windowSwitcherActive {
                    onDragHoverIndexChange?(index)
                } else {
                    startDragTimer()
                }
            } else {
                cancelDragTimer()
            }
        }
        .environment(\.layoutDirection, .leftToRight)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if isDraggingOver { return }

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
                if !currentHoverState { setHoverState(true) }
                onHoverIndexChange?(index, location)
            case .ended:
                onHoverIndexChange?(nil, nil)
                if currentHoverState {
                    setHoverState(false)
                }
            }
        }
    }

    var body: some View {
        previewCoreContent
            .windowPreviewInteractions(
                windowInfo: windowInfo,
                windowSwitcherActive: windowSwitcherActive,
                dockPosition: dockPosition,
                handleWindowAction: handleWindowAction,
                onTap: onTap
            )
            .fixedSize()
            .opacity(skeletonMode ? 0 : 1)
            .allowsHitTesting(!skeletonMode && !mockPreviewActive)
    }

    private func handleWindowTap() {
        if windowInfo.isMinimized {
            handleWindowAction(.minimize)
        } else if isEffectivelyHidden {
            handleWindowAction(.hide)
        } else {
            windowInfo.bringToFront()
            if !appearance.keepPreviewOnHoverActivation {
                onTap?()
            }
        }
    }

    private func startDragTimer() {
        dragTimer?.invalidate()
        highlightOpacity = 1.0
        dragTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.08)) { highlightOpacity = 0.0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.easeInOut(duration: 0.08)) { highlightOpacity = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    withAnimation(.easeInOut(duration: 0.08)) { highlightOpacity = 0.0 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.easeInOut(duration: 0.08)) { highlightOpacity = 1.0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            cancelDragTimer()
                            handleWindowTap()
                        }
                    }
                }
            }
        }
    }

    private func cancelDragTimer() {
        dragTimer?.invalidate()
        dragTimer = nil
        isDraggingOver = false
        highlightOpacity = 0.0
    }
}
