import Defaults
import SwiftUI

struct CompactModeSection: View {
    @Default(.disableImagePreview) var disableImagePreview
    @Default(.compactModeTitleFormat) var compactModeTitleFormat
    @Default(.compactModeItemSize) var compactModeItemSize
    @Default(.compactModeHideTrafficLights) var compactModeHideTrafficLights
    @Default(.compactModeWidth) var compactModeWidth
    @Default(.enableHoverActionsInCompactMode) var enableHoverActionsInCompactMode
    @Default(.windowSwitcherCompactThreshold) var windowSwitcherCompactThreshold
    @Default(.dockPreviewCompactThreshold) var dockPreviewCompactThreshold
    @Default(.cmdTabCompactThreshold) var cmdTabCompactThreshold

    let hasScreenRecordingPermission: Bool

    private var isCompactModeForced: Bool {
        disableImagePreview || !hasScreenRecordingPermission
    }

    var body: some View {
        SettingsGroup(header: "Compact Mode (Titles Only)") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Compact mode displays windows as a streamlined vertical list with app icons and titles.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { !hasScreenRecordingPermission || disableImagePreview },
                        set: { disableImagePreview = $0 }
                    )) {
                        Text("Always use compact mode")
                    }
                    .settingsSearchTarget("appearance.compactMode")
                    .disabled(!hasScreenRecordingPermission)

                    if !hasScreenRecordingPermission {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.fill")
                                .font(.caption)
                            Text("Screen Recording permission is required for window thumbnails.")
                                .font(.caption)
                        }
                        .foregroundColor(.orange)
                        .padding(.leading, 20)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Enable hover actions in compact mode", isOn: $enableHoverActionsInCompactMode)
                        .settingsSearchTarget("appearance.compactHoverActions")

                    if enableHoverActionsInCompactMode, !hasScreenRecordingPermission {
                        HStack(spacing: 8) {
                            Image(systemName: "record.circle")
                                .font(.caption)
                            Text("Hover actions in compact mode require Screen Recording permission.")
                                .font(.caption)
                            Button("Grant") {
                                SystemPreferencesHelper.openScreenRecordingPreferences()
                            }
                            .buttonStyle(AccentButtonStyle(small: true))
                        }
                        .foregroundColor(.orange)
                        .padding(.leading, 20)
                    }
                }

                if !isCompactModeForced {
                    Divider().padding(.vertical, 2)
                    Text("Window Threshold").font(.headline).padding(.bottom, -2)

                    Text("Set a threshold to automatically switch to compact mode when an app has that many or more windows. Set to 0 to disable.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    compactThresholdSlider(
                        title: "Window Switcher",
                        value: $windowSwitcherCompactThreshold,
                        description: "Switch to compact list in window switcher when window count reaches threshold."
                    )
                    .settingsSearchTarget("appearance.compactThresholdSwitcher")

                    compactThresholdSlider(
                        title: "Dock Previews",
                        value: $dockPreviewCompactThreshold,
                        description: "Switch to compact list in dock previews when window count reaches threshold."
                    )
                    .settingsSearchTarget("appearance.compactThresholdDock")

                    compactThresholdSlider(
                        title: "Cmd+Tab Enhancement",
                        value: $cmdTabCompactThreshold,
                        description: "Switch to compact list in Cmd+Tab overlay when window count reaches threshold."
                    )
                    .settingsSearchTarget("appearance.compactThresholdCmdTab")
                }

                Divider().padding(.vertical, 2)
                Text("Appearance").font(.headline).padding(.bottom, -2)

                sliderSetting(
                    title: "Compact Mode Width",
                    value: $compactModeWidth,
                    range: 200 ... 1200,
                    step: 50,
                    unit: "px",
                    formatter: {
                        let f = NumberFormatter()
                        f.minimumFractionDigits = 0
                        f.maximumFractionDigits = 0
                        return f
                    }()
                )
                .settingsSearchTarget("appearance.compactModeWidth")

                Text("Controls row width in compact mode so longer titles have more room.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Item Size", selection: $compactModeItemSize) {
                    ForEach(CompactModeItemSize.allCases) { size in
                        Text(size.localizedName).tag(size)
                    }
                }
                .pickerStyle(.menu)
                .settingsSearchTarget("appearance.compactItemSize")

                Picker("Title Format", selection: $compactModeTitleFormat) {
                    ForEach(CompactModeTitleFormat.allCases) { format in
                        Text(format.localizedName).tag(format)
                    }
                }
                .pickerStyle(.menu)
                .settingsSearchTarget("appearance.compactTitleFormat")

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Hide Traffic Lights", isOn: $compactModeHideTrafficLights)
                        .settingsSearchTarget("appearance.hideTrafficLights")
                    Text("Hides the close, minimize, and other window control buttons in compact mode to provide more room for window titles.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func compactThresholdSlider(title: String, value: Binding<Int>, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue == 0 ? "Disabled" : "\(value.wrappedValue)+ windows")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0) }
                ),
                in: 0 ... 10,
                step: 1
            )

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
