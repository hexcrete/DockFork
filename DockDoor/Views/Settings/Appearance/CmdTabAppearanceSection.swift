import Defaults
import SwiftUI

struct CmdTabAppearanceSection: View {
    @Default(.cmdTabShowAppName) var cmdTabShowAppName
    @Default(.cmdTabAppNameStyle) var cmdTabAppNameStyle
    @Default(.cmdTabShowAppIconOnly) var cmdTabShowAppIconOnly
    @Default(.cmdTabShowWindowTitle) var cmdTabShowWindowTitle
    @Default(.cmdTabWindowTitleVisibility) var cmdTabWindowTitleVisibility
    @Default(.cmdTabDisableDockStyleTitles) var cmdTabDisableDockStyleTitles
    @Default(.cmdTabControlPosition) var cmdTabControlPosition
    @Default(.cmdTabTrafficLightButtonsVisibility) var cmdTabTrafficLightButtonsVisibility
    @Default(.cmdTabEnabledTrafficLightButtons) var cmdTabEnabledTrafficLightButtons
    @Default(.cmdTabUseMonochromeTrafficLights) var cmdTabUseMonochromeTrafficLights
    @Default(.cmdTabDisableDockStyleTrafficLights) var cmdTabDisableDockStyleTrafficLights
    @Default(.cmdTabUseEmbeddedDockPreviewElements) var cmdTabUseEmbeddedDockPreviewElements
    @Default(.showCmdTabSpaceNumberIndicator) var showCmdTabSpaceNumberIndicator
    @Default(.highlightCmdTabCurrentSpaceIndicator) var highlightCmdTabCurrentSpaceIndicator
    @Default(.cmdTabWindowStateIndicatorPlacement) var cmdTabWindowStateIndicatorPlacement
    @Default(.cmdTabDisableDockStyleWindowStateIndicator) var cmdTabDisableDockStyleWindowStateIndicator

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // App Header section
            Toggle("Show App Header", isOn: $cmdTabShowAppName)
                .settingsSearchTarget("appearance.cmdTabShowAppHeader")

            if cmdTabShowAppName {
                Picker("App Header Style", selection: $cmdTabAppNameStyle) {
                    ForEach(AppNameStyle.allCases, id: \.self) { style in
                        Text(style.localizedName)
                            .tag(style)
                    }
                }
                .settingsSearchTarget("appearance.cmdTabAppHeaderStyle")
                Toggle("Show App Icon Only", isOn: $cmdTabShowAppIconOnly)
                    .settingsSearchTarget("appearance.cmdTabShowAppIconOnly")
            }

            // Toolbar section
            Divider().padding(.vertical, 2)
            Text("Cmd+Tab Toolbar").font(.headline).padding(.bottom, -2)

