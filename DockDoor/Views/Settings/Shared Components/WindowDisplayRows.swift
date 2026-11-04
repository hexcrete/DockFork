import SwiftUI

struct SharedWindowDisplayRows: View {
    let currentSpaceOnly: Binding<Bool>
    let currentSpaceOnlyTarget: String
    let monitorCaption: LocalizedStringKey
    let currentMonitorOnly: Binding<Bool>
    let currentMonitorOnlyTarget: String
    let includeHidden: Binding<Bool>
    let includeHiddenTarget: String
    let showWindowless: Binding<Bool>
    let showWindowlessTarget: String
    let windowlessTitle: LocalizedStringKey
    let windowlessCaption: LocalizedStringKey
    var ignoreSingleWindow: Binding<Bool>?
    var ignoreSingleWindowTarget: String?
    var ignoreSingleWindowCaption: LocalizedStringKey?

    var body: some View {
        Toggle(isOn: currentSpaceOnly) { Text("Show windows from current Space only") }
            .settingsSearchTarget(currentSpaceOnlyTarget)
            .settingsAnnotation("Only display windows that are in the current virtual desktop/Space.")

        Toggle(isOn: currentMonitorOnly) { Text("Show windows from current monitor only") }
            .settingsSearchTarget(currentMonitorOnlyTarget)
            .settingsAnnotation(monitorCaption)

        Toggle(isOn: includeHidden) { Text("Include hidden/minimized windows") }
            .settingsSearchTarget(includeHiddenTarget)

        Toggle(isOn: showWindowless) { Text(windowlessTitle) }
            .settingsSearchTarget(showWindowlessTarget)
            .settingsAnnotation(windowlessCaption)

        if let ignoreSingleWindow, let ignoreSingleWindowTarget, let ignoreSingleWindowCaption {
            Toggle(isOn: ignoreSingleWindow) { Text("Ignore apps with one window") }
                .settingsSearchTarget(ignoreSingleWindowTarget)
                .settingsAnnotation(ignoreSingleWindowCaption)
        }
    }
}

struct WindowStateIndicatorSettingsSection: View {
    @Binding var spacePlacement: WindowStateIndicatorPlacement
    @Binding var highlightCurrentSpace: Bool
    @Binding var statePlacement: WindowStateIndicatorPlacement
    @Binding var disableStyling: Bool
    @Binding var swapControls: Bool
    @Binding var compactSwapOnly: Bool
    let spaceNumberTarget: String
    let highlightTarget: String
    let stateTarget: String
    let stylingTarget: String
    let swapTarget: String
    let compactTarget: String

    var body: some View {
        SettingsSection("Window State Indicator") {
            Picker("Show Space Number Indicator", selection: $spacePlacement) {
                ForEach(WindowStateIndicatorPlacement.allCases, id: \.self) { placement in
                    Text(placement.localizedName).tag(placement)
                }
            }
            .settingsSearchTarget(spaceNumberTarget)

            if spacePlacement != .off {
                Group {
                    Toggle("Highlight Current Space", isOn: $highlightCurrentSpace)
                        .settingsSearchTarget(highlightTarget)
                        .settingsAnnotation("Tint the Space number indicator when this window is on the currently active Space.")
                }
            }
            Picker("Show Window State Indicator", selection: $statePlacement) {
                ForEach(WindowStateIndicatorPlacement.allCases, id: \.self) { placement in
                    Text(placement.localizedName).tag(placement)
                }
            }
            .settingsSearchTarget(stateTarget)
            .settingsAnnotation("Controls whether Minimized, Hidden, and Full Screen indicators are hidden, shown on window previews, or placed next to traffic light buttons.")
            if spacePlacement == .nextToTrafficLightButtons || statePlacement == .nextToTrafficLightButtons {
                Group {
                    Toggle("Disable dock styling on Window State Indicator", isOn: $disableStyling)
                        .settingsSearchTarget(stylingTarget)
                        .settingsAnnotation("Removes the pill-shaped background styling from the Window State Indicator.")
                    Toggle("Swap Window State Indicator and Traffic Light Buttons", isOn: $swapControls)
                        .settingsSearchTarget(swapTarget)
                    if swapControls {
                        Group {
                            Toggle("Limit to Compact Mode only", isOn: $compactSwapOnly)
                                .settingsSearchTarget(compactTarget)
                        }
                    }
                }
            }
        }
    }
}
