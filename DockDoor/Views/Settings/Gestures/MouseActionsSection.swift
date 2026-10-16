import Defaults
import SwiftUI

struct MouseActionsSection: View {
    @Default(.middleClickAction) var middleClickAction
    @Default(.enableWindowDragTiling) private var enableWindowDragTiling

    var body: some View {
        SettingsGroup(header: "Mouse Actions") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "computermouse.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        Text("Middle Click")
                            .frame(width: 80, alignment: .leading)
                    }

                    Picker("", selection: $middleClickAction) {
                        ForEach(WindowAction.assignablePreviewActions, id: \.self) { windowAction in
                            HStack(spacing: 6) {
                                Image(systemName: windowAction.iconName)
                                Text(windowAction.localizedName)
                            }
                            .tag(windowAction)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .settingsSearchTarget("gestures.middleClick")
                }

                Text("Action performed when middle-clicking on a window preview.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Enable dragging windows together to tile them", isOn: $enableWindowDragTiling)
                    .settingsSearchTarget("gestures.enableWindowDragTiling")
                Text("Drag a window preview onto another preview to tile them on the target window's Desktop. Checked windows are included in selection order.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