            Picker("Position Window Controls", selection: $cmdTabControlPosition) {
                ForEach(WindowSwitcherControlPosition.allCases, id: \.self) { position in
                    Text(position.localizedName)
                        .tag(position)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .settingsSearchTarget("appearance.cmdTabControlPosition")

            Toggle("Show Window Title", isOn: $cmdTabShowWindowTitle)
                .settingsSearchTarget("appearance.cmdTabShowWindowTitle")

            if cmdTabShowWindowTitle {
                Picker("Window Title Visibility", selection: $cmdTabWindowTitleVisibility) {
                    ForEach(WindowTitleVisibility.allCases, id: \.self) { visibility in
                        Text(visibility.localizedName)
                            .tag(visibility)
                    }
                }
                .settingsSearchTarget("appearance.cmdTabWindowTitleVisibility")

                VStack(alignment: .leading) {
                    Toggle(isOn: $cmdTabDisableDockStyleTitles) {
                        Text("Disable dock styling on window titles")
                    }
                    .settingsSearchTarget("appearance.cmdTabDisableTitleStyling")
                    Text("Removes the pill-shaped background styling from window titles.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }
            }

            // Traffic Light Buttons section
            Divider().padding(.vertical, 2)
            Text("Traffic Light Buttons").font(.headline).padding(.bottom, -2)

            Picker("Visibility", selection: $cmdTabTrafficLightButtonsVisibility) {
                ForEach(TrafficLightButtonsVisibility.allCases, id: \.self) { visibility in
                    Text(visibility.localizedName)
                        .tag(visibility)
                }
            }
            .settingsSearchTarget("appearance.cmdTabTrafficLightVisibility")

            if cmdTabTrafficLightButtonsVisibility != .never {
                Text("Enabled Buttons")
                VStack(alignment: .leading) {
                    if !cmdTabEnabledTrafficLightButtons.isEmpty {
                        TrafficLightButtons(
                            displayMode: cmdTabTrafficLightButtonsVisibility,
                            hoveringOverParentWindow: true,
                            onWindowAction: { _ in },
                            pillStyling: true,
                            mockPreviewActive: false,
                            enabledButtons: cmdTabEnabledTrafficLightButtons,
                            useMonochrome: cmdTabUseMonochromeTrafficLights,
                            backgroundAppearance: .resolve()
                        )
                    }
                    EnabledButtonsCheckboxes(
                        enabledButtons: $cmdTabEnabledTrafficLightButtons,
                        visibilityBinding: $cmdTabTrafficLightButtonsVisibility,
                        useMonochrome: cmdTabUseMonochromeTrafficLights
                    )
                }
                Toggle("Use Monochrome Colors", isOn: $cmdTabUseMonochromeTrafficLights)
                    .settingsSearchTarget("appearance.cmdTabMonochrome")

                VStack(alignment: .leading) {
                    Toggle(isOn: $cmdTabDisableDockStyleTrafficLights) {
                        Text("Disable dock styling on traffic light buttons")
                    }
                    .settingsSearchTarget("appearance.cmdTabDisableTrafficLightStyling")
                    Text("Removes the pill-shaped background styling from traffic light buttons.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }
            }

            Divider().padding(.vertical, 2)
            Text("Window State Indicator").font(.headline).padding(.bottom, -2)
            Toggle("Show Space Number Indicator", isOn: $showCmdTabSpaceNumberIndicator)
                .settingsSearchTarget("appearance.cmdTabSpaceNumberIndicator")

            VStack(alignment: .leading) {
                Toggle("Highlight Current Space", isOn: $highlightCmdTabCurrentSpaceIndicator)
                    .settingsSearchTarget("appearance.cmdTabHighlightCurrentSpace")
                Text("Highlights the Space number indicator for windows on the current Space.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.leading, 20)
            }
            .padding(.leading, 20)
            .disabled(!showCmdTabSpaceNumberIndicator)
            .opacity(showCmdTabSpaceNumberIndicator ? 1 : 0.5)

            Picker("Show Window State Indicator", selection: $cmdTabWindowStateIndicatorPlacement) {
                ForEach(WindowStateIndicatorPlacement.allCases, id: \.self) { placement in
                    Text(placement.localizedName).tag(placement)
                }
            }
            .pickerStyle(.menu)
            .settingsSearchTarget("appearance.cmdTabWindowStateIndicator")
            Text("Controls whether Minimized, Hidden, and Full Screen indicators are hidden, shown on window previews, or placed next to traffic light buttons.")
                .font(.footnote)
                .foregroundColor(.gray)

            if showCmdTabSpaceNumberIndicator || cmdTabWindowStateIndicatorPlacement == .nextToTrafficLightButtons {
                VStack(alignment: .leading) {
                    Toggle("Disable dock styling on Window State Indicator", isOn: $cmdTabDisableDockStyleWindowStateIndicator)
                        .settingsSearchTarget("appearance.cmdTabDisableWindowStateIndicatorStyling")
                    Text("Removes the pill-shaped background styling from the Window State Indicator in Cmd+Tab previews.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }
            }

            // Layout section
            Divider().padding(.vertical, 2)
            Text("Cmd+Tab Layout").font(.headline).padding(.bottom, -2)

            VStack(alignment: .leading) {
                Toggle(isOn: $cmdTabUseEmbeddedDockPreviewElements) {
                    Text("Embed controls in preview frames")
                }
                .settingsSearchTarget("appearance.cmdTabEmbedControls")
                Text("Places traffic light buttons and window titles directly inside the preview frames.")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.leading, 20)
            }
        }
    }
}
