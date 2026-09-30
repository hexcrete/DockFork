import Defaults
import SwiftUI

struct DockPreviewAppearanceSection: View {
    @Default(.showAppName) var showAppName
    @Default(.appNameStyle) var appNameStyle
    @Default(.showAppIconOnly) var showAppIconOnly
    @Default(.dockPreviewControlPosition) var dockPreviewControlPosition
    @Default(.showWindowTitle) var showWindowTitle
    @Default(.windowTitleVisibility) var windowTitleVisibility
    @Default(.disableDockStyleTitles) var disableDockStyleTitles
    @Default(.disableDockStyleTrafficLights) var disableDockStyleTrafficLights
    @Default(.showMassActionButtons) var showMassActionButtons
    @Default(.useEmbeddedDockPreviewElements) var useEmbeddedDockPreviewElements
    @Default(.previewMaxColumns) var previewMaxColumns
    @Default(.previewMaxRows) var previewMaxRows
    @Default(.showDockPreviewSpaceNumberIndicator) var showDockPreviewSpaceNumberIndicator
    @Default(.highlightDockPreviewCurrentSpaceIndicator) var highlightDockPreviewCurrentSpaceIndicator
    @Default(.dockPreviewWindowStateIndicatorPlacement) var dockPreviewWindowStateIndicatorPlacement
    @Default(.disableDockStyleWindowStateIndicator) var disableDockStyleWindowStateIndicator
    @Default(.swapDockPreviewTrafficLightsAndWindowStateIndicator) var swapTrafficLightsAndWindowStateIndicator
    @Default(.limitDockPreviewIndicatorSwapToCompactMode) var limitIndicatorSwapToCompactMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // App Header section
            Toggle(isOn: $showAppName) {
                Text("Show App Header")
            }
            .settingsSearchTarget("appearance.dockShowAppHeader")

            if showAppName {
                Picker(String(localized: "App Header Style"), selection: $appNameStyle) {
                    ForEach(AppNameStyle.allCases, id: \.self) { style in
                        Text(style.localizedName)
                            .tag(style)
                    }
                }
                .settingsSearchTarget("appearance.dockAppHeaderStyle")

                Toggle(isOn: $showAppIconOnly) {
                    Text("Show App Icon Only")
                }
                .settingsSearchTarget("appearance.dockShowAppIconOnly")
            }

            Divider().padding(.vertical, 2)
            Text("Dock Preview Toolbar").font(.headline).padding(.bottom, -2)

