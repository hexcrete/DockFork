import Defaults
import SwiftUI

struct AppearanceSettingsView: View {
    @Default(.disableImagePreview) var disableImagePreview

    @StateObject private var permissionsChecker = PermissionsChecker()

    var body: some View {
        SettingsFormView {
            if !permissionsChecker.screenRecordingPermission {
                CompactModeWarningBanner(
                    hasScreenRecordingPermission: permissionsChecker.screenRecordingPermission,
                    disableImagePreview: disableImagePreview
                )
            }

            WindowSizeSettingsSection()

            FullSizePreviewAppearanceSection()

            BackgroundAppearanceSection()

            GeneralAppearanceSection()

            CompactModeSection(hasScreenRecordingPermission: permissionsChecker.screenRecordingPermission)

            SpacesBarAppearanceSection()

            ActionFeedbackSettingsSection()

            AdvancedAppearanceSection()
        }
    }
}

struct SpacesBarAppearanceSection: View {
    @Default(.enableSpacesBar) private var enableSpacesBar
    @Default(.spacesBarItemSize) private var spacesBarItemSize
    @Default(.spacesBarShowAppIcons) private var spacesBarShowAppIcons
    @Default(.spacesBarLabels) private var spacesBarLabels
    @Default(.spacesBarFixedWidth) private var spacesBarFixedWidth
    @Default(.spacesBarMinimumIcons) private var spacesBarMinimumIcons
    @Default(.spacesBarMaximumIcons) private var spacesBarMaximumIcons
    @Default(.spacesBarPillWidth) private var spacesBarPillWidth

    private var iconLimits: SpacesBarIconLimits {
        SpacesBarIconLimits(minimum: spacesBarMinimumIcons, maximum: spacesBarMaximumIcons)
    }

    private var minimumIcons: Binding<Double> {
        Binding(get: { Double(iconLimits.minimum) },
                set: { spacesBarMinimumIcons = min(SpacesBarIconLimits.minimumUpperBound, max(0, Int($0)), iconLimits.maximum) })
    }

    private var maximumIcons: Binding<Double> {
        Binding(get: { Double(iconLimits.maximum) },
                set: { spacesBarMaximumIcons = max(iconLimits.minimum, min(SpacesBarIconLimits.maximumUpperBound, Int($0))) })
    }

    private func resetIconLimits() {
        let minimum = Double(Defaults.Keys.spacesBarMinimumIcons.defaultValue)
        let maximum = Double(Defaults.Keys.spacesBarMaximumIcons.defaultValue)
        if maximumIcons.wrappedValue < minimum {
            maximumIcons.wrappedValue = maximum
            minimumIcons.wrappedValue = minimum
        } else {
            minimumIcons.wrappedValue = minimum
            maximumIcons.wrappedValue = maximum
        }
    }

    var body: some View {
        Group {
            if enableSpacesBar {
                SettingsSection("Spaces Bar") {
                    Picker("Item Size", selection: $spacesBarItemSize) {
                        ForEach(SpacesBarItemSize.allCases) { size in
                            Text(size.localizedName).tag(size)
                        }
                    }

                    .pickerStyle(.menu)
                    .settingsSearchTarget("windowSwitcher.spacesBarItemSize")
                    Toggle("Show app icons in the Spaces Bar", isOn: $spacesBarShowAppIcons)
                        .settingsSearchTarget("windowSwitcher.spacesBarShowAppIcons")
                    Picker("Labels", selection: $spacesBarLabels) {
                        Text("Numbers").tag(SpaceMenuDisplayMode.numberOnly)
                        Text("Names").tag(SpaceMenuDisplayMode.fullName)
                    }

                    .settingsSearchTarget("windowSwitcher.spacesBarLabels")
                    Picker("Pill width", selection: $spacesBarFixedWidth) {
                        Text("Fixed").tag(true)
                        Text("Flexible").tag(false)
                    }

                    .settingsSearchTarget("windowSwitcher.spacesBarFixedWidth")
                    if spacesBarFixedWidth {
                        Group {
                            SettingsSliderRow(title: "Pill width", value: $spacesBarPillWidth, range: 10 ... 600, defaultValue: Defaults.Keys.spacesBarPillWidth.defaultValue, step: 10)
                                .settingsSearchTarget("windowSwitcher.spacesBarPillWidth")
                        }
                    } else if spacesBarShowAppIcons {
                        Group {
                            SettingsSliderRow(title: "Minimum icons", value: minimumIcons, range: 0 ... Double(SpacesBarIconLimits.minimumUpperBound), defaultValue: Double(Defaults.Keys.spacesBarMinimumIcons.defaultValue), step: 1, onReset: resetIconLimits)
                                .settingsSearchTarget("windowSwitcher.spacesBarMinimumIcons")
                                .help("Reset restores both icon limits.")
                            SettingsSliderRow(title: "Maximum icons", value: maximumIcons, range: 0 ... Double(SpacesBarIconLimits.maximumUpperBound), defaultValue: Double(Defaults.Keys.spacesBarMaximumIcons.defaultValue), step: 1, onReset: resetIconLimits)
                                .settingsSearchTarget("windowSwitcher.spacesBarMaximumIcons")
                                .help("Reset restores both icon limits.")
                        }
                    }
                }
            }
        }
        .onChange(of: spacesBarItemSize) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar(.layout) }
        .onChange(of: spacesBarShowAppIcons) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar(.layout) }
        .onChange(of: spacesBarLabels) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar(.layout) }
        .onChange(of: spacesBarFixedWidth) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar(.layout) }
        .onChange(of: spacesBarMinimumIcons) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar(.layout) }
        .onChange(of: spacesBarMaximumIcons) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar(.layout) }
        .onChange(of: spacesBarPillWidth) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar(.layout) }
    }
}

private struct ActionFeedbackSettingsSection: View {
    @Default(.enableActionFeedback) private var enabled
    @Default(.actionFeedbackPosition) private var position

    var body: some View {
        SettingsSection("Action Feedback") {
            Toggle("Enable action feedback", isOn: $enabled)
                .settingsSearchTarget("gestures.enableActionFeedback")
                .settingsAnnotation("Show progress and results for window and Space actions. Selection changes and AppleScript actions remain silent.")
            if enabled {
                Group {
                    Picker("Position:", selection: $position) {
                        ForEach(ActionFeedbackPosition.allCases, id: \.self) { Text($0.title).tag($0) }
                    }

                    .settingsSearchTarget("gestures.actionFeedbackPosition")
                }
            }
        }
    }
}
