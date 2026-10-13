import Carbon.HIToolbox.Events
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
    @State private var releaseActivationTask: Task<Void, Never>?

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
                releaseActivationTask?.cancel()
                releaseActivationTask = nil
                if isTargeted {
                    beginSpringLoading()
                }
            }
            .onDisappear {
                cancelSpringLoading()
                releaseActivationTask?.cancel()
                releaseActivationTask = nil
            }
    }

    private func beginSpringLoading() {
        guard Defaults[.enableSpringLoading], !windowInfo.isWindowlessApp else { return }

        releaseActivationTask?.cancel()
        releaseActivationTask = nil
        springLoadTask?.cancel()
        if windowSwitcherActive {
            onDragHoverIndexChange?(index)
        }

        let coordinator = SharedPreviewWindowCoordinator.activeInstance
        let sessionID = coordinator?.windowSwitcherCoordinator.pointerInteractionSessionID
        springLoadTask = Task { @MainActor [weak coordinator] in
            do {
                try await Task.sleep(nanoseconds: UInt64(effectiveSpringLoadingDelay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled, isTargeted else { return }

            SharedPreviewWindowCoordinator.activeInstance?.restoreDockAutoHideState()
            let activated = await WindowUtil.springLoadWindow(windowInfo)
            guard !Task.isCancelled, isTargeted,
                  coordinator?.windowSwitcherCoordinator.pointerInteractionSessionID == sessionID,
                  coordinator?.isVisible != false
            else { return }
            guard activated else {
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
        releaseActivationTask?.cancel()
        releaseActivationTask = nil
        SharedPreviewWindowCoordinator.activeInstance?.restoreDockAutoHideState()
        if windowInfo.isMinimized {
            handleWindowAction(.minimize)
        } else if windowInfo.isEffectivelyHiddenForUI {
            handleWindowAction(.hide)
        } else {
            let coordinator = SharedPreviewWindowCoordinator.activeInstance
            let sessionID = coordinator?.windowSwitcherCoordinator.pointerInteractionSessionID
            releaseActivationTask = Task { @MainActor [weak coordinator] in
                let activated = await windowInfo.bringToFrontConfirmed()
                guard !Task.isCancelled,
                      coordinator?.windowSwitcherCoordinator.pointerInteractionSessionID == sessionID,
                      coordinator?.isVisible != false
                else { return }
                releaseActivationTask = nil
                if activated, !keepPreviewOnHoverActivation { onTap?() }
            }
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
    @State private var activationTask: Task<Void, Never>?

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
            .onChange(of: windowInfo.id) { _ in
                activationTask?.cancel()
                activationTask = nil
            }
            .onChange(of: windowInfo.app.processIdentifier) { _ in
                activationTask?.cancel()
                activationTask = nil
            }
            .onDisappear {
                activationTask?.cancel()
                activationTask = nil
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
        if Defaults[.enableMultiWindowSelection],
           !windowInfo.isWindowlessApp,
           NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           SharedPreviewWindowCoordinator.activeInstance?.permitsCommandClickSelection == true
        {
            performAction(.toggleWindowSelection)
            return
        }
        activationTask?.cancel()
        activationTask = nil
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
            let coordinator = SharedPreviewWindowCoordinator.activeInstance
            let sessionID = coordinator?.windowSwitcherCoordinator.pointerInteractionSessionID
            activationTask = Task { @MainActor [weak coordinator] in
                let activated = await windowInfo.bringToFrontConfirmed()
                guard !Task.isCancelled,
                      coordinator?.windowSwitcherCoordinator.pointerInteractionSessionID == sessionID,
                      coordinator?.isVisible != false
                else { return }
                activationTask = nil
                if activated, windowSwitcherActive { windowInfo.warpMouseToCenterIfNeeded() }
                onTap?()
            }
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
final class WindowActionMenuBuilder: NSObject {
    static let shared = WindowActionMenuBuilder()

    final class ActionRequest: NSObject {
        let action: WindowAction
        let handler: (WindowAction) -> Void

        init(action: WindowAction, handler: @escaping (WindowAction) -> Void) {
            self.action = action
            self.handler = handler
        }
    }

    func makeMenu(
        for window: WindowInfo,
        shortcutKeybind: UserKeyBind? = nil,
        showShortcutHints: Bool,
        handleWindowAction: @escaping (WindowAction) -> Void,
        dismissPreviews: (() -> Void)? = nil
    ) -> (menu: NSMenu, shortcuts: [UInt16: WindowAction]) {
        let keybind = shortcutKeybind ?? Defaults[.UserKeybind]
        var shortcutByAction: [WindowAction: CmdShortcut] = [:]
        if showShortcutHints {
            let shortcuts = WindowSwitcherShortcutResolver.resolvedPreviewShortcuts(
                Defaults[.cmdShortcuts],
                previewKeybind: keybind,
                mainKeybind: SharedPreviewWindowCoordinator.activeInstance?.effectivePreviewShortcutKeybind(forSpaces: true)
                    ?? Defaults[.UserKeybind]
            )
            for shortcut in shortcuts where shortcutByAction[shortcut.action] == nil {
                shortcutByAction[shortcut.action] = shortcut
            }
        }
        var displayedShortcuts: [UInt16: WindowAction] = [:]
        let menu = buildMenu(
            for: window,
            shortcutKeybind: keybind,
            showShortcutHints: showShortcutHints,
            shortcutByAction: shortcutByAction,
            displayedShortcuts: &displayedShortcuts,
            handleWindowAction: handleWindowAction,
            dismissPreviews: dismissPreviews
        )
        return (menu, displayedShortcuts)
    }

    private func buildMenu(
        for window: WindowInfo,
        shortcutKeybind: UserKeyBind,
        showShortcutHints: Bool,
        shortcutByAction: [WindowAction: CmdShortcut],
        displayedShortcuts: inout [UInt16: WindowAction],
        handleWindowAction: @escaping (WindowAction) -> Void,
        dismissPreviews: (() -> Void)?
    ) -> NSMenu {
        let menu = NSMenu()
        let batchTargets = showShortcutHints ? SharedPreviewWindowCoordinator.activeInstance?.windowSwitcherCoordinator.checkedActionTargets(for: window) : nil
        let groups = WindowAction.availableGroups(for: window, batchTargets: batchTargets, includeSelectionActions: showShortcutHints)

        if let actions = groups.first(where: { $0.id == .window })?.actions {
            add(
                actions,
                for: window,
                batchTargets: batchTargets,
                to: menu,
                shortcutKeybind: shortcutKeybind,
                shortcutByAction: shortcutByAction,
                displayedShortcuts: &displayedShortcuts,
                handler: handleWindowAction
            )
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
                forceImageVisibility(for: arrangeItem)
                let arrangeMenu = NSMenu(title: WindowAction.Group.arrange.localizedName)
                add(
                    actions,
                    for: window,
                    batchTargets: batchTargets,
                    to: arrangeMenu,
                    shortcutKeybind: shortcutKeybind,
                    shortcutByAction: shortcutByAction,
                    displayedShortcuts: &displayedShortcuts,
                    handler: handleWindowAction
                )
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
            forceImageVisibility(for: moveItem)
            moveItem.submenu = SpaceMoveMenuController.shared.makeMenu(
                for: window,
                dismissPreviews: dismissPreviews,
                showShortcutHints: showShortcutHints
            )
            menu.addItem(moveItem)
        }

        if let actions = groups.first(where: { $0.id == .app })?.actions {
            addSeparatorIfNeeded(to: menu)
            add(
                actions,
                for: window,
                batchTargets: batchTargets,
                to: menu,
                shortcutKeybind: shortcutKeybind,
                shortcutByAction: shortcutByAction,
                displayedShortcuts: &displayedShortcuts,
                handler: handleWindowAction
            )
        }

        return menu
    }

    private func add(
        _ actions: [WindowAction],
        for window: WindowInfo,
        batchTargets: [WindowInfo]?,
        to menu: NSMenu,
        shortcutKeybind: UserKeyBind,
        shortcutByAction: [WindowAction: CmdShortcut],
        displayedShortcuts: inout [UInt16: WindowAction],
        handler: @escaping (WindowAction) -> Void
    ) {
        for action in actions {
            let item = NSMenuItem(
                title: action.menuTitle(for: window, batchTargets: batchTargets),
                action: #selector(performAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = ActionRequest(action: action, handler: handler)
            item.image = NSImage(
                systemSymbolName: action.menuIcon(for: window, batchTargets: batchTargets),
                accessibilityDescription: nil
            )
            forceImageVisibility(for: item)
            if let shortcut = shortcutByAction[action],
               let keyEquivalent = KeyboardLabel.menuKeyEquivalent(for: shortcut.keyCode)
            {
                item.keyEquivalent = keyEquivalent
                item.keyEquivalentModifierMask = WindowSwitcherShortcutResolver.appKitModifierMask(for: shortcutKeybind)
                displayedShortcuts[shortcut.keyCode] = action
            }
            if action == .quit {
                item.attributedTitle = NSAttributedString(
                    string: item.title,
                    attributes: [.foregroundColor: NSColor.systemRed]
                )
                item.image = item.image?.tint(color: .systemRed)
                item.image?.isTemplate = false
            }
            menu.addItem(item)
        }
    }

    func actionRequest(for action: WindowAction, in menu: NSMenu?) -> ActionRequest? {
        guard let menu else { return nil }
        for item in menu.items {
            if let request = item.representedObject as? ActionRequest,
               request.action == action
            {
                return request
            }
            if let request = actionRequest(for: action, in: item.submenu) {
                return request
            }
        }
        return nil
    }

    private func forceImageVisibility(for item: NSMenuItem) {
        if #available(macOS 27.0, *) {
            item.preferredImageVisibility = .visible
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

@MainActor
final class PreviewContextMenuController: NSObject {
    static let shared = PreviewContextMenuController()

    private var activeMenu: NSMenu?
    private var activeRoutingToken: UUID?

    func present(
        for window: WindowInfo,
        event: NSEvent,
        sourceView: NSView,
        handleWindowAction: @escaping (WindowAction) -> Void,
        dismissPreviews: (() -> Void)?
    ) {
        let shortcutKeybind = effectiveShortcutKeybind()
        let builtMenu = WindowActionMenuBuilder.shared.makeMenu(
            for: window,
            shortcutKeybind: shortcutKeybind,
            showShortcutHints: true,
            handleWindowAction: handleWindowAction,
            dismissPreviews: dismissPreviews
        )
        let menu = builtMenu.menu
        guard !menu.items.isEmpty else { return }

        dismiss()
        activeMenu = menu
        let routingToken = SharedPreviewWindowCoordinator.activeInstance?.beginContextMenuShortcutRouting(
            keybind: shortcutKeybind,
            actionsByKeyCode: builtMenu.shortcuts
        )
        activeRoutingToken = routingToken
        NSMenu.popUpContextMenu(menu, with: event, for: sourceView)
        if activeMenu === menu {
            activeMenu = nil
        }
        if activeRoutingToken == routingToken {
            activeRoutingToken = nil
        }
        if let routingToken {
            SharedPreviewWindowCoordinator.activeInstance?.endContextMenuShortcutRouting(token: routingToken)
        }
    }

    func dismiss() {
        activeMenu?.cancelTracking()
        activeMenu = nil
        if let activeRoutingToken {
            SharedPreviewWindowCoordinator.activeInstance?.endContextMenuShortcutRouting(token: activeRoutingToken)
            self.activeRoutingToken = nil
        }
    }

    func performShortcut(_ action: WindowAction, token: UUID) {
        guard activeRoutingToken == token,
              let request = WindowActionMenuBuilder.shared.actionRequest(for: action, in: activeMenu)
        else { return }

        dismiss()
        request.handler(request.action)
    }

    private func effectiveShortcutKeybind() -> UserKeyBind {
        SharedPreviewWindowCoordinator.activeInstance?.effectivePreviewShortcutKeybind()
            ?? WindowSwitcherShortcutResolver.dependentShortcutKeybind(Defaults[.UserKeybind])
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
