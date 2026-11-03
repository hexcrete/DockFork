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
    var valueText: ((T) -> String)?
    var onEditingChanged: ((Bool) -> Void)?

    private var effectiveDecimals: Int {
        guard decimals == 0, Double(step) < 1 else { return decimals }
        return Double(step) < 0.1 ? 2 : 1
    }

    private var displayValue: String {
        if let valueText {
            return valueText(value)
        }
        return String(format: "%.\(effectiveDecimals)f", Double(value)) + unit
    }

    private var snappedValue: Binding<T> {
        Binding {
            value
        } set: { newValue in
            let stepSize = T(step)
            guard stepSize > 0 else { return value = newValue }
            let snapped = range.lowerBound + ((newValue - range.lowerBound) / stepSize).rounded() * stepSize
            value = min(max(snapped, range.lowerBound), range.upperBound)
        }
    }

    private var isModified: Bool {
        guard let defaultValue else { return false }
        return abs(Double(value) - Double(defaultValue)) > 0.01
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                Slider(value: snappedValue, in: range) { isEditing in
                    onEditingChanged?(isEditing)
                }
                .labelsHidden()
                .frame(width: 180)

                Text(displayValue)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 72, alignment: .trailing)

                SettingsResetButton(isModified: isModified) {
                    guard let defaultValue else { return }
                    withAnimation(.easeInOut(duration: 0.15)) {
                        value = defaultValue
                    }
                }
                .frame(width: 16)
            }
        } label: {
            Text(title)
        }
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

func sliderSetting<T: BinaryFloatingPoint>(
    title: LocalizedStringKey,
    value: Binding<T>,
    range: ClosedRange<T>,
    step: T.Stride,
    unit: LocalizedStringKey,
    formatter: NumberFormatter = NumberFormatter.defaultFormatter,
    onEditingChanged: ((Bool) -> Void)? = nil
) -> some View where T.Stride: BinaryFloatingPoint {
    VStack(alignment: .leading, spacing: 5) {
        Text(title)
            .font(.body)
        HStack {
            Slider(
                value: value,
                in: range,
                step: step,
                onEditingChanged: { isEditing in
                    onEditingChanged?(isEditing)
                }
            )
            TextField("", value: value, formatter: formatter)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 50)
            Text(unit)
                .font(.footnote)
        }
    }
}
