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
            }
        }
    }
}

private struct SpacesSettingsSection: View {
    @Default(.enableSpaceIndicatorWindowMoving) private var enableSpaceIndicatorWindowMoving
    @Default(.spaceMenuDisplayMode) private var spaceMenuDisplayMode
    @Default(.switchToDestinationSpaceAfterMoving) private var switchToDestinationSpaceAfterMoving
    @Default(.showUnavailableSpacesInMenu) private var showUnavailableSpacesInMenu

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

                    Toggle("Switch to the destination Space after moving the window", isOn: $switchToDestinationSpaceAfterMoving)
                        .settingsSearchTarget("gestures.switchToDestinationSpaceAfterMoving")

                    Toggle("Show unavailable Spaces in the list", isOn: $showUnavailableSpacesInMenu)
                        .settingsSearchTarget("gestures.showUnavailableSpacesInMenu")

                    Text("Show Spaces the window cannot be moved to in the Spaces dropdown menu.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
            }
        }
    }
}
