import Defaults
import SwiftUI

struct KeybindsSettingsView: View {
    @Default(.enableWindowSwitcher) var enableWindowSwitcher
    @Default(.enableCmdTabEnhancements) var enableCmdTabEnhancements
    @Default(.enableDockPreviews) private var enableDockPreviews

    var body: some View {
        SettingsFormView {
            if enableWindowSwitcher {
                WindowSwitcherKeybindSection()
            } else {
                Section {
                    SettingsNote(icon: "info.circle", text: "Turn on the Window Switcher to change its shortcuts.")
                }
            }

            if enableWindowSwitcher || enableCmdTabEnhancements || enableDockPreviews {
                CmdKeyShortcutsSection()
            }
            PreviewPostActionBehaviorSection()
            SpacesSettingsSection()
            WindowSelectionSettingsSection()
            TilingSettingsSection()
        }
    }
}

private struct WindowSelectionSettingsSection: View {
    @Default(.enableMultiWindowSelection) private var enabled
    @Default(.enableWindowlessAppSelection) private var enableWindowlessAppSelection
    @Default(.showUncheckedSelectionCheckboxes) private var showUnchecked
    @Default(.selectionCheckboxVisibility) private var visibility
    @Default(.showWindowSelectionSummary) private var showSummary
    @Default(.keepWindowSwitcherOpenWhenSelected) private var keepOpenWhenSelected

    var body: some View {
        SettingsSection("Window Selection") {
            Toggle("Enable multi-window selection", isOn: $enabled)
                .settingsSearchTarget("gestures.enableMultiWindowSelection")
                .settingsAnnotation("Select a range by Shift-clicking another checkbox, dragging from a checkbox across previews, or holding the Toggle Window Selection shortcut while using arrow keys.")
            if enabled {
                Group {
                    Toggle("Enable selection of windowless apps in Window Switcher", isOn: $enableWindowlessAppSelection)
                        .settingsSearchTarget("gestures.enableWindowlessAppSelection")
                        .settingsAnnotation("Only \"Quit\", \"Force Quit\" and \"Open New Window\" apply to windowless apps.")
                    Toggle("Keep Window Switcher open when windows are selected", isOn: $keepOpenWhenSelected)
                        .settingsSearchTarget("gestures.keepWindowSwitcherOpenWhenSelected")
                        .settingsAnnotation("Keep selected windows available after releasing the initializer modifier or finishing a swipe. When disabled, selecting windows does not change the session's normal dismissal behavior. Dock and Cmd+Tab previews keep their normal dismissal behavior.")
                    Toggle("Show selection summary", isOn: $showSummary)
                        .settingsSearchTarget("gestures.showWindowSelectionSummary")
                        .settingsAnnotation("Show the selection count with Select All, Clear Selection, and Tile Windows buttons.")
                    Toggle("Show unchecked selection checkboxes", isOn: $showUnchecked)
                        .settingsSearchTarget("gestures.showUncheckedSelectionCheckboxes")
                    if showUnchecked {
                        Group {
                            Picker("Checkbox visibility:", selection: $visibility) {
                                ForEach(SelectionCheckboxVisibility.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                            }

                            .settingsSearchTarget("gestures.selectionCheckboxVisibility")
                            .settingsAnnotation("Checkboxes remain visible while checked.")
                        }
                    }
                }
            }
        }
        .onChange(of: enabled) { value in
            if !value { SharedPreviewWindowCoordinator.activeInstance?.windowSwitcherCoordinator.clearCheckedWindows(resetOwnership: true) }
        }
        .onChange(of: enableWindowlessAppSelection) { _ in
            SharedPreviewWindowCoordinator.activeInstance?.windowSwitcherCoordinator.reconcileCheckedWindows()
        }
    }
}

private struct TilingSettingsSection: View {
    @Default(.fillActionsAutoTileSelection) private var fillActionsAutoTileSelection
    @Default(.linkTiledWindowsWhenResizing) private var linkTiledWindowsWhenResizing
    @Default(.maximumTilingRows) private var maximumTilingRows
    @Default(.maximumTilingColumns) private var maximumTilingColumns
    @Default(.tileOnlyWhatFits) private var tileOnlyWhatFits

