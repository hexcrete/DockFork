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
    @Default(.spacesBarPreferDetails) private var spacesBarPreferDetails
    @Default(.spacesBarMinimumWidth) private var spacesBarMinimumWidth
    @Default(.spacesBarMaximumWidth) private var spacesBarMaximumWidth
    @Default(.spacesBarPillWidth) private var spacesBarPillWidth

    private enum SpacesBarWidthMode: Int {
        case screenSpace, details, fixed
    }

    private var spacesBarWidthMode: Binding<SpacesBarWidthMode> {
        Binding(get: {
            spacesBarFixedWidth ? .fixed : (spacesBarPreferDetails ? .details : .screenSpace)
        }, set: { mode in
            spacesBarFixedWidth = mode == .fixed
            spacesBarPreferDetails = mode == .details
        })
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
                        Picker("Pill width", selection: spacesBarWidthMode) {
                            Text("Flexible (Prefer screen space)").tag(SpacesBarWidthMode.screenSpace)
                            Text("Flexible (Prefer Space details)").tag(SpacesBarWidthMode.details)
                                .settingsSearchTarget("windowSwitcher.spacesBarPreferDetails")
                            Text("Fixed").tag(SpacesBarWidthMode.fixed)
                        }
                        .settingsSearchTarget("windowSwitcher.spacesBarFixedWidth")
                        if spacesBarFixedWidth {
                            HStack {
                                Text("Pill width")
                                Slider(value: $spacesBarPillWidth, in: 10 ... 600, step: 10)
                                Text("\(Int(spacesBarPillWidth))")
                            }
                            .settingsSearchTarget("windowSwitcher.spacesBarPillWidth")
                        } else if spacesBarPreferDetails {
                            HStack {
                                Text("Maximum pill width")
                                Slider(value: $spacesBarMaximumWidth, in: 10 ... 600, step: 10)
                                Text("\(Int(spacesBarMaximumWidth))")
                            }
                            .settingsSearchTarget("windowSwitcher.spacesBarMaximumWidth")
                        } else {
                            HStack {
                                Text("Minimum pill width")
                                Slider(value: $spacesBarMinimumWidth, in: 10 ... 600, step: 10)
                                Text("\(Int(spacesBarMinimumWidth))")
                            }
                            .settingsSearchTarget("windowSwitcher.spacesBarMinimumWidth")
                        }
                    }
                }
            }
        }
        .onChange(of: spacesBarItemSize) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar() }
        .onChange(of: spacesBarShowAppIcons) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar() }
        .onChange(of: spacesBarLabels) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar() }
        .onChange(of: spacesBarFixedWidth) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar() }
        .onChange(of: spacesBarPreferDetails) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar() }
        .onChange(of: spacesBarMinimumWidth) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar() }
        .onChange(of: spacesBarMaximumWidth) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar() }
        .onChange(of: spacesBarPillWidth) { _ in SharedPreviewWindowCoordinator.activeInstance?.refreshSpacesBar() }
    }
}
