import Defaults
import SwiftUI

struct TrackpadSwitcherSwipeSection: View {
    @Default(.enableSpacesBar) private var enableSpacesBar
    @Default(.trackpadSwitcherSwipeSpaces) private var trackpadSwitcherSwipeSpaces
    @Default(.enableWindowSwitcher) var enableWindowSwitcher
    @Default(.enableTrackpadSwitcherSwipe) var enableTrackpadSwitcherSwipe
    @Default(.trackpadSwitcherSwipeFingers) var trackpadSwitcherSwipeFingers
    @Default(.trackpadSwitcherSwipeDirection) var trackpadSwitcherSwipeDirection
    @Default(.trackpadSwitcherSwipeDisabledActivationDirections) private var disabledActivationDirections
    @Default(.reverseTrackpadSwipeSelectionDirection) private var reverseTrackpadSwipeSelectionDirection
    @Default(.selectWindowOnPersistentSwitcherSwipe) private var selectWindowOnPersistentSwitcherSwipe
    @Default(.trackpadSwitcherSwipeSensitivity) var trackpadSwitcherSwipeSensitivity

    var body: some View {
        SettingsGroup(header: "Trackpad Swipe for Window Switcher") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $enableTrackpadSwitcherSwipe) {
                    HStack(spacing: 8) {
                        Image(systemName: "hand.draw")
                            .foregroundColor(.accentColor)
                        Text("Open window switcher with a trackpad swipe")
                    }
                }
                .settingsSearchTarget("gestures.trackpadSwitcherSwipe")
                .onChange(of: enableTrackpadSwitcherSwipe) { _ in askUserToRestartApplication() }

                if enableTrackpadSwitcherSwipe {
                    Text("Swipe to open the switcher, keep your fingers down to change the selection, then lift your fingers to switch.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)

                    Divider()

                    Picker("Fingers:", selection: $trackpadSwitcherSwipeFingers) {
                        Text("3").tag(3)
                        Text("4").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .settingsSearchTarget("gestures.trackpadSwitcherSwipeFingers")

                    Picker("Direction:", selection: $trackpadSwitcherSwipeDirection) {
                        ForEach(TrackpadSwipeDirection.allCases, id: \.self) { direction in
                            Text(direction.localizedName).tag(direction)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .settingsSearchTarget("gestures.trackpadSwitcherSwipeDirection")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Disable activation directions"))
                        HStack(spacing: 16) {
                            ForEach(TrackpadSwipeActivationDirection.allCases, id: \.self) { direction in
                                Toggle(direction.localizedName, isOn: Binding(
                                    get: { disabledActivationDirections.contains(direction) },
                                    set: { disabled in
                                        if disabled { disabledActivationDirections.insert(direction) }
                                        else { disabledActivationDirections.remove(direction) }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }
                        Text(String(localized: "Checked directions won't open the switcher. All directions still navigate an open switcher. macOS gestures are unchanged."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .settingsSearchTarget("gestures.trackpadSwitcherSwipeDisabledActivationDirections")

                    Text("For directions that open the switcher, disable conflicting macOS gestures in System Settings > Trackpad > More Gestures.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if enableSpacesBar {
                        Toggle(isOn: $trackpadSwitcherSwipeSpaces) {
                            Text(trackpadSwitcherSwipeDirection.spacesBarNavigationTitle)
                        }
                        .settingsSearchTarget("gestures.trackpadSwitcherSwipeSpaces")
                        if trackpadSwitcherSwipeSpaces {
                            Text("The activation direction restrictions also apply to Spaces Bar swipes.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    let sensitivityBinding = Binding<Double>(
                        get: { Double(trackpadSwitcherSwipeSensitivity) },
                        set: { trackpadSwitcherSwipeSensitivity = CGFloat($0) }
                    )
                    sliderSetting(
                        title: "Swipe Sensitivity",
                        value: sensitivityBinding,
                        range: Double(TrackpadSwipeDetector.sensitivityRange.lowerBound) ... Double(TrackpadSwipeDetector.sensitivityRange.upperBound),
                        step: 0.1,
                        unit: "",
                        formatter: NumberFormatter.percentFormatter
                    )
                    .settingsSearchTarget("gestures.trackpadSwitcherSwipeSensitivity")

                    Text("Higher values open the switcher and change the selection with shorter swipes.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(isOn: $reverseTrackpadSwipeSelectionDirection) {
                        Text(String(localized: "Reverse swipe selection direction"))
                    }
                    .settingsSearchTarget("gestures.reverseTrackpadSwipeSelectionDirection")

                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: $selectWindowOnPersistentSwitcherSwipe) {
                            Text(String(localized: "Select highlighted window when swiping in persistent Window Switchers"))
                        }
                        .settingsSearchTarget("gestures.trackpadSwitcherSwipePersistentSelection")

                        Text(String(localized: "Swiping takes over persistent Window Switchers and unfocuses search. Lift your fingers to activate the selected window. Regular Window Switchers remain controlled by their initializer key while it is held."))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .disabled(!enableWindowSwitcher)
            .opacity(enableWindowSwitcher ? 1.0 : 0.5)
        }
    }
}
