import Defaults
import SwiftUI

struct GeneralAppearanceSection: View {
    @Default(.uniformCardRadius) var uniformCardRadius
    @Default(.previewCornerRadius) var previewCornerRadius
    @Default(.globalPaddingMultiplier) var globalPaddingMultiplier
    @Default(.trafficLightButtonScale) var trafficLightButtonScale
    @Default(.windowTitleFontSize) var windowTitleFontSize
    @Default(.windowStateIndicatorFontSize) private var windowStateIndicatorFontSize
    @Default(.trafficLightTransitionDuration) private var trafficLightTransitionDuration
    @Default(.unselectedContentOpacity) var unselectedContentOpacity
    @Default(.titleOverflowStyle) var titleOverflowStyle
    @Default(.dimMinimizedHiddenPreviews) var dimMinimizedHiddenPreviews
    @Default(.showSpaceNumber) var showSpaceNumber
    @Default(.showWindowlessAppQuitButton) var showWindowlessAppQuitButton
    @Default(.hidePreviewCardBackground) var hidePreviewCardBackground
    @Default(.hideHoverContainerBackground) var hideHoverContainerBackground
    @Default(.hideWidgetContainerBackground) var hideWidgetContainerBackground
    @Default(.showActiveWindowBorder) var showActiveWindowBorder
    @Default(.appAppearanceMode) var appAppearanceMode