    var body: some View {
        SettingsSection("Tiling") {
            Toggle("\"Fill\" actions on multiple selected windows trigger \"Auto Tile\"", isOn: $fillActionsAutoTileSelection)
                .settingsSearchTarget("gestures.fillActionsAutoTileSelection")
                .settingsAnnotation("Use actions such as \"Fill Left Half\" to arrange selected windows together, starting from that direction. When disabled, each window fills the requested area on its own Space.")
            Toggle("Link tiled windows when resizing", isOn: $linkTiledWindowsWhenResizing)
                .settingsSearchTarget("gestures.linkTiledWindowsWhenResizing")
                .settingsAnnotation("Resize shared edges to resize neighboring windows tiled together. Drag a tiled window's title bar to restore its earlier size. Moving it to another Desktop or display detaches it.")
                .onChange(of: linkTiledWindowsWhenResizing) { _ in WindowSnapRegistry.existing?.removeDisabledRecords() }
            Picker("Auto Tile maximum rows:", selection: $maximumTilingRows) {
                ForEach(1 ... 6, id: \.self) { Text("\($0)").tag($0) }
            }

            .settingsSearchTarget("gestures.maximumTilingRows")
            Picker("Auto Tile maximum columns:", selection: $maximumTilingColumns) {
                ForEach(1 ... 6, id: \.self) { Text("\($0)").tag($0) }
            }

            .settingsSearchTarget("gestures.maximumTilingColumns")
            Toggle("Auto Tile only what fits", isOn: $tileOnlyWhatFits)
                .settingsSearchTarget("gestures.tileOnlyWhatFits")
                .settingsAnnotation("Arrange only the first windows that fit within the row and column limits, leaving extra windows unchanged. When disabled, extra windows stack behind earlier windows in the same cells.")
            if maximumTilingRows > 3 || maximumTilingColumns > 3 {
                SettingsCallout(tone: .warning, message: Text("More than 3 rows or columns may not look good on some displays."))
            }
        }
    }
}

private struct SpacesSettingsSection: View {
    @Default(.cmdShortcuts) private var previewShortcuts
    @Default(.alternateSwitcherShortcuts) private var alternateShortcuts
    @Default(.switcherBackwardKeyCode) private var backwardKey
    @Default(.windowSwitcherSelectionKeyCode) private var selectionKey
    @Default(.spacesBarCycleOpensSwitcher) private var spacesBarCycleOpensSwitcher
    @Default(.spacesBarCycleKey) private var spacesBarCycleKey
    @Default(.spacesBarBackwardCycleKey) private var spacesBarBackwardCycleKey
    @Default(.enableSpaceIndicatorWindowMoving) private var enableSpaceIndicatorWindowMoving
    @Default(.spaceMenuDisplayMode) private var spaceMenuDisplayMode
    @Default(.switchToDestinationSpaceAfterMoving) private var switchToDestinationSpaceAfterMoving
    @Default(.showUnavailableSpacesInMenu) private var showUnavailableSpacesInMenu
    @Default(.showCurrentSpaceBadgeInMenu) private var showCurrentSpaceBadgeInMenu
    @Default(.enableSpacesShortcuts) private var enableSpacesShortcuts
    @Default(.UserKeybind) private var windowSwitcherKeybind
    @Default(.ignoreMainModifierSideForDependentShortcuts) private var ignoreMainModifierSideForDependentShortcuts

    private var spacesShortcutKeybind: UserKeyBind {
        WindowSwitcherShortcutResolver.dependentShortcutKeybind(
            windowSwitcherKeybind,
            ignoreModifierSide: ignoreMainModifierSideForDependentShortcuts
        )
    }

    private func spaceCycleKeyRow(_ title: LocalizedStringKey, key: Binding<UInt16>, backward: Bool) -> some View {
        let _ = (previewShortcuts, alternateShortcuts, backwardKey, selectionKey, enableSpacesShortcuts)
        let conflict = WindowSwitcherShortcutResolver.spaceCycleConflict(backward: backward, previewKeybind: spacesShortcutKeybind, mainKeybind: windowSwitcherKeybind)
        return LabeledContent(title) {
            SettingsKeyCaptureControls(keyCode: key,
                                       defaultKeyCode: backward ? Defaults.Keys.spacesBarBackwardCycleKey.defaultValue : Defaults.Keys.spacesBarCycleKey.defaultValue,
                                       modifierLabel: modifierConverter.toSymbol(spacesShortcutKeybind), conflict: conflict,
                                       emptyLabel: String(localized: "Unassigned"), forceEmptyLabel: key.wrappedValue == .max,
                                       treatKeyCodeZeroAsEmpty: false)
        }
    }

    var body: some View {
        SettingsSection("Spaces") {
            spaceCycleKeyRow("Space cycle key", key: $spacesBarCycleKey, backward: false)
                .settingsSearchTarget("gestures.spacesBarCycleKey")
            spaceCycleKeyRow("Backward Space cycle key", key: $spacesBarBackwardCycleKey, backward: true)
                .settingsSearchTarget("gestures.spacesBarBackwardCycleKey")
            Toggle("Allow Space-cycle shortcuts to open the switcher", isOn: $spacesBarCycleOpensSwitcher)
                .settingsSearchTarget("gestures.spacesBarCycleOpensSwitcher")
            Toggle("Use Space Number Indicator to move windows to Spaces", isOn: $enableSpaceIndicatorWindowMoving)
                .settingsSearchTarget("gestures.enableSpaceIndicatorWindowMoving")
                .settingsAnnotation("Click the Space Number Indicator to list available Spaces. Choosing a Space will move the selected window there.")
            if enableSpaceIndicatorWindowMoving {
                Group {
                    Picker("Display available Spaces as:", selection: $spaceMenuDisplayMode) {
                        ForEach(SpaceMenuDisplayMode.allCases, id: \.self) { Text($0.localizedName).tag($0) }
                    }

                    .settingsSearchTarget("gestures.spaceMenuDisplayMode")
                    Toggle("Show “Current” badge in the Spaces dropdown", isOn: $showCurrentSpaceBadgeInMenu)
                        .settingsSearchTarget("gestures.showCurrentSpaceBadgeInMenu")
                        .settingsAnnotation("Labels the currently active Space with a “Current” badge.")
                    Toggle("Switch to the destination Space after moving the window", isOn: $switchToDestinationSpaceAfterMoving)
                        .settingsSearchTarget("gestures.switchToDestinationSpaceAfterMoving")
                    Toggle("Show unavailable Spaces in the list", isOn: $showUnavailableSpacesInMenu)
                        .settingsSearchTarget("gestures.showUnavailableSpacesInMenu")
                        .settingsAnnotation("Show Spaces the window cannot be moved to in the Spaces dropdown menu.")
                }
            }
            Toggle("Enable Spaces Shortcuts", isOn: $enableSpacesShortcuts)
                .settingsSearchTarget("gestures.enableSpacesShortcuts")
                .settingsAnnotation("When a window preview is focused, press the Window Switcher modifier plus a number to move the window to that numbered Desktop. When Window Switcher is open without a focused preview, the same shortcut switches to that numbered Space.")
                .settingsAnnotation("Current modifier: \(modifierConverter.toSymbol(spacesShortcutKeybind))")
        }
    }
}
