
import Defaults
import SwiftUI

struct AppIconBadgeLayout {
    let height: CGFloat
    let width: CGFloat

    init(iconSize: CGFloat, scale: CGFloat, label: String) {
        let size = iconSize.isFinite ? max(0, iconSize) : 0
        let scale = scale.isFinite ? min(1.5, max(0.75, scale)) : 1
        height = size * 0.44 * scale
        width = min(size, max(height, height * (0.55 * CGFloat(min(label.count, 8)) + 0.4)))
    }

    static func normalizedLabel(_ label: String?) -> String? {
        guard let label else { return nil }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class AppIconBadgeStore: ObservableObject {
    private static var instance: AppIconBadgeStore?

    static var shared: AppIconBadgeStore {
        if let instance { return instance }
        let store = AppIconBadgeStore()
        instance = store
        return store
    }

    static func stopIfInitialized() {
        instance?.stop()
    }

    @Published private(set) var labels: [URL: String] = [:]
    private var consumers: [UUID: URL] = [:]
    private var refreshTask: Task<Void, Never>?
    private var generation = UUID()
    private var scanInFlight = false
    private var lastScanTime: TimeInterval = -.infinity
    private let queue = DispatchQueue(label: "com.dockdoor.app-icon-badges", qos: .utility)

    private init() {}

    func subscribe(_ id: UUID, bundleURL: URL) {
        consumers[id] = bundleURL.standardizedFileURL
        guard refreshTask == nil else { return }
        generation = UUID()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func unsubscribe(_ id: UUID) {
        consumers.removeValue(forKey: id)
        if consumers.isEmpty {
            stop()
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
        generation = UUID()
        consumers.removeAll()
        if !labels.isEmpty { labels = [:] }
    }

    private func refresh() {
        let now = ProcessInfo.processInfo.systemUptime
        guard !consumers.isEmpty, !scanInFlight,
              now - lastScanTime >= 1,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return }

        lastScanTime = now
        scanInFlight = true
        let token = generation
        let urls = Set(consumers.values)
        let pid = dock.processIdentifier
        queue.async { [weak self] in
            let snapshot = Self.readLabels(dockPID: pid, bundleURLs: urls)
            Task { @MainActor [weak self] in
                guard let self else { return }
                scanInFlight = false
                guard generation == token, !consumers.isEmpty, let snapshot else { return }
                let activeURLs = Set(consumers.values)
                let activeLabels = snapshot.filter { activeURLs.contains($0.key) }
                if labels != activeLabels { labels = activeLabels }
            }
        }
    }

    private nonisolated static func readLabels(dockPID: pid_t, bundleURLs: Set<URL>) -> [URL: String]? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.5
        let dock = AXUIElementCreateApplication(dockPID)

        func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.1)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value as? T
        }

        guard let children: [AXUIElement] = attribute(dock, kAXChildrenAttribute),
              let list = children.first(where: { child in
                  let role: String? = attribute(child, kAXRoleAttribute)
                  return role == kAXListRole
              }),
              let items: [AXUIElement] = attribute(list, kAXChildrenAttribute)
        else { return nil }

        var result: [URL: String] = [:]
        var remainingURLs = bundleURLs
        // The Dock exposes AXStatusLabel, but the public SDK does not declare its constant.
        let attributes = [kAXSubroleAttribute, kAXIsApplicationRunningAttribute, kAXURLAttribute, "AXStatusLabel"] as CFArray
        for item in items {
            if remainingURLs.isEmpty { break }
            guard ProcessInfo.processInfo.systemUptime < deadline else { return nil }
            AXUIElementSetMessagingTimeout(item, 0.1)
            var rawValues: CFArray?
            guard AXUIElementCopyMultipleAttributeValues(item, attributes, [], &rawValues) == .success,
                  let values = rawValues as? [Any], values.count == 4,
                  values[0] as? String == kAXApplicationDockItemSubrole,
                  values[1] as? Bool == true,
                  let url = (values[2] as? URL)?.standardizedFileURL,
                  remainingURLs.remove(url) != nil
            else { continue }
            if let label = AppIconBadgeLayout.normalizedLabel(values[3] as? String) {
                result[url] = label
            }
        }
        return result
    }
}

struct PreviewAppIcon: View {
    let icon: NSImage?
    let bundleURL: URL?
    let size: CGFloat
    let showBadge: Bool
    let badgeScale: CGFloat
    let mockPreviewActive: Bool

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "app.fill").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if showBadge {
                AppIconBadgeOverlay(
                    bundleURL: bundleURL?.standardizedFileURL,
                    iconSize: size,
                    scale: badgeScale,
                    mockPreviewActive: mockPreviewActive
                )
                .id(bundleURL)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct AppIconBadgeSurface: ViewModifier {
    func body(content: Content) -> some View {
        let shadowRadius = Defaults.Keys.previewShadowRadius.defaultValue
        content
            .background {
                Capsule().fill(Color(nsColor: .systemRed))
                    .shadow(
                        color: .black.opacity(Double(Defaults.Keys.previewShadowOpacity.defaultValue)),
                        radius: shadowRadius,
                        y: shadowRadius * 0.4
                    )
            }
    }
}

private struct AppIconBadgeOverlay: View {
    let bundleURL: URL?
    let iconSize: CGFloat
    let scale: CGFloat
    let mockPreviewActive: Bool

    @ObservedObject private var store = AppIconBadgeStore.shared
    @State private var subscriptionID = UUID()

    var body: some View {
        let label = mockPreviewActive ? "3" : bundleURL.flatMap { store.labels[$0] }
        ZStack(alignment: .topTrailing) {
            Color.clear
            if let label {
                let layout = AppIconBadgeLayout(iconSize: iconSize, scale: scale, label: label)
                Text(verbatim: label)
                    .font(.system(size: layout.height * 0.65, weight: .regular, design: .default))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, layout.height * 0.15)
                    .frame(width: layout.width, height: layout.height)
                    .modifier(AppIconBadgeSurface())
                    .accessibilityLabel(Text(String(localized: "App icon badge: \(label)")))
            }
        }
        .frame(width: iconSize, height: iconSize)
        .onAppear {
            if !mockPreviewActive, let bundleURL {
                store.subscribe(subscriptionID, bundleURL: bundleURL)
            }
        }
        .onDisappear {
            if !mockPreviewActive { store.unsubscribe(subscriptionID) }
        }
    }
}