    var body: some View {
        SettingsGroup(header: "General Appearance") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Appearance", selection: $appAppearanceMode) {
                    ForEach(AppAppearanceMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .settingsSearchTarget("appearance.theme")
                .onChange(of: appAppearanceMode) { newMode in
                    applyAppearanceMode(newMode)
                }

                sliderSetting(
                    title: "Spacing Scale",
                    value: $globalPaddingMultiplier,
                    range: 0.5 ... 2.0,
                    step: 0.1,
                    unit: "×",
                    formatter: {
                        let f = NumberFormatter()
                        f.minimumFractionDigits = 1
                        f.maximumFractionDigits = 1
                        return f
                    }()
                )
                .settingsSearchTarget("appearance.spacingScale")

                sliderSetting(
                    title: "Traffic Light Button Scale",
                    value: $trafficLightButtonScale,
                    range: 0.75 ... 2.0,
                    step: 0.05,
                    unit: "×",
                    formatter: NumberFormatter.twoDecimalFormatter
                )
                .settingsSearchTarget("appearance.trafficLightButtonScale")

                Picker("Window Title Font Size", selection: $windowTitleFontSize) {
                    ForEach(WindowTitleFontSize.allCases) { size in
                        Text(size.localizedName)
                            .tag(size)
                    }
                }
                .settingsSearchTarget("appearance.windowTitleFontSize")

                Picker(String(localized: "Window State / Space Number Indicator Font Size"), selection: $windowStateIndicatorFontSize) {
                    ForEach(WindowTitleFontSize.allCases) { size in
                        Text(size.localizedName).tag(size)
                    }
                }
                .settingsSearchTarget("appearance.windowStateIndicatorFontSize")

                VStack(alignment: .leading) {
                    sliderSetting(
                        title: "Traffic Light Buttons Transition Animation Speed",
                        value: $trafficLightTransitionDuration,
                        range: 0 ... 0.2,
                        step: 0.01,
                        unit: "seconds",
                        formatter: NumberFormatter.twoDecimalFormatter
                    )
                    .settingsSearchTarget("appearance.trafficLightTransitionDuration")
                    Text("Controls traffic light button transitions in all preview modes, independently of Reduce Motion. Set to 0 seconds to disable.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }

                sliderSetting(
                    title: "Unselected Content Opacity",
                    value: $unselectedContentOpacity,
                    range: 0 ... 1,
                    step: 0.05,
                    unit: "",
                    formatter: NumberFormatter.percentFormatter
                )
                .settingsSearchTarget("appearance.unselectedOpacity")

                VStack(alignment: .leading) {
                    Toggle(isOn: $uniformCardRadius) {
                        Text("Rounded corners")
                    }
                    .settingsSearchTarget("appearance.roundedCorners")
                    Text("Round the corners of window preview images for a modern look.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)

                    if uniformCardRadius {
                        sliderSetting(
                            title: "Corner Radius",
                            value: $previewCornerRadius,
                            range: 0 ... 40,
                            step: 1,
                            unit: "pt"
                        )
                        .padding(.leading, 20)
                        .settingsSearchTarget("appearance.cornerRadius")
                    }
                }

                VStack(alignment: .leading) {
                    Picker("Long title overflow", selection: $titleOverflowStyle) {
                        ForEach(TitleOverflowStyle.allCases, id: \.self) { style in
                            Text(style.localizedName).tag(style)
                        }
                    }
                    .settingsSearchTarget("appearance.marquee")
                    Text("How to display window titles that are too long to fit.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading) {
                    Toggle(isOn: $dimMinimizedHiddenPreviews) {
                        Text("Dim minimized and hidden previews")
                    }
                    .settingsSearchTarget("appearance.dimMinimizedHiddenPreviews")
                    Text("Dims minimized and hidden window preview images without changing window state indicator visibility.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading) {
                    Toggle(isOn: $showSpaceNumber) {
                        Text("Show Space number on previews (Legacy)")
                    }
                    .settingsSearchTarget("appearance.spaceNumber")
                    Text("Labels each preview with the number of the desktop (Space) its window is on. Only shown when you have more than one desktop.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading) {
                    Toggle(isOn: $showWindowlessAppQuitButton) {
                        Text("Show quit button for apps with no open windows")
                    }
                    .settingsSearchTarget("appearance.windowlessQuitButton")
                    Text("Shows a quit-only control on previews for running apps with no open windows.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading) {
                    Toggle(isOn: $hidePreviewCardBackground) {
                        Text("Hide preview card background")
                    }
                    .settingsSearchTarget("appearance.hidePreviewBackground")
                    Text("Removes the background panel from individual window previews.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading) {
                    Toggle(isOn: $hideHoverContainerBackground) {
                        Text("Hide hover container background")
                    }
                    .settingsSearchTarget("appearance.hideContainerBackground")
                    Text("Removes the container background from window preview panels.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading) {
                    Toggle(isOn: $hideWidgetContainerBackground) {
                        Text("Hide widget container background")
                    }
                    .settingsSearchTarget("appearance.hideWidgetBackground")
                    Text("Removes the container background from widget panels (media controls, calendar).")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading) {
                    Toggle(isOn: $showActiveWindowBorder) {
                        Text("Show active window border")
                    }
                    .settingsSearchTarget("appearance.activeBorder")
                    Text("Highlights the currently focused window with a colored border.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }
            }
        }
    }
}

struct FullSizePreviewAppearanceSection: View {
    @Default(.fullSizePreviewOpacity) var fullSizePreviewOpacity
    @Default(.fullSizePreviewFadeInDuration) var fullSizePreviewFadeInDuration
    @Default(.fullSizePreviewFadeOutDuration) var fullSizePreviewFadeOutDuration
    @Default(.enableFullSizePreviewBackdropBlur) var enableFullSizePreviewBackdropBlur
    @Default(.showFullSizePreviewBorder) var showFullSizePreviewBorder

    var body: some View {
        SettingsGroup(header: "Full Size Previews") {
            VStack(alignment: .leading, spacing: 10) {
                sliderSetting(
                    title: "Opacity",
                    value: $fullSizePreviewOpacity,
                    range: 0 ... 1,
                    step: 0.05,
                    unit: "",
                    formatter: NumberFormatter.percentFormatter
                )
                .settingsSearchTarget("appearance.fullSizePreviewOpacity")

                sliderSetting(
                    title: "Fade In Duration",
                    value: $fullSizePreviewFadeInDuration,
                    range: 0 ... 1,
                    step: 0.05,
                    unit: "seconds",
                    formatter: NumberFormatter.twoDecimalFormatter
                )
                .settingsSearchTarget("appearance.fullSizePreviewFadeIn")
                Text("Set the full size preview fade-in duration. Set to 0 seconds to disable the animation.")
                    .font(.footnote)
                    .foregroundColor(.gray)

                sliderSetting(
                    title: "Fade Out Duration",
                    value: $fullSizePreviewFadeOutDuration,
                    range: 0 ... 1,
                    step: 0.05,
                    unit: "seconds",
                    formatter: NumberFormatter.twoDecimalFormatter
                )
                .settingsSearchTarget("appearance.fullSizePreviewFadeOut")
                Text("Set the full size preview fade-out duration. Set to 0 seconds to disable the animation.")
                    .font(.footnote)
                    .foregroundColor(.gray)

                VStack(alignment: .leading) {
                    Toggle(isOn: $enableFullSizePreviewBackdropBlur) {
                        Text("Blur background behind full size previews")
                    }
                    .settingsSearchTarget("appearance.fullSizePreviewBackgroundBlur")
                    Text("Blurs the content behind full size previews without blurring the preview itself.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }

                VStack(alignment: .leading) {
                    Toggle(isOn: $showFullSizePreviewBorder) {
                        Text("Show full size preview border")
                    }
                    .settingsSearchTarget("appearance.fullSizePreviewBorder")
                    Text("Uses the active window border color and stays inside the preview bounds.")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .padding(.leading, 20)
                }
            }
        }
    }
}
