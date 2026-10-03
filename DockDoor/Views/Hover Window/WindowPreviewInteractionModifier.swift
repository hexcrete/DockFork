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
    let pointerHoverActive: Bool
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
                isActive: pointerHoverActive,
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
            .previewContextMenu(
                windowInfo: windowInfo,
                handleWindowAction: handleWindowAction,
                dismissPreviews: onTap
            )
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
        pointerHoverActive: Bool,
        handleWindowAction: @escaping (WindowAction) -> Void,
        onTap: (() -> Void)?
    ) -> some View {
        modifier(WindowPreviewInteractionModifier(
            windowInfo: windowInfo,
            windowSwitcherActive: windowSwitcherActive,
            dockPosition: dockPosition,
            useCompactMode: useCompactMode,
            pointerHoverActive: pointerHoverActive,
            handleWindowAction: handleWindowAction,
            onTap: onTap
        ))
    }
}

@MainActor
final class PreviewContextMenuController: NSObject {
    static let shared = PreviewContextMenuController()

    private final class ActionRequest: NSObject {
        let action: WindowAction
        let handler: (WindowAction) -> Void

        init(action: WindowAction, handler: @escaping (WindowAction) -> Void) {
            self.action = action
            self.handler = handler
        }
    }

    private var activeMenu: NSMenu?

    func present(
        for window: WindowInfo,
        event: NSEvent,
        sourceView: NSView,
        handleWindowAction: @escaping (WindowAction) -> Void,
        dismissPreviews: (() -> Void)?
    ) {
        let menu = makeMenu(
            for: window,
            handleWindowAction: handleWindowAction,
            dismissPreviews: dismissPreviews
        )
        guard !menu.items.isEmpty else { return }

        activeMenu?.cancelTracking()
        activeMenu = menu
        NSMenu.popUpContextMenu(menu, with: event, for: sourceView)
        if activeMenu === menu {
            activeMenu = nil
        }
    }

    func dismiss() {
        activeMenu?.cancelTracking()
        activeMenu = nil
    }

    private func makeMenu(
        for window: WindowInfo,
        handleWindowAction: @escaping (WindowAction) -> Void,
        dismissPreviews: (() -> Void)?
    ) -> NSMenu {
        let menu = NSMenu()
        let groups = WindowAction.availableGroups(for: window)

        if let actions = groups.first(where: { $0.id == .window })?.actions {
            add(actions, for: window, to: menu, handler: handleWindowAction)
        }

        if !window.isWindowlessApp {
            addSeparatorIfNeeded(to: menu)
            if let actions = groups.first(where: { $0.id == .arrange })?.actions {
                let arrangeItem = NSMenuItem(
                    title: WindowAction.Group.arrange.localizedName,
                    action: nil,
                    keyEquivalent: ""
                )
                arrangeItem.image = NSImage(
                    systemSymbolName: "rectangle.split.2x2",
                    accessibilityDescription: nil
                )
                let arrangeMenu = NSMenu(title: WindowAction.Group.arrange.localizedName)
                add(actions, for: window, to: arrangeMenu, handler: handleWindowAction)
                arrangeItem.submenu = arrangeMenu
                menu.addItem(arrangeItem)
            }

            let moveItem = NSMenuItem(
                title: String(localized: "Move to Space", comment: "Space destination submenu title"),
                action: nil,
                keyEquivalent: ""
            )
            moveItem.image = NSImage(
                systemSymbolName: "rectangle.on.rectangle",
                accessibilityDescription: nil
            )
            moveItem.submenu = SpaceMoveMenuController.shared.makeMenu(
                for: window,
                dismissPreviews: dismissPreviews
            )
            menu.addItem(moveItem)
        }

        if let actions = groups.first(where: { $0.id == .app })?.actions {
            addSeparatorIfNeeded(to: menu)
            add(actions, for: window, to: menu, handler: handleWindowAction)
        }

        return menu
    }

    private func add(
        _ actions: [WindowAction],
        for window: WindowInfo,
        to menu: NSMenu,
        handler: @escaping (WindowAction) -> Void
    ) {
        for action in actions {
            let item = NSMenuItem(
                title: action.menuTitle(for: window),
                action: #selector(performAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = ActionRequest(action: action, handler: handler)
            item.image = NSImage(
                systemSymbolName: action.menuIcon(for: window),
                accessibilityDescription: nil
            )
            menu.addItem(item)
        }
    }

    private func addSeparatorIfNeeded(to menu: NSMenu) {
        guard let lastItem = menu.items.last, !lastItem.isSeparatorItem else { return }
        menu.addItem(.separator())
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? ActionRequest else { return }
        request.handler(request.action)
    }
}

private struct PreviewContextMenuCapture: NSViewRepresentable {
    let windowInfo: WindowInfo
    let handleWindowAction: (WindowAction) -> Void
    let dismissPreviews: (() -> Void)?

    func makeNSView(context: Context) -> ContextMenuView {
        ContextMenuView()
    }

    func updateNSView(_ nsView: ContextMenuView, context: Context) {
        nsView.windowInfo = windowInfo
        nsView.handleWindowAction = handleWindowAction
        nsView.dismissPreviews = dismissPreviews
    }

    final class ContextMenuView: NSView {
        var windowInfo: WindowInfo?
        var handleWindowAction: ((WindowAction) -> Void)?
        var dismissPreviews: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point), NSApp.currentEvent?.type == .rightMouseDown else { return nil }
            return self
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let windowInfo, let handleWindowAction else { return }
            PreviewContextMenuController.shared.present(
                for: windowInfo,
                event: event,
                sourceView: self,
                handleWindowAction: handleWindowAction,
                dismissPreviews: dismissPreviews
            )
        }
    }
}

extension View {
    func previewContextMenu(
        windowInfo: WindowInfo,
        handleWindowAction: @escaping (WindowAction) -> Void,
        dismissPreviews: (() -> Void)? = nil
    ) -> some View {
        overlay {
            PreviewContextMenuCapture(
                windowInfo: windowInfo,
                handleWindowAction: handleWindowAction,
                dismissPreviews: dismissPreviews
            )
        }
    }
}
