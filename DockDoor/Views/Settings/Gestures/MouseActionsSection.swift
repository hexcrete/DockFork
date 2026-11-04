import Defaults
import SwiftUI

struct MouseActionsSection: View {
    @Default(.middleClickAction) var middleClickAction

    @Default(.enableWindowDragTiling) private var enableWindowDragTiling

    var body: some View {
        SettingsSection("Mouse Actions") {
            Picker("Middle Click", selection: $middleClickAction) {
                ForEach(WindowAction.assignablePreviewActions, id: \.self) { windowAction in
                    Label(windowAction.localizedName, systemImage: windowAction.iconName)
                        .tag(windowAction)
                }
            }
            .settingsSearchTarget("gestures.middleClick")
            .settingsAnnotation("Action performed when middle-clicking on a window preview.")
            Toggle("Enable dragging windows together to tile them", isOn: $enableWindowDragTiling)
                .settingsSearchTarget("gestures.enableWindowDragTiling")
                .settingsAnnotation("Drag a window preview onto another preview to tile them on the target window's Desktop. Checked windows are included in selection order.")
        }
    }
}