            Picker("Position Dock Preview Controls", selection: $dockPreviewControlPosition) {
                ForEach(WindowSwitcherControlPosition.allCases, id: \.self) { position in
                    Text(position.localizedName)
                        .tag(position)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .settingsSearchTarget("appearance.dockControlPosition")

            Toggle(isOn: $showWindowTitle) {
                Text("Show Window Title")
            }
            .settingsSearchTarget("appearance.dockShowWindowTitle")

            if showWindowTitle {
                Picker("Window Title Visibility", selection: $windowTitleVisibility) {
                    ForEach(WindowTitleVisibility.allCases, id: \.self) { visibility in
                        Text(visibility.localizedName)
                            .tag(visibility)
                    }
                }
                .settingsSearchTarget("appearance.dockWindowTitleVisibility")

                VStack(alignment: .leading) {
                    Toggle(isOn: $disableDockStyleTitles) {
                        Text("Disable dock styling on window titles")
                    }
                    .settingsSearchTarget("appearance.dockDisableTitleStyling")
                    Text("Removes the pill-shaped background styling from window titles in dock previews for a cleaner look.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }
            }

            Divider().padding(.vertical, 2)
            Text("Traffic Light Buttons in Previews").font(.headline).padding(.bottom, -2)
            AppearanceSettingsView.TrafficLightButtonsSettingsView()

            VStack(alignment: .leading) {
                Toggle(isOn: $disableDockStyleTrafficLights) {
                    Text("Disable dock styling on traffic light buttons")
                }
                .settingsSearchTarget("appearance.dockDisableTrafficLightStyling")
                Text("Removes the pill-shaped background styling from traffic light buttons in dock previews for a cleaner look.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.leading, 20)
            }

            Divider().padding(.vertical, 2)
            Text("Window State Indicator").font(.headline).padding(.bottom, -2)
            Toggle("Show Space Number Indicator", isOn: $showDockPreviewSpaceNumberIndicator)
                .settingsSearchTarget("appearance.dockSpaceNumberIndicator")

            VStack(alignment: .leading) {
                Toggle("Highlight Current Space", isOn: $highlightDockPreviewCurrentSpaceIndicator)
                    .settingsSearchTarget("appearance.dockHighlightCurrentSpace")
                Text("Highlights the Space number indicator for windows on the current Space.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.leading, 20)
            }
            .padding(.leading, 20)
            .disabled(!showDockPreviewSpaceNumberIndicator)
            .opacity(showDockPreviewSpaceNumberIndicator ? 1 : 0.5)

            Picker("Show Window State Indicator", selection: $dockPreviewWindowStateIndicatorPlacement) {
                ForEach(WindowStateIndicatorPlacement.allCases, id: \.self) { placement in
                    Text(placement.localizedName).tag(placement)
                }
            }
            .pickerStyle(.menu)
            .settingsSearchTarget("appearance.dockWindowStateIndicator")
            Text("Controls whether Minimized, Hidden, and Full Screen indicators are hidden, shown on window previews, or placed next to traffic light buttons.")
                .font(.footnote)
                .foregroundColor(.gray)

            if showDockPreviewSpaceNumberIndicator || dockPreviewWindowStateIndicatorPlacement == .nextToTrafficLightButtons {
                VStack(alignment: .leading) {
                    Toggle("Disable dock styling on Window State Indicator", isOn: $disableDockStyleWindowStateIndicator)
                        .settingsSearchTarget("appearance.dockDisableWindowStateIndicatorStyling")
                    Text("Removes the pill-shaped background styling from the Window State Indicator in dock previews.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)

                    Toggle("Swap Window State Indicator and Traffic Light Buttons", isOn: $swapTrafficLightsAndWindowStateIndicator)
                        .settingsSearchTarget("appearance.dockSwapWindowStateIndicator")

                    if swapTrafficLightsAndWindowStateIndicator {
                        Toggle("Limit to Compact Mode only", isOn: $limitIndicatorSwapToCompactMode)
                            .padding(.leading, 20)
                            .settingsSearchTarget("appearance.dockLimitIndicatorSwapToCompactMode")
                    }
                }
            }

            Divider().padding(.vertical, 2)
            Text("Mass Action Buttons").font(.headline).padding(.bottom, -2)

            VStack(alignment: .leading) {
                Toggle(isOn: $showMassActionButtons) {
                    Text("Show Close All and Minimize All buttons")
                }
                .settingsSearchTarget("appearance.dockMassActionButtons")
                Text("Displays Close All and Minimize All buttons when hovering the app header in dock previews.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.leading, 20)
            }

            Divider().padding(.vertical, 2)
            Text("Dock Preview Layout").font(.headline).padding(.bottom, -2)

            VStack(alignment: .leading) {
                Toggle(isOn: $useEmbeddedDockPreviewElements) {
                    Text("Embed controls in preview frames")
                }
                .settingsSearchTarget("appearance.dockEmbedControls")
                Text("Places traffic light buttons and window titles directly inside the dock preview frames for a more compact and minimal appearance.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.leading, 20)
            }

            VStack(alignment: .leading, spacing: 4) {
                let previewMaxRowsBinding = Binding<Double>(
                    get: { Double(previewMaxRows) },
                    set: { previewMaxRows = Int($0) }
                )
                sliderSetting(
                    title: "Max Rows (Bottom Dock)",
                    value: previewMaxRowsBinding,
                    range: 1.0 ... 8.0,
                    step: 1.0,
                    unit: "",
                    formatter: {
                        let f = NumberFormatter()
                        f.minimumFractionDigits = 0
                        f.maximumFractionDigits = 0
                        return f
                    }()
                )
                .settingsSearchTarget("appearance.dockMaxRows")

                let previewMaxColumnsBinding = Binding<Double>(
                    get: { Double(previewMaxColumns) },
                    set: { previewMaxColumns = Int($0) }
                )
                sliderSetting(
                    title: "Max Columns (Left/Right Dock)",
                    value: previewMaxColumnsBinding,
                    range: 1.0 ... 8.0,
                    step: 1.0,
                    unit: "",
                    formatter: {
                        let f = NumberFormatter()
                        f.minimumFractionDigits = 0
                        f.maximumFractionDigits = 0
                        return f
                    }()
                )
                .settingsSearchTarget("appearance.dockMaxColumns")

                Text(String(localized: "Controls how many rows/columns of windows are shown in dock previews. Only the relevant setting applies based on dock position."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
