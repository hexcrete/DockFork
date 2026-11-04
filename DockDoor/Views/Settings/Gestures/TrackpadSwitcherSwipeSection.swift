import Defaults
import SwiftUI

struct TrackpadSwitcherSwipeSection: View {
    @Default(.enableTrackpadSwitcherSwipe) var enableTrackpadSwitcherSwipe
    @Default(.trackpadSwitcherSwipeFingers) var trackpadSwitcherSwipeFingers
    @Default(.trackpadSwitcherSwipeDirection) var trackpadSwitcherSwipeDirection
    @Default(.trackpadSwitcherSwipeSensitivity) var trackpadSwitcherSwipeSensitivity

    @Default(.enableSpacesBar) private var enableSpacesBar
    @Default(.trackpadSwitcherSwipeSpaces) private var trackpadSwitcherSwipeSpaces
    @Default(.trackpadSwitcherSwipeDisabledActivationDirections) private var disabledActivationDirections
    @Default(.reverseTrackpadSwipeSelectionDirection) private var reverseTrackpadSwipeSelectionDirection
    @Default(.selectWindowOnPersistentSwitcherSwipe) private var selectWindowOnPersistentSwitcherSwipe

    var body: some View {
        SettingsSection("Trackpad Swipe for Window Switcher") {
            Group {
                Toggle(isOn: $enableTrackpadSwitcherSwipe) {
                    Text("Open window switcher with a trackpad swipe")
                }
                .settingsSearchTarget("gestures.trackpadSwitcherSwipe")
                .onChange(of: enableTrackpadSwitcherSwipe) { _ in askUserToRestartApplication() }
                .settingsAnnotation("Swipe to open the switcher, keep your fingers down to change the selection, then lift your fingers to switch.")

                if enableTrackpadSwitcherSwipe {
                    Group {
                        Picker("Fingers:", selection: $trackpadSwitcherSwipeFingers) {
                            Text("3").tag(3)
                            Text("4").tag(4)
                        }
                        .settingsSearchTarget("gestures.trackpadSwitcherSwipeFingers")

                        Picker("Direction:", selection: $trackpadSwitcherSwipeDirection) {
                            ForEach(TrackpadSwipeDirection.allCases, id: \.self) { direction in
                                Text(direction.localizedName).tag(direction)
                            }
                        }
                        .settingsSearchTarget("gestures.trackpadSwitcherSwipeDirection")

                        LabeledContent("Disable activation directions") {
                            HStack(spacing: 12) {
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
                        }
                        .settingsSearchTarget("gestures.trackpadSwitcherSwipeDisabledActivationDirections")
                        .settingsAnnotation("Checked directions won't open the switcher. All directions still navigate an open switcher. macOS gestures are unchanged.")
                        if enableSpacesBar {
                            Toggle(isOn: $trackpadSwitcherSwipeSpaces) { Text(trackpadSwitcherSwipeDirection.spacesBarNavigationTitle) }
                                .settingsSearchTarget("gestures.trackpadSwitcherSwipeSpaces")
                        }
                        Toggle("Reverse swipe selection direction", isOn: $reverseTrackpadSwipeSelectionDirection)
                            .settingsSearchTarget("gestures.reverseTrackpadSwipeSelectionDirection")
                        Toggle("Select highlighted window when swiping in persistent Window Switchers", isOn: $selectWindowOnPersistentSwitcherSwipe)
                            .settingsSearchTarget("gestures.trackpadSwitcherSwipePersistentSelection")
                            .settingsAnnotation("Swiping takes over persistent Window Switchers and unfocuses search. Lift your fingers to activate the selected window. Regular Window Switchers remain controlled by their initializer key while it is held.")
                        let sensitivityBinding = Binding<Double>(
                            get: { Double(trackpadSwitcherSwipeSensitivity) },
                            set: { trackpadSwitcherSwipeSensitivity = CGFloat($0) }
                        )
                        SettingsSliderRow(
                            title: "Swipe Sensitivity",
                            value: sensitivityBinding,
                            range: Double(TrackpadSwipeDetector.sensitivityRange.lowerBound) ... Double(TrackpadSwipeDetector.sensitivityRange.upperBound),
                            step: 0.1
                        )
                        .settingsSearchTarget("gestures.trackpadSwitcherSwipeSensitivity")
                        .settingsAnnotation("Higher values open the switcher and change the selection with shorter swipes.")

                        Text("For directions that open the switcher, disable conflicting macOS gestures in System Settings > Trackpad > More Gestures.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
