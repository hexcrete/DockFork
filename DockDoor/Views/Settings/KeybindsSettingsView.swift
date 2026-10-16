import Defaults
import SwiftUI

struct KeybindsSettingsView: View {
    var body: some View {
        BaseSettingsView {
            VStack(alignment: .leading, spacing: 16) {
                MouseActionsSection()
                CmdKeyShortcutsSection()
                PreviewPostActionBehaviorSection()
                SpacesSettingsSection()
                WindowSelectionSettingsSection()
                WindowSwitcherKeybindSection()
            }
        }
    }
}

private struct WindowSelectionSettingsSection: View {
    @Default(.enableMultiWindowSelection) private var enabled
    @Default(.showUncheckedSelectionCheckboxes) private var showUnchecked
    @Default(.selectionCheckboxVisibility) private var visibility
    @Default(.showWindowSelectionSummary) private var showSummary
    @Default(.keepWindowSwitcherOpenWhenSelected) private var keepOpenWhenSelected
    @Default(.linkTiledWindowsWhenResizing) private var linkTiledWindowsWhenResizing
    @Default(.maximumTilingRows) private var maximumTilingRows
    @Default(.maximumTilingColumns) private var maximumTilingColumns

    var body: some View {
        SettingsGroup(header: "Window Selection & Tiling") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enable multi-window selection", isOn: $enabled)
                    .settingsSearchTarget("gestures.enableMultiWindowSelection")
                Text("Check windows using selection controls or the Toggle Window Selection action. Selecting windows follows the session's normal dismissal behavior unless Keep Window Switcher open when windows are selected is enabled. Dock previews retain normal hover dismissal. Escape or clicking outside closes previews and clears selection. Mixed selections minimize or hide when any applicable target is unminimized or visible; otherwise they restore or unhide. Fullscreen exits all selected fullscreen windows. If none are fullscreen, only the clicked or highlighted window enters fullscreen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
                Toggle(String(localized: "Link tiled windows when resizing"), isOn: $linkTiledWindowsWhenResizing)
                    .settingsSearchTarget("gestures.linkTiledWindowsWhenResizing")
                Text(String(localized: "Resize shared edges to resize neighboring windows tiled together. Drag a tiled window's title bar to restore its earlier size. Moving it to another Desktop or display detaches it. This works without Window Gestures or multi-window selection."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
                if enabled {
                    Toggle("Keep Window Switcher open when windows are selected", isOn: $keepOpenWhenSelected)
                        .settingsSearchTarget("gestures.keepWindowSwitcherOpenWhenSelected")
                    Text("Keep selected windows available after releasing the initializer modifier or finishing a swipe. When disabled, selecting windows does not change the session's normal dismissal behavior. Dock and Cmd+Tab previews keep their normal dismissal behavior.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                    Toggle("Show selection summary", isOn: $showSummary)
                        .settingsSearchTarget("gestures.showWindowSelectionSummary")
                    Text("Show the selection count with Select All, Clear Selection and Tile Windows buttons. Tile Windows automatically arranges selected windows. Window Switcher also shows selected-app icons. Select All adds currently displayed, filtered windows to the selection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                    Toggle("Show unchecked selection checkboxes", isOn: $showUnchecked)
                        .settingsSearchTarget("gestures.showUncheckedSelectionCheckboxes")
                    if showUnchecked {
                        Picker("Checkbox visibility:", selection: $visibility) {
                            ForEach(SelectionCheckboxVisibility.allCases, id: \.self) { option in
                                Text(option.localizedName).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .settingsSearchTarget("gestures.selectionCheckboxVisibility")
                    }
                    Text("Checked controls stay visible. Preview hover includes keyboard highlighting. In Compact Mode, On title hover uses icon hover; other options use preview hover. Hidden titles outside Compact Mode fall back to preview hover.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                    Picker("Maximum tiling rows:", selection: $maximumTilingRows) {
                        ForEach(1 ... 6, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .settingsSearchTarget("gestures.maximumTilingRows")
                    Picker("Maximum tiling columns:", selection: $maximumTilingColumns) {
                        ForEach(1 ... 6, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .settingsSearchTarget("gestures.maximumTilingColumns")
                    Text("The first checked window leads. Auto Tile Selected Windows and Half/Quarter actions arrange checked groups on the current Desktop. Set both limits to 1 to move windows without resizing. Overflowing groups repeat the same layout.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                    if maximumTilingRows > 3 || maximumTilingColumns > 3 {
                        SettingsNote(icon: "exclamationmark.triangle", text: "More than 3 rows or columns may not look good on some displays. Apps may enforce minimum window sizes.")
                    }
                }
            }
        }
        .onChange(of: linkTiledWindowsWhenResizing) { _ in
            WindowSnapRegistry.existing?.removeDisabledRecords()
        }
        .onChange(of: enabled) { newValue in
            if !newValue {
                SharedPreviewWindowCoordinator.activeInstance?.windowSwitcherCoordinator.clearCheckedWindows(resetOwnership: true)
            }
        }
    }
}

private struct SpacesSettingsSection: View {
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

    var body: some View {
        SettingsGroup(header: "Spaces") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Use Space Number Indicator to move windows to Spaces", isOn: $enableSpaceIndicatorWindowMoving)
                    .settingsSearchTarget("gestures.enableSpaceIndicatorWindowMoving")

                Text("Click the Space Number Indicator to list available Spaces. Choosing a Space will move the selected window there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)

                if enableSpaceIndicatorWindowMoving {
                    Divider()

                    Picker("Display available Spaces as:", selection: $spaceMenuDisplayMode) {
                        ForEach(SpaceMenuDisplayMode.allCases, id: \.self) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .settingsSearchTarget("gestures.spaceMenuDisplayMode")

                    Toggle(
                        String(localized: "Show “Current” badge in the Spaces dropdown", comment: "Setting to label the active Space in the window-moving menu"),
                        isOn: $showCurrentSpaceBadgeInMenu
                    )
                    .settingsSearchTarget("gestures.showCurrentSpaceBadgeInMenu")

                    Text(String(localized: "Labels the currently active Space with a “Current” badge.", comment: "Explanation for the current Space badge setting"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)

                    Toggle("Switch to the destination Space after moving the window", isOn: $switchToDestinationSpaceAfterMoving)
                        .settingsSearchTarget("gestures.switchToDestinationSpaceAfterMoving")

                    Toggle("Show unavailable Spaces in the list", isOn: $showUnavailableSpacesInMenu)
                        .settingsSearchTarget("gestures.showUnavailableSpacesInMenu")

                    Text("Show Spaces the window cannot be moved to in the Spaces dropdown menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Spaces Shortcuts")
                        .font(.headline)

                    Toggle("Enable Spaces Shortcuts", isOn: $enableSpacesShortcuts)
                        .settingsSearchTarget("gestures.enableSpacesShortcuts")

                    Text("When a window preview is focused, press the Window Switcher modifier plus a number to move the window to that numbered Desktop. When Window Switcher is open without a focused preview, the same shortcut switches to that numbered Space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)

                    Text("Current modifier: \(modifierConverter.toSymbol(spacesShortcutKeybind))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
            }
        }
    }
}
