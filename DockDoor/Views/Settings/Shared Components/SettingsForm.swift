import SwiftUI

struct SettingsFormView<Content: View, Header: View>: View {
    @Environment(\.settingsScrollTarget) private var scrollTarget
    let content: Content
    let header: Header

    init(@ViewBuilder content: () -> Content, @ViewBuilder pinnedHeader: () -> Header) {
        self.content = content()
        header = pinnedHeader()
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                content
            }
            .formStyle(.grouped)
            .modifier(SoftTopScrollEdge())
            .safeAreaInset(edge: .top, spacing: 0) {
                if Header.self != EmptyView.self {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipped()
                        .contentShape(Rectangle())
                }
            }
            .onChange(of: scrollTarget) { target in
                guard let target else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
            .onAppear {
                guard let target = scrollTarget else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
        .frame(minWidth: 650, idealWidth: 700, minHeight: 650)
    }
}

extension SettingsFormView where Header == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, pinnedHeader: { EmptyView() })
    }
}

private struct SoftTopScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: LocalizedStringKey
    var footer: LocalizedStringKey?
    @ViewBuilder let content: Content

    init(_ title: LocalizedStringKey, footer: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            Text(title)
        } footer: {
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SettingsDependentRows<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Group { content }
            .padding(.leading, 20)
    }
}

struct SettingsKeyCaptureControls: View {
    @Binding var keyCode: UInt16
    let defaultKeyCode: UInt16
    var captureModifiers = false
    var modifierLabel: String?
    var conflict: AlternateSwitcherShortcutConflict?
    var emptyLabel: String?
    var forceEmptyLabel = false
    var treatKeyCodeZeroAsEmpty = true

    var body: some View {
        HStack(spacing: 8) {
            if let modifierLabel {
                Text(modifierLabel).foregroundStyle(.secondary)
            }
            KeyCaptureButton(keyCode: $keyCode, emptyLabel: emptyLabel, forceEmptyLabel: forceEmptyLabel,
                             treatKeyCodeZeroAsEmpty: treatKeyCodeZeroAsEmpty, captureModifiers: captureModifiers)
            SettingsShortcutConflictWarning(conflict: conflict)
            SettingsResetButton(isModified: keyCode != defaultKeyCode) { keyCode = defaultKeyCode }
        }
    }
}

struct SettingsShortcutRow<Trigger: View, Options: View>: View {
    @ViewBuilder let trigger: Trigger
    @ViewBuilder let options: Options
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            trigger
            Spacer(minLength: 8)
            options
            SettingsShortcutRemoveButton(action: onRemove)
        }
    }
}

struct SettingsShortcutModePicker: View {
    @Binding var selection: SwitcherInvocationMode

    var body: some View {
        Picker("Mode", selection: $selection) {
            ForEach(SwitcherInvocationMode.sortedCases) { mode in
                Text(mode.localizedName).tag(mode)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(minWidth: 44, maxWidth: 260, alignment: .trailing)
        .layoutPriority(-1)
        .help(selection.localizedName)
        .accessibilityValue(selection.localizedName)
    }
}

struct SettingsShortcutConflictWarning: View {
    let conflict: AlternateSwitcherShortcutConflict?

    var body: some View {
        if let conflict {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help(conflict.localizedMessage)
                .accessibilityLabel(conflict.localizedMessage)
        }
    }
}

struct SettingsShortcutRemoveButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Remove shortcut")
        .accessibilityLabel("Remove shortcut")
    }
}

struct SettingsShortcutAddButton: View {
    let title: LocalizedStringKey
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label(title, systemImage: "plus") }
            .buttonStyle(.settings)
            .disabled(!isEnabled)
    }
}

struct SettingsShortcutListFooter: View {
    let title: LocalizedStringKey
    let canAdd: Bool
    let onAdd: () -> Void
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SettingsShortcutAddButton(title: title, isEnabled: canAdd, action: onAdd)
            Spacer(minLength: 0)
            Button("Reset to Defaults", action: onReset).buttonStyle(.settings)
        }
    }
}

struct SettingsButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            Button(configuration).buttonStyle(.glass)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}

extension PrimitiveButtonStyle where Self == SettingsButtonStyle {
    static var settings: SettingsButtonStyle {
        SettingsButtonStyle()
    }
}

struct SettingsResetButton: View {
    let isModified: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Reset to default")
        .accessibilityLabel("Reset to default")
        .opacity(isModified ? 1 : 0)
        .disabled(!isModified)
    }
}