struct SharedHoverAppTitle: View {
    let appName: String
    let appIcon: NSImage?
    let hoveringAppIcon: Bool
    let backgroundAppearance: BackgroundAppearance
    @Default(.showAppName) var showAppTitleData
    @Default(.showAppIconOnly) var showAppIconOnly
    @Default(.appNameStyle) var appNameStyle
    @AnimationsEnabled var showAnimations
    @Default(.gradientColorPalette) private var defaultGradientColorPalette

    var body: some View {
        if showAppTitleData {
            Group {
                switch appNameStyle {
                case .default:
                    HStack(alignment: .center) {
                        if let appIcon {
                            Image(nsImage: appIcon)
                                .resizable()
                                .scaledToFit()
                                .zIndex(1)
                                .frame(width: 24, height: 24)
                        } else { ProgressView().frame(width: 24, height: 24) }
                        hoverTitleLabelView()
                            .animation(nil, value: hoveringAppIcon)
                    }
                    .globalPadding(.top, 12)
                    .globalPadding(.leading, 20)
                    .animation(showAnimations ? .smooth(duration: 0.15) : nil, value: hoveringAppIcon)

                case .shadowed:
                    HStack(spacing: 2) {
                        if let appIcon {
                            Image(nsImage: appIcon)
                                .resizable()
                                .scaledToFit()
                                .zIndex(1)
                                .frame(width: 24, height: 24)
                        } else { ProgressView().frame(width: 24, height: 24) }
                        hoverTitleLabelView()
                            .animation(nil, value: hoveringAppIcon)
                    }
                    .padding(EdgeInsets(top: -11.5, leading: 15, bottom: -1.5, trailing: 1.5))
                    .animation(showAnimations ? .smooth(duration: 0.15) : nil, value: hoveringAppIcon)

                case .popover:
                    HStack {
                        Spacer()
                        HStack(alignment: .center, spacing: 2) {
                            if let appIcon {
                                Image(nsImage: appIcon)
                                    .resizable()
                                    .scaledToFit()
                                    .zIndex(1)
                                    .frame(width: 24, height: 24)
                            } else { ProgressView().frame(width: 24, height: 24) }
                            hoverTitleLabelView()
                                .animation(nil, value: hoveringAppIcon)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .dockStyle(backgroundAppearance: backgroundAppearance, cornerRadius: 10)
                        Spacer()
                    }
                    .offset(y: -30)
                    .animation(showAnimations ? .smooth(duration: 0.15) : nil, value: hoveringAppIcon)
                }
            }
            .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private func hoverTitleLabelView() -> some View {
        if !showAppIconOnly {
            let trimmedAppName = appName.trimmingCharacters(in: .whitespaces)
            let baseText = Text(trimmedAppName).font(.subheadline).fontWeight(.medium)
            let labelSize = measureString(trimmedAppName, fontSize: 14)
            let rainbowGradientColors: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .pink]
            let rainbowGradientHighlights: [Color] = [.white.opacity(0.45), .yellow.opacity(0.35), .pink.opacity(0.4)]

            Group {
                switch appNameStyle {
                case .shadowed:
                    if trimmedAppName == "DockDoor" {
                        FluidGradient(blobs: rainbowGradientColors, highlights: rainbowGradientHighlights, speed: 0.65, blur: 0.5)
                            .frame(width: labelSize.width, height: labelSize.height)
                            .mask(baseText)
                            .fontWeight(.medium)
                            .padding(.leading, 4)
                            .appHeaderTextShadow()
                            .background(
                                ZStack {
                                    MaterialBlurView(material: .hudWindow).mask(Ellipse().fill(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(1.0), Color.white.opacity(0.35)]), startPoint: .top, endPoint: .bottom))).blur(radius: 5)
                                }.frame(width: labelSize.width + 30)
                            )
                            .animation(showAnimations ? .easeInOut(duration: 0.2) : nil, value: trimmedAppName)
                    } else {
                        baseText.foregroundStyle(Color.primary).appHeaderTextShadow()
                            .background(
                                ZStack {
                                    MaterialBlurView(material: .hudWindow).mask(Ellipse().fill(LinearGradient(gradient: Gradient(colors: [Color.white.opacity(1.0), Color.white.opacity(0.35)]), startPoint: .top, endPoint: .bottom))).blur(radius: 5)
                                }.frame(width: labelSize.width + 30)
                            )
                            .animation(showAnimations ? .easeInOut(duration: 0.2) : nil, value: trimmedAppName)
                    }
                case .default, .popover:
                    if trimmedAppName == "DockDoor" {
                        FluidGradient(blobs: rainbowGradientColors, highlights: rainbowGradientHighlights, speed: 0.65, blur: 0.5)
                            .frame(width: labelSize.width, height: labelSize.height)
                            .mask(baseText)
                            .animation(showAnimations ? .easeInOut(duration: 0.2) : nil, value: trimmedAppName)
                    } else {
                        baseText.foregroundStyle(Color.primary)
                            .animation(showAnimations ? .easeInOut(duration: 0.2) : nil, value: trimmedAppName)
                    }
                }
            }
        }
    }
}
