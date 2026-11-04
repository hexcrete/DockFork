import Defaults
import SwiftUI

struct GeneralAppearanceSection: View {
    @Default(.uniformCardRadius) var uniformCardRadius
    @Default(.previewCornerRadius) var previewCornerRadius
    @Default(.globalPaddingMultiplier) var globalPaddingMultiplier
    @Default(.unselectedContentOpacity) var unselectedContentOpacity
    @Default(.titleOverflowStyle) var titleOverflowStyle
    @Default(.showWindowlessAppQuitButton) var showWindowlessAppQuitButton
    @Default(.hidePreviewCardBackground) var hidePreviewCardBackground
    @Default(.hideHoverContainerBackground) var hideHoverContainerBackground
    @Default(.hideWidgetContainerBackground) var hideWidgetContainerBackground
    @Default(.showActiveWindowBorder) var showActiveWindowBorder
    @Default(.appAppearanceMode) var appAppearanceMode

    @Default(.windowStateIndicatorFontSize) private var windowStateIndicatorFontSize
    @Default(.trafficLightTransitionDuration) private var trafficLightTransitionDuration
    @Default(.dimMinimizedHiddenPreviews) var dimMinimizedHiddenPreviews
    @Default(.centerOutOfViewSelections) private var centerOutOfViewSelections

    var body: some View {
        SettingsSection("General Appearance") {
            Picker("Appearance", selection: $appAppearanceMode) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .settingsSearchTarget("appearance.theme")
            .onChange(of: appAppearanceMode) { newMode in
                applyAppearanceMode(newMode)
            }

            SettingsSliderRow(
                title: "Spacing Scale",
                value: $globalPaddingMultiplier,
                range: 0.5 ... 2.0,
                unit: "×",
                step: 0.1
            )
            .settingsSearchTarget("appearance.spacingScale")

            SettingsSliderRow(
                title: "Unselected Content Opacity",
                value: $unselectedContentOpacity,
                range: 0 ... 1,
                step: 0.05
            )
            .settingsSearchTarget("appearance.unselectedOpacity")

            Toggle(isOn: $uniformCardRadius) {
                Text("Rounded corners")
            }
            .settingsSearchTarget("appearance.roundedCorners")
            .settingsAnnotation("Round the corners of window preview images for a modern look.")

            if uniformCardRadius {
                SettingsDependentRows {
                    SettingsSliderRow(
                        title: "Corner Radius",
                        value: $previewCornerRadius,
                        range: 0 ... 40,
                        unit: " pt",
                        step: 1
                    )
                    .settingsSearchTarget("appearance.cornerRadius")
                }
            }

            Picker("Long title overflow", selection: $titleOverflowStyle) {
                ForEach(TitleOverflowStyle.allCases, id: \.self) { style in
                    Text(style.localizedName).tag(style)
                }
            }
            .settingsSearchTarget("appearance.marquee")
            .settingsAnnotation("How to display window titles that are too long to fit.")

            Toggle("Dim minimized and hidden previews", isOn: $dimMinimizedHiddenPreviews)
                .settingsSearchTarget("appearance.dimMinimizedHiddenPreviews")
                .settingsAnnotation("Dims minimized and hidden window preview images without changing window state indicator visibility.")
            Toggle(isOn: $showWindowlessAppQuitButton) {
                Text("Show quit button for apps with no open windows")
            }
            .settingsSearchTarget("appearance.windowlessQuitButton")
            .settingsAnnotation("Shows a quit-only control on previews for running apps with no open windows.")

            Toggle(isOn: $hidePreviewCardBackground) {
                Text("Hide preview card background")
            }
            .settingsSearchTarget("appearance.hidePreviewBackground")
            .settingsAnnotation("Removes the background panel from individual window previews.")

            Toggle(isOn: $hideHoverContainerBackground) {
                Text("Hide hover container background")
            }
            .settingsSearchTarget("appearance.hideContainerBackground")
            .settingsAnnotation("Removes the container background from window preview panels.")

            Toggle(isOn: $hideWidgetContainerBackground) {
                Text("Hide widget container background")
            }
            .settingsSearchTarget("appearance.hideWidgetBackground")
            .settingsAnnotation("Removes the container background from widget panels (media controls, calendar).")

            Toggle(isOn: $showActiveWindowBorder) {
                Text("Show active window border")
            }
            .settingsSearchTarget("appearance.activeBorder")
            .settingsAnnotation("Highlights the currently focused window with a colored border.")
            Picker("Window State / Space Number Indicator Font Size", selection: $windowStateIndicatorFontSize) {
                ForEach(WindowTitleFontSize.allCases) { size in Text(size.localizedName).tag(size) }
            }

            .settingsSearchTarget("appearance.windowStateIndicatorFontSize")
            SettingsSliderRow(title: "Traffic Light Buttons Transition Animation Speed", value: $trafficLightTransitionDuration, range: 0 ... PreviewControlAnimation.maximumDuration, defaultValue: Defaults.Keys.trafficLightTransitionDuration.defaultValue, unit: " s", step: 0.01, decimals: 2)
                .settingsSearchTarget("appearance.trafficLightTransitionDuration")
            Toggle("Center out-of-view selections during keyboard navigation", isOn: $centerOutOfViewSelections)
                .settingsSearchTarget("appearance.centerOutOfViewSelections")
                .settingsAnnotation("When highlighting an out-of-view window or Space in an overflowing list, scroll it to the center. When off, scroll only enough to reveal it.")
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
        SettingsSection("Full Size Previews") {
            SettingsSliderRow(title: "Opacity", value: $fullSizePreviewOpacity, range: 0 ... 1, defaultValue: Defaults.Keys.fullSizePreviewOpacity.defaultValue, unit: "", step: 0.05, formatter: NumberFormatter.percentFormatter)
                .settingsSearchTarget("appearance.fullSizePreviewOpacity")

            SettingsSliderRow(title: "Fade In Duration", value: $fullSizePreviewFadeInDuration, range: 0 ... 1, defaultValue: Defaults.Keys.fullSizePreviewFadeInDuration.defaultValue, unit: " s", step: 0.05, formatter: NumberFormatter.twoDecimalFormatter)
                .settingsSearchTarget("appearance.fullSizePreviewFadeIn")
                .settingsAnnotation("Set the full size preview fade-in duration. Set to 0 seconds to disable the animation.")

            SettingsSliderRow(title: "Fade Out Duration", value: $fullSizePreviewFadeOutDuration, range: 0 ... 1, defaultValue: Defaults.Keys.fullSizePreviewFadeOutDuration.defaultValue, unit: " s", step: 0.05, formatter: NumberFormatter.twoDecimalFormatter)
                .settingsSearchTarget("appearance.fullSizePreviewFadeOut")
                .settingsAnnotation("Set the full size preview fade-out duration. Set to 0 seconds to disable the animation.")

            VStack(alignment: .leading) {
                Toggle(isOn: $enableFullSizePreviewBackdropBlur) {
                    Text("Blur background behind full size previews")
                }
                .settingsSearchTarget("appearance.fullSizePreviewBackgroundBlur")
                .settingsAnnotation("Blurs the content behind full size previews without blurring the preview itself.")
            }

            VStack(alignment: .leading) {
                Toggle(isOn: $showFullSizePreviewBorder) {
                    Text("Show full size preview border")
                }
                .settingsSearchTarget("appearance.fullSizePreviewBorder")
                .settingsAnnotation("Uses the active window border color and stays inside the preview bounds.")
            }
        }
    }
}
