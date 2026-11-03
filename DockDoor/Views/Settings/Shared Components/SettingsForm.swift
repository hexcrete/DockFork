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

struct SettingsButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26.0, *) {
            Button(configuration).buttonStyle(.glass)
        } else {
            Button(configuration).buttonStyle(.settings)
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

struct SettingsIllustratedToggle<Caption: View>: View {
    @Binding var isOn: Bool
    let title: LocalizedStringKey
    let imageName: String?
    @ViewBuilder var caption: Caption

    init(
        isOn: Binding<Bool>,
        title: LocalizedStringKey,
        imageName: String? = nil,
        @ViewBuilder caption: () -> Caption
    ) {
        _isOn = isOn
        self.title = title
        self.imageName = imageName
        self.caption = caption()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: $isOn) { Text(title) }

                caption
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }

            Spacer(minLength: 12)

            if let imageName {
                Image(imageName)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFill()
                    .frame(width: 280, height: 170)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}

extension SettingsIllustratedToggle where Caption == EmptyView {
    init(isOn: Binding<Bool>, title: LocalizedStringKey, imageName: String? = nil) {
        self.init(isOn: isOn, title: title, imageName: imageName) { EmptyView() }
    }
}
