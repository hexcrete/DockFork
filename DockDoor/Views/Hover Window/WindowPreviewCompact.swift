import Defaults
import SwiftUI

enum CompactPreviewCardLayout {
    static let spacing: CGFloat = 10
    static let verticalPadding: CGFloat = 8
    static var horizontalInset: CGFloat { CardRadius.innerPadding }
}

private struct CompactRowContentClip: Shape {
    let trailingOverflow: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width + trailingOverflow,
            height: rect.height
        ))
    }
}

struct WindowPreviewCompact: View, Equatable {
    let windowInfo: WindowInfo
    let index: Int
    let dockPosition: DockPosition
    let uniformCardRadius: Bool
    let handleWindowAction: (WindowAction) -> Void
    let isSelected: Bool
    let windowSwitcherActive: Bool
    let mockPreviewActive: Bool
    let onTap: (() -> Void)?
    let onHoverIndexChange: ((Int?, CGPoint?) -> Bool)?
    let onDragHoverIndexChange: ((Int?) -> Void)?
    let widthOverride: CGFloat?
    var appearance: PreviewAppearanceSettings
    let backgroundAppearance: BackgroundAppearance
    let focusedWindowID: CGWindowID?
    let currentSpaceNumbers: Set<Int>
    var spaceNumber: Int? = nil
    var isChecked = false
    var dragSelection: SwitcherSelectionState? = nil
    var previewBodyDrag: AnyGesture<DragGesture.Value>? = nil
    var selectionInteraction: PreviewSelectionInteraction? = nil

    @State private var isHovering = false
    @State private var isHoveringIcon = false

    private var isHighlighted: Bool {
        isSelected
    }

    static func == (l: Self, r: Self) -> Bool {
        l.index == r.index && l.isSelected == r.isSelected && l.isChecked == r.isChecked
            && l.dragSelection === r.dragSelection
            && l.selectionInteraction?.isDragOrigin == r.selectionInteraction?.isDragOrigin
            && l.windowSwitcherActive == r.windowSwitcherActive
            && l.uniformCardRadius == r.uniformCardRadius
            && l.widthOverride == r.widthOverride
            && l.appearance == r.appearance
            && l.windowInfo.viewSnapshot == r.windowInfo.viewSnapshot
            && l.backgroundAppearance == r.backgroundAppearance
            && l.focusedWindowID == r.focusedWindowID
            && l.currentSpaceNumbers == r.currentSpaceNumbers
            && l.spaceNumber == r.spaceNumber
    }

    private var rowWidth: CGFloat {
        widthOverride ?? appearance.compactModeWidth
    }

    private var effectiveTrafficLightButtons: Set<WindowAction> {
        resolvedTrafficLightButtons(
            for: windowInfo,
            configuredButtons: appearance.enabledTrafficLightButtons,
            showWindowlessQuitButton: appearance.showWindowlessAppQuitButton
        )
    }

    private var canRenderTrafficLightButtons: Bool {
        appearance.trafficLightVisibility != .never &&
            !effectiveTrafficLightButtons.isEmpty
    }

    /// Checks if this window is the currently active (focused) window on the system and adds a border if so.
    private var isActiveWindow: Bool {
        guard appearance.showActiveWindowBorder else { return false }
        guard windowInfo.app.isActive else { return false }
        return windowInfo.id == focusedWindowID
    }

    private var appName: String {
        windowInfo.app.localizedName ?? "Unknown"
    }

    private var windowTitle: String? {
        let title = windowInfo.windowName ?? ""
        if title.isEmpty || title == appName {
            return nil
        }
        return title
    }

    private var stateIndicator: String? {
        if windowInfo.isWindowlessApp {
            return String(localized: "No Open Windows", comment: "Label for running apps without any open windows in the window switcher")
        }
        guard appearance.windowStateIndicatorPlacement == .onWindowPreviews else { return nil }
        if windowInfo.isMinimized {
            return String(localized: "Minimized", comment: "Window state label")
        } else if windowInfo.isEffectivelyHiddenForUI {
            return String(localized: "Hidden", comment: "Window state label")
        } else if windowInfo.isFullscreen == true {
            return String(localized: "Full Screen", comment: "Window state label")
        }
        return nil
    }

    private var secondaryStateIndicator: String? {
        stateIndicator
    }

