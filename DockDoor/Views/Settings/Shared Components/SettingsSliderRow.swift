import Defaults
import SwiftUI

struct SettingsSliderRow<T: BinaryFloatingPoint>: View where T.Stride: BinaryFloatingPoint {
    let title: LocalizedStringKey
    @Binding var value: T
    let range: ClosedRange<T>
    var defaultValue: T?
    var unit = ""
    var step: T.Stride = 1
    var decimals = 0
    var onEditingChanged: ((Bool) -> Void)?

    private var displayValue: String {
        if decimals > 0 {
            return String(format: "%.\(decimals)f", Double(value))
        }
        return "\(Int(value))"
    }

    private var isModified: Bool {
        guard let defaultValue else { return false }
        return abs(Double(value) - Double(defaultValue)) > 0.01
    }

    var body: some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.body)
                .frame(width: 180, alignment: .leading)

            Slider(value: $value, in: range, step: step) { isEditing in
                onEditingChanged?(isEditing)
            }
            .controlSize(.small)

            HStack(spacing: 4) {
                Text(displayValue + unit)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)

                if let defaultValue {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            value = defaultValue
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isModified ? 1 : 0)
                    .frame(width: 20)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 40)
    }
}

struct PreviewFocusFadeSettings: View {
    let mode: PreviewFocusFadeMode
    @Default private var enabled: Bool
    @Default private var delay: CGFloat
    @Default private var duration: CGFloat
    @Default private var opacity: CGFloat
    @Default private var hoverAction: PreviewHoverAction

    init(mode: PreviewFocusFadeMode) {
        self.mode = mode
        _enabled = Default(mode.enabledKey)
        _delay = Default(mode.delayKey)
        _duration = Default(mode.durationKey)
        _opacity = Default(mode.opacityKey)
        _hoverAction = Default(mode.hoverActionKey)
    }

    var body: some View {
        if hoverAction == .previewFullSize {
            Toggle(mode.toggleTitle, isOn: $enabled)
                .settingsSearchTarget(mode.searchPrefix + ".focusFade")
            Text(mode.helperText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)
            if enabled {
                sliderSetting(title: LocalizedStringKey(mode.delayTitle), value: $delay, range: 0 ... 5, step: 0.1, unit: "seconds", formatter: NumberFormatter.oneDecimalFormatter)
                    .settingsSearchTarget(mode.searchPrefix + ".focusFadeDelay")
                sliderSetting(title: "Fade Out Duration", value: $duration, range: 0 ... 5, step: 0.1, unit: "seconds", formatter: NumberFormatter.oneDecimalFormatter)
                    .settingsSearchTarget(mode.searchPrefix + ".focusFadeDuration")
                sliderSetting(title: "Target Minimum Opacity", value: $opacity, range: 0 ... 0.5, step: 0.05, unit: "", formatter: NumberFormatter.percentFormatter)
                    .settingsSearchTarget(mode.searchPrefix + ".focusFadeOpacity")
            }
        }
    }
}
