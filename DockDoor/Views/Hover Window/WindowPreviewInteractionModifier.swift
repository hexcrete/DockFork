import Defaults
import SwiftUI
import UniformTypeIdentifiers

private struct ExternalDragSpringLoadingModifier: ViewModifier {
    let windowInfo: WindowInfo
    let index: Int
    let uniformCardRadius: Bool
    let paddingMultiplier: CGFloat
    let windowSwitcherActive: Bool
    let keepPreviewOnHoverActivation: Bool
    let handleWindowAction: (WindowAction) -> Void
    let onTap: (() -> Void)?
    let onDragHoverIndexChange: ((Int?) -> Void)?

    @State private var isTargeted = false
    @State private var springLoadTask: Task<Void, Never>?

    private var windowIdentity: String {
        "\(windowInfo.app.processIdentifier)-\(windowInfo.id)"
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(
                        cornerRadius: CardRadius.previewCard(
                            uniform: uniformCardRadius,
                            paddingMultiplier: paddingMultiplier
                        )
                    )
                    .fill(Color(nsColor: .controlAccentColor).opacity(0.3))
                    .padding(-CardRadius.innerPadding)
                    .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.item], isTargeted: $isTargeted) { _ in
                guard isTargeted, !windowInfo.isWindowlessApp else { return false }
                cancelSpringLoading()
                performReleaseFallback()
                return true
            }
            .onChange(of: isTargeted) { isOver in
                if isOver {
                    beginSpringLoading()
                } else {
                    cancelSpringLoading()
                }
            }
            .onChange(of: windowIdentity) { _ in
                cancelSpringLoading()
                if isTargeted {
                    beginSpringLoading()
                }
            }
            .onDisappear {
                cancelSpringLoading()
            }
    }

    private func beginSpringLoading() {
        guard Defaults[.enableSpringLoading], !windowInfo.isWindowlessApp else { return }

        springLoadTask?.cancel()
        if windowSwitcherActive {
            onDragHoverIndexChange?(index)
        }

        springLoadTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(effectiveSpringLoadingDelay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled, isTargeted else { return }

            SharedPreviewWindowCoordinator.activeInstance?.restoreDockAutoHideState()
            guard WindowUtil.springLoadWindow(windowInfo) else {
                NSSound.beep()
                cancelSpringLoading()
                return
            }

            springLoadTask = nil
            onTap?()
        }
    }

    private var effectiveSpringLoadingDelay: TimeInterval {
        let fallback = TimeInterval(Defaults.Keys.springLoadingDelay.defaultValue)
        let delay: TimeInterval = if Defaults[.useSystemSpringLoadingSpeed] {
            // AppKit does not expose this preference through a public API.
            (UserDefaults.standard.object(forKey: "com.apple.springing.delay") as? NSNumber)?.doubleValue ?? fallback
        } else {
            TimeInterval(Defaults[.springLoadingDelay])
        }

        return delay.isFinite && delay > 0 && delay <= 60 ? delay : fallback
    }

    private func performReleaseFallback() {
        SharedPreviewWindowCoordinator.activeInstance?.restoreDockAutoHideState()
        if windowInfo.isMinimized {
            handleWindowAction(.minimize)
        } else if windowInfo.isEffectivelyHiddenForUI {
            handleWindowAction(.hide)
        } else if windowInfo.bringToFront(), !keepPreviewOnHoverActivation {
            onTap?()
        }
    }

    private func cancelSpringLoading() {
        springLoadTask?.cancel()
        springLoadTask = nil
    }
}

/// Shared interaction modifier for window preview views (both standard and compact)
/// Provides: middle click, trackpad gestures, context menu, and tap handling
struct WindowPreviewInteractionModifier: ViewModifier {
    let windowInfo: WindowInfo
    let windowSwitcherActive: Bool
    let dockPosition: DockPosition
    let useCompactMode: Bool
    let handleWindowAction: (WindowAction) -> Void
    let onTap: (() -> Void)?

    // Middle click
    @Default(.middleClickAction) private var middleClickAction

    // Dock Preview Gestures
    @Default(.enableDockPreviewGestures) private var enableDockPreviewGestures
    @Default(.dockSwipeTowardsDockAction) private var dockSwipeTowardsDockAction
    @Default(.dockSwipeAwayFromDockAction) private var dockSwipeAwayFromDockAction

    @State private var suppressTap = false

    func body(content: Content) -> some View {
        content
            .onMiddleClick {
                if middleClickAction != .none {
                    performAction(middleClickAction)
                }
            }
            .onTrackpadSwipe(
                onScrollingChanged: { scrolling in suppressTap = scrolling },
                onSwipeUp: { handleSwipe(.up) },
                onSwipeDown: { handleSwipe(.down) },
                onSwipeLeft: { handleSwipe(.left) },
                onSwipeRight: { handleSwipe(.right) }
            )
            .onTapGesture {
                guard !suppressTap else { return }
                handleWindowTap()
            }
            .contextMenu {
                WindowActionsMenuContent(windowInfo: windowInfo, handleWindowAction: handleWindowAction)
            }
    }