    private var windowStateSymbols: [String] {
        WindowStateSymbolResolver.symbols(
            for: windowInfo,
            isEffectivelyHidden: windowInfo.isEffectivelyHiddenForUI
        )
    }

    private var movesWindowStateToIndicator: Bool {
        appearance.windowStateIndicatorPlacement == .nextToTrafficLightButtons &&
            !windowStateSymbols.isEmpty
    }

    private var indicatorStateSymbols: [String] {
        movesWindowStateToIndicator ? windowStateSymbols : []
    }

    private var hasWindowStateIndicator: Bool {
        (appearance.showSpaceNumberIndicator && windowInfo.spaceNumber != nil) || !indicatorStateSymbols.isEmpty
    }

    @ViewBuilder
    private var windowStateIndicator: some View {
        let spaceNumber = appearance.showSpaceNumberIndicator ? windowInfo.spaceNumber : nil
        if spaceNumber != nil || !indicatorStateSymbols.isEmpty {
            SpaceMoveIndicatorControl(
                window: windowInfo,
                spaceNumber: spaceNumber,
                isEnabled: appearance.enableSpaceIndicatorWindowMoving && !mockPreviewActive,
                dismissPreviews: onTap
            ) {
                WindowStateIndicator(
                    number: spaceNumber,
                    stateSymbols: indicatorStateSymbols,
                    disableDockStyling: appearance.disableDockStyleWindowStateIndicator,
                    fontSize: appearance.windowStateIndicatorFontSize,
                    backgroundAppearance: backgroundAppearance,
                    highlightsCurrentSpace: appearance.highlightCurrentSpaceNumberIndicator &&
                        spaceNumber.map(currentSpaceNumbers.contains) == true,
                    highlightColor: appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor),
                    highlightOpacity: appearance.selectionOpacity,
                    activeBorderColor: appearance.activeAppIndicatorColor
                )
            }
        }
    }

    @ViewBuilder
    private func trafficLightButtons(_ stage: PreviewToolbarStage) -> some View {
        if !appearance.compactModeHideTrafficLights,
           canRenderTrafficLightButtons
        {
            TrafficLightButtons(
                previewAppearance: appearance,
                hoveringOverParentWindow: isSelected || isHovering,
                onWindowAction: handleWindowAction,
                mockPreviewActive: mockPreviewActive,
                enabledButtons: stage.visibleActions(in: effectiveTrafficLightButtons),
                backgroundAppearance: backgroundAppearance, windowInfo: windowInfo
            )
        }
    }

    var body: some View {
        let appIcon = windowInfo.app.icon
        let showTrafficLightButtons = appearance.trafficLightVisibility.isVisible(
            hoveringOverParentWindow: isSelected || isHovering
        )
        let hasVisibleTrafficLightButtons = !appearance.compactModeHideTrafficLights &&
            canRenderTrafficLightButtons && showTrafficLightButtons
        let windowStateIndicatorIsOutermost = hasWindowStateIndicator &&
            (!hasVisibleTrafficLightButtons || appearance.swapTrafficLightsAndWindowStateIndicator)
        let controlsTrailingInset = appearance.compactControlAlignmentEdgeInset(
            hasWindowStateIndicator: hasWindowStateIndicator,
            hasTrafficLightButtons: hasVisibleTrafficLightButtons,
            windowStateIndicatorIsOutermost: windowStateIndicatorIsOutermost
        )
        PreviewAdaptiveToolbar(
            allowsTitleOmission: appearance.showAppHeader,
            partialActionCounts: appearance.partialTrafficLightCounts(for: effectiveTrafficLightButtons, isVisible: hasVisibleTrafficLightButtons),
            controlsVisible: hasVisibleTrafficLightButtons,
            animationDuration: appearance.trafficLightTransitionDuration, animationsEnabled: appearance.showAnimations
        ) { stage, isMeasuring in compactRow(stage, appIcon: appIcon, isMeasuring: isMeasuring) }
            .padding(.vertical, CompactPreviewCardLayout.verticalPadding)
            .frame(width: rowWidth, height: appearance.compactRowHeight(hasWindowStateIndicator: hasWindowStateIndicator), alignment: .leading)
            .clipShape(CompactRowContentClip(trailingOverflow: max(0, -controlsTrailingInset)))
            // Keep body hits behind controls but in front of the decorative chrome.
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(previewBodyDrag)
                    .padding(.horizontal, -CardRadius.innerPadding)
            }
            .opacity(isHighlighted || isChecked ? 1.0 : appearance.unselectedContentOpacity)
            .previewCardChrome(
                uniformCardRadius: uniformCardRadius,
                paddingMultiplier: appearance.globalPaddingMultiplier,
                expansionEdges: .horizontal,
                hideBackground: appearance.hidePreviewCardBackground,
                isHighlighted: isHighlighted,
                isActiveWindow: isActiveWindow,
                highlightColor: appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor),
                highlightOpacity: appearance.selectionOpacity,
                activeBorderColor: appearance.activeAppIndicatorColor,
                backgroundAppearance: backgroundAppearance
            )
            .externalDragSpringLoading(
                windowInfo: windowInfo,
                index: index,
                uniformCardRadius: uniformCardRadius,
                appearance: appearance,
                windowSwitcherActive: windowSwitcherActive,
                handleWindowAction: handleWindowAction,
                onTap: onTap,
                onDragHoverIndexChange: onDragHoverIndexChange,
                dragSelection: dragSelection,
                expansionEdges: .horizontal
            )
            .padding(.horizontal, CompactPreviewCardLayout.horizontalInset)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                let setHoverState: (Bool) -> Void = { newState in
                    if appearance.showAnimations {
                        withAnimation(.snappy(duration: 0.175)) { isHovering = newState }
                    } else {
                        isHovering = newState
                    }
                }

                switch phase {
                case let .active(location):
                    let shouldShowHover = onHoverIndexChange?(index, location) ?? true
                    if isHovering != shouldShowHover { setHoverState(shouldShowHover) }
                case .ended:
                    _ = onHoverIndexChange?(nil, nil)
                    if isHovering { setHoverState(false) }
                }
            }
            .windowPreviewInteractions(
                windowInfo: windowInfo,
                windowSwitcherActive: windowSwitcherActive,
                dockPosition: dockPosition,
                useCompactMode: true,
                pointerHoverActive: isHovering,
                handleWindowAction: handleWindowAction,
                onTap: onTap
            )
            .allowsHitTesting(!mockPreviewActive)
    }

    @ViewBuilder
    private func compactRow(_ stage: PreviewToolbarStage, appIcon: NSImage?, isMeasuring: Bool) -> some View {
        let showTrafficLightButtons = appearance.trafficLightVisibility.isVisible(
            hoveringOverParentWindow: isSelected || isHovering
        )
        let hasVisibleTrafficLightButtons = !appearance.compactModeHideTrafficLights &&
            canRenderTrafficLightButtons && showTrafficLightButtons
        let windowStateIndicatorIsOutermost = hasWindowStateIndicator &&
            (!hasVisibleTrafficLightButtons || appearance.swapTrafficLightsAndWindowStateIndicator)
        let controlsTrailingInset = appearance.compactControlAlignmentEdgeInset(
            hasWindowStateIndicator: hasWindowStateIndicator,
            hasTrafficLightButtons: hasVisibleTrafficLightButtons,
            windowStateIndicatorIsOutermost: windowStateIndicatorIsOutermost
        )
        let controlElementSpacing = appearance.controlElementSpacing
        let hasTitle = appearance.showAppHeader && stage.showsTitles
        let showsStateLabel = !stage.showsTitles && !stage.overflowsIndicators && secondaryStateIndicator != nil
        let hasControlGroup = stage != .combined && (hasWindowStateIndicator || hasVisibleTrafficLightButtons ||
            (stage.overflowsIndicators && (spaceNumber != nil || secondaryStateIndicator != nil)))
        let hasControls = hasControlGroup || (spaceNumber != nil && !stage.overflowsIndicators)
        let controlsSpacing: CGFloat = if hasWindowStateIndicator, hasVisibleTrafficLightButtons {
            controlElementSpacing
        } else {
            0
        }

        HStack(spacing: CompactPreviewCardLayout.spacing) {
            PreviewAppIcon(
                icon: appIcon,
                bundleURL: windowInfo.app.bundleURL,
                size: appearance.compactModeItemSize.iconSize,
                showBadge: !isMeasuring && windowSwitcherActive && appearance.showCompactAppIconBadges,
                badgeScale: appearance.appIconBadgeScale,
                mockPreviewActive: mockPreviewActive
            )
            .allowsHitTesting(false)
            .overlay {
                if stage == .combined {
                    overflowButton(stage, circular: true)
                } else if appearance.enableMultiWindowSelection, !mockPreviewActive, !windowInfo.isWindowlessApp || appearance.enableWindowlessAppSelection,
                          appearance.showUncheckedSelectionCheckboxes || isChecked || selectionInteraction?.isDragOrigin == true
                {
                    PreviewSelectionCheckbox(
                        isChecked: isChecked,
                        isVisible: selectionInteraction?.isDragOrigin == true || appearance.selectionCheckboxVisibility.showsCheckbox(
                            checked: isChecked,
                            previewHovered: isSelected || isHovering,
                            titleHovered: isHoveringIcon,
                            titleAvailable: appearance.showAppHeader,
                            compact: true
                        ),
                        color: appearance.activeAppIndicatorColor,
                        diameter: PreviewSelectionCheckbox.iconDiameter(for: appearance.compactModeItemSize.iconSize),
                        backgroundAppearance: backgroundAppearance,
                        animationsEnabled: appearance.showAnimations,
                        interaction: isMeasuring ? nil : selectionInteraction,
                        toggle: { handleWindowAction(.toggleWindowSelection) }
                    )
                }
            }

            .if(!isMeasuring && appearance.enableMultiWindowSelection && appearance.showUncheckedSelectionCheckboxes &&
                appearance.selectionCheckboxVisibility == .titleHover && !mockPreviewActive && (!windowInfo.isWindowlessApp || appearance.enableWindowlessAppSelection))
            { view in
                view.onContinuousHover { phase in
                    let hovering: Bool = switch phase {
                    case .active:
                        SharedPreviewWindowCoordinator.activeInstance?.windowSwitcherCoordinator.registerMouseMovementSinceOpen() == true
                    case .ended:
                        false
                    }
                    if isHoveringIcon != hovering { isHoveringIcon = hovering }
                }
                .onDisappear { isHoveringIcon = false }
            }

            HStack(spacing: 0) {
                if hasTitle {
                    PreviewToolbarTitle(font: appearance.compactModeItemSize.primaryFont) {
                        VStack(alignment: .leading, spacing: 2) {
                            switch appearance.compactModeTitleFormat {
                            case .appNameAndTitle:
                                titleText(appName, isPrimary: true, isMeasuring: isMeasuring)
                                if windowInfo.isWindowlessApp, let state = secondaryStateIndicator {
                                    stateText(state)
                                } else if let title = windowTitle {
                                    HStack(spacing: 0) {
                                        if let state = secondaryStateIndicator {
                                            stateText(state)
                                            Text("  \u{2022}  ")
                                                .font(appearance.compactModeItemSize.secondaryFont)
                                                .foregroundStyle(.secondary)
                                        }
                                        titleText(title, isPrimary: false, isMeasuring: isMeasuring)
                                    }
                                } else if let state = secondaryStateIndicator {
                                    stateText(state)
                                }

                            case .titleOnly:
                                titleText(windowInfo.isWindowlessApp ? appName : windowTitle ?? appName, isPrimary: true, isMeasuring: isMeasuring)
                                if let state = secondaryStateIndicator {
                                    stateText(state)
                                }

                            case .appNameOnly:
                                titleText(appName, isPrimary: true, isMeasuring: isMeasuring)
                                if let state = secondaryStateIndicator {
                                    stateText(state)
                                }
                            }
                        }
                    }
                    .allowsHitTesting(false)
                }

                if showsStateLabel, let state = secondaryStateIndicator {
                    stateText(state).fixedSize()
                        .allowsHitTesting(false)
                }

                Spacer(minLength: (hasTitle || showsStateLabel) && hasControls ? controlElementSpacing : 0)

                HStack(spacing: hasControlGroup ? controlElementSpacing : 0) {
                    if let spaceNumber, !stage.overflowsIndicators {
                        SpaceNumberBadge(
                            number: spaceNumber,
                            font: appearance.compactModeItemSize.secondaryFont,
                            backgroundAppearance: backgroundAppearance,
                            highlightsCurrentSpace: appearance.highlightCurrentSpaceNumberIndicator && currentSpaceNumbers.contains(spaceNumber),
                            highlightColor: appearance.hoverHighlightColor ?? Color(nsColor: .controlAccentColor),
                            highlightOpacity: appearance.selectionOpacity
                        )
                    }

                    if stage != .combined {
                        HStack(spacing: controlsSpacing) {
                            if appearance.swapTrafficLightsAndWindowStateIndicator {
                                adaptiveTrafficLights(stage, isVisible: showTrafficLightButtons)
                                if !stage.overflowsIndicators { windowStateIndicator }
                            } else {
                                if !stage.overflowsIndicators { windowStateIndicator }
                                adaptiveTrafficLights(stage, isVisible: showTrafficLightButtons)
                            }
                        }
                        .padding(.trailing, controlsTrailingInset)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func adaptiveTrafficLights(_ stage: PreviewToolbarStage, isVisible: Bool) -> some View {
        if !appearance.compactModeHideTrafficLights, canRenderTrafficLightButtons {
            PreviewControlReplacement(
                controlsVisible: stage.showsTrafficLights && isVisible,
                replacementVisible: stage.overflowsActions && (isVisible || (stage.overflowsIndicators && (hasWindowStateIndicator || spaceNumber != nil || secondaryStateIndicator != nil))),
                spacing: appearance.controlElementSpacing
            ) {
                trafficLightButtons(stage)
            } replacement: {
                overflowButton(stage)
            }
        } else if stage.overflowsIndicators, hasWindowStateIndicator || spaceNumber != nil || secondaryStateIndicator != nil {
            overflowButton(stage)
        }
    }

    private func overflowButton(_ stage: PreviewToolbarStage, circular: Bool = false) -> some View {
        let lightsVisible = !appearance.compactModeHideTrafficLights && canRenderTrafficLightButtons &&
            appearance.trafficLightVisibility.isVisible(hoveringOverParentWindow: isSelected || isHovering)
        return PreviewOverflowButton(window: windowInfo, appearance: appearance, backgroundAppearance: backgroundAppearance,
                                     overflow: PreviewControlOverflow(actions: lightsVisible ? stage.overflowActions(in: effectiveTrafficLightButtons) : [],
                                                                      includesIndicator: stage.overflowsIndicators && (hasWindowStateIndicator || spaceNumber != nil || secondaryStateIndicator != nil),
                                                                      includesSelection: circular && appearance.enableMultiWindowSelection,
                                                                      spaceNumber: appearance.showSpaceNumberIndicator ? windowInfo.spaceNumber : spaceNumber,
                                                                      allowsSpaceMoving: appearance.enableSpaceIndicatorWindowMoving && appearance.showSpaceNumberIndicator),
                                     circularDiameter: circular ? PreviewSelectionCheckbox.iconDiameter(for: appearance.compactModeItemSize.iconSize) : nil,
                                     isChecked: isChecked, mockPreviewActive: mockPreviewActive,
                                     handleWindowAction: handleWindowAction, dismissPreviews: onTap)
    }

    @ViewBuilder
    private func titleText(_ text: String, isPrimary: Bool, isMeasuring: Bool) -> some View {
        let font = isPrimary ? appearance.compactModeItemSize.primaryFont : appearance.compactModeItemSize.secondaryFont
        if isMeasuring {
            Text(verbatim: "\u{2026}").font(font)
        } else {
            switch appearance.titleOverflowStyle {
            case .marquee:
                MarqueeText(text: text, startDelay: 1, adaptsToAvailableWidth: true)
                    .font(font)
                    .foregroundStyle(isPrimary ? .primary : .secondary)
            case .truncateTail:
                Text(text).font(font).foregroundStyle(isPrimary ? .primary : .secondary)
                    .lineLimit(1).truncationMode(.tail)
            case .truncateMiddle:
                Text(text).font(font).foregroundStyle(isPrimary ? .primary : .secondary)
                    .lineLimit(1).truncationMode(.middle)
            case .truncateHead:
                Text(text).font(font).foregroundStyle(isPrimary ? .primary : .secondary)
                    .lineLimit(1).truncationMode(.head)
            }
        }
    }

    @ViewBuilder
    private func stateText(_ text: String) -> some View {
        Text(text)
            .font(appearance.compactModeItemSize.secondaryFont)
            .foregroundStyle(.secondary)
            .italic()
    }
}
