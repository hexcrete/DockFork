import Defaults
import SwiftUI

struct GesturesAndKeybindsSettingsView: View {
    var body: some View {
        BaseSettingsView {
            VStack(alignment: .leading, spacing: 16) {
                DockScrollGestureSection()
                TitleBarScrollGestureSection()
                DockPreviewGesturesSection()
                GestureSettingsSection()
                MouseActionsSection()
                CmdKeyShortcutsSection()
                PreviewPostActionBehaviorSection()
                SpacesSettingsSection()
                WindowSwitcherKeybindSection()
                TrackpadSwitcherSwipeSection()
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