    // MARK: - Swipe Handling

    private enum SwipeDirection {
        case up, down, left, right
    }

    private func handleSwipe(_ direction: SwipeDirection) {
        guard !windowSwitcherActive else { return }
        guard enableDockPreviewGestures else { return }
        // In compact mode, use horizontal gestures (left/right) since vertical is for scrolling
        if useCompactMode {
            switch direction {
            case .left:
                performAction(dockSwipeTowardsDockAction)
            case .right:
                performAction(dockSwipeAwayFromDockAction)
            case .up, .down:
                break
            }
        } else {
            if isSwipeTowardsDock(direction) {
                performAction(dockSwipeTowardsDockAction)
            } else if isSwipeAwayFromDock(direction) {
                performAction(dockSwipeAwayFromDockAction)
            }
        }
    }

    private func isSwipeTowardsDock(_ direction: SwipeDirection) -> Bool {
        switch dockPosition {
        case .bottom: direction == .down
        case .top: direction == .up
        case .left: direction == .left
        case .right: direction == .right
        case .cmdTab, .cli, .unknown: direction == .down
        }
    }

    private func isSwipeAwayFromDock(_ direction: SwipeDirection) -> Bool {
        switch dockPosition {
        case .bottom: direction == .up
        case .top: direction == .down
        case .left: direction == .right
        case .right: direction == .left
        case .cmdTab, .cli, .unknown: direction == .up
        }
    }

    private func performAction(_ action: WindowAction) {
        guard action != .none else { return }
        handleWindowAction(action)
    }

    // MARK: - Tap Handling

    private func handleWindowTap() {
        // Avoid activating the target while the temporarily pinned Dock reduces the usable screen area.
        SharedPreviewWindowCoordinator.activeInstance?.restoreDockAutoHideState()

        if NSEvent.modifierFlags.contains(.shift) {
            WindowUtil.activateAndOpenNewWindow(app: windowInfo.app)
            onTap?()
            return
        }

        if windowInfo.isWindowlessApp {
            WindowUtil.activateWindowlessApp(app: windowInfo.app)
            onTap?()
        } else if windowInfo.isMinimized {
            handleWindowAction(.minimize)
        } else if windowInfo.isEffectivelyHiddenForUI {
            handleWindowAction(.hide)
        } else {
            if windowInfo.bringToFront(), windowSwitcherActive {
                windowInfo.warpMouseToCenterIfNeeded()
            }
            onTap?()
        }
    }
}

extension View {
    func externalDragSpringLoading(
        windowInfo: WindowInfo,
        index: Int,
        uniformCardRadius: Bool,
        appearance: PreviewAppearanceSettings,
        windowSwitcherActive: Bool,
        handleWindowAction: @escaping (WindowAction) -> Void,
        onTap: (() -> Void)?,
        onDragHoverIndexChange: ((Int?) -> Void)?
    ) -> some View {
        modifier(ExternalDragSpringLoadingModifier(
            windowInfo: windowInfo,
            index: index,
            uniformCardRadius: uniformCardRadius,
            paddingMultiplier: appearance.globalPaddingMultiplier,
            windowSwitcherActive: windowSwitcherActive,
            keepPreviewOnHoverActivation: appearance.keepPreviewOnHoverActivation,
            handleWindowAction: handleWindowAction,
            onTap: onTap,
            onDragHoverIndexChange: onDragHoverIndexChange
        ))
    }

    /// Applies shared window preview interactions (middle click, gestures, context menu, tap)
    func windowPreviewInteractions(
        windowInfo: WindowInfo,
        windowSwitcherActive: Bool,
        dockPosition: DockPosition,
        useCompactMode: Bool = false,
        handleWindowAction: @escaping (WindowAction) -> Void,
        onTap: (() -> Void)?
    ) -> some View {
        modifier(WindowPreviewInteractionModifier(
            windowInfo: windowInfo,
            windowSwitcherActive: windowSwitcherActive,
            dockPosition: dockPosition,
            useCompactMode: useCompactMode,
            handleWindowAction: handleWindowAction,
            onTap: onTap
        ))
    }
}

struct WindowActionsMenuContent: View {
    let windowInfo: WindowInfo
    let handleWindowAction: (WindowAction) -> Void

    var body: some View {
        let groups = WindowAction.availableGroups(for: windowInfo)
        ForEach(groups) { entry in
            if entry.id != groups.first?.id {
                Divider()
            }
            if entry.id == .arrange {
                Menu {
                    actionButtons(entry.actions)
                } label: {
                    Label(entry.id.localizedName, systemImage: "rectangle.split.2x2")
                }
            } else {
                actionButtons(entry.actions)
            }
        }
    }

    private func actionButtons(_ actions: [WindowAction]) -> some View {
        ForEach(actions, id: \.self) { action in
            Button(role: action == .quit ? .destructive : nil, action: { handleWindowAction(action) }) {
                Label(action.menuTitle(for: windowInfo), systemImage: action.menuIcon(for: windowInfo))
            }
        }
    }
}
