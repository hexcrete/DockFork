import Defaults
import SwiftUI

struct AppearanceSettingsView: View {
    @Default(.disableImagePreview) var disableImagePreview

    @StateObject private var permissionsChecker = PermissionsChecker()

    var body: some View {
        BaseSettingsView {
            VStack(alignment: .leading, spacing: 16) {
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

                AdvancedAppearanceSection()
            }
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

    var body: some View {
        Group {
            if enableSpacesBar {
                SettingsGroup(header: "Spaces Bar") {
                    VStack(alignment: .leading, spacing: 10) {
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
                            HStack {
                                Text("Pill width")
                                Slider(value: $spacesBarPillWidth, in: 10 ... 600, step: 10)
                                Text("\(Int(spacesBarPillWidth))")
                            }
                            .settingsSearchTarget("windowSwitcher.spacesBarPillWidth")
                        } else if spacesBarShowAppIcons {
                            HStack {
                                Text("Minimum icons")
                                Slider(value: minimumIcons, in: 0 ... Double(SpacesBarIconLimits.minimumUpperBound), step: 1)
                                    .accessibilityLabel(Text("Minimum icons"))
                                Text("\(iconLimits.minimum)")
                            }
                            .settingsSearchTarget("windowSwitcher.spacesBarMinimumIcons")
                            HStack {
                                Text("Maximum icons")
                                Slider(value: maximumIcons, in: 0 ... Double(SpacesBarIconLimits.maximumUpperBound), step: 1)
                                    .accessibilityLabel(Text("Maximum icons"))
                                Text("\(iconLimits.maximum)")
                            }
                            .settingsSearchTarget("windowSwitcher.spacesBarMaximumIcons")
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
