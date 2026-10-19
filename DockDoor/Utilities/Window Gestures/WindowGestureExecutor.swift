import AppKit
import ApplicationServices
import Carbon.HIToolbox.Events

final class WindowGestureExecutor {
    private let queue = DispatchQueue(label: "com.ethanbills.DockDoor.windowGestures.actions", qos: .userInteractive)
    private let registry = WindowSnapRegistry.shared
    private var pending: [(WindowGestureCommand, WindowGestureZone, CGPoint)] = []

    func perform(_ command: WindowGestureCommand, zone: WindowGestureZone, cursor: CGPoint) {
        switch command {
        case .switchApp, .openSwitcher: break
        default:
            Task.detached(priority: .userInitiated) { [self] in await run(command, zone: zone, cursor: cursor) }
            return
        }
        queue.async { [self] in
            pending.append((command, zone, cursor))
            if pending.count == 1 { runNext() }
        }
    }

    private func runNext() {
        guard let (command, zone, cursor) = pending.first else { return }
        Task.detached(priority: .userInitiated) { [self] in
            await run(command, zone: zone, cursor: cursor)
            queue.async { [self] in
                pending.removeFirst()
                runNext()
            }
        }
    }

    private func run(_ command: WindowGestureCommand, zone: WindowGestureZone, cursor: CGPoint) async {
        let reservesWindow = switch command {
        case .switchApp, .openSwitcher: false
        default: true
        }
        if reservesWindow, WindowActionRequest.current == nil, let window = zone.window {
            let apps: Set<pid_t>
            let terminal: Bool
            switch command {
            case let .window(action):
                apps = action.isAppWidePreviewAction ? [window.app.processIdentifier] : []
                terminal = action == .close || action.isQuitAction
            case .closeTab: apps = []; terminal = true
            default: apps = []; terminal = false
            }
            _ = await WindowActionRequest.run([PreviewWindowIdentity(window)], apps: apps, protect: terminal) { _ in
                await self.run(command, zone: zone, cursor: cursor)
            }
            return
        }
        switch command {
        case let .window(action):
            guard let window = zone.window else { return }
            if action == .minimize { await minimize(window) }
            else if action.positionRect != nil { await perform(action, on: window) }
            else if action.usesConfirmedSingleWindowAction(on: window) {
                let result = await WindowUtil.performPreviewBatchAction(action, on: [window], allowFullscreenEntry: action == .toggleFullScreen)
                if !Task.isCancelled, !result.succeeded.isEmpty,
                   action == .openAppWindow || (action == .hide && window.isHidden)
                { _ = await window.bringToFrontConfirmed() }
            } else { await perform(action, on: window) }
        case .closeTab:
            closeTab(in: zone)
        case .minimizeFrontWindow:
            guard let app = zone.app, let window = frontWindow(of: app) else { return }
            await minimize(window)
        case .restoreLastMinimized:
            guard let app = zone.app else { return }
            await restoreLastMinimized(of: app)
        case .quitApp:
            if let app = zone.app { _ = WindowInfo.windowlessEntry(for: app).quit(force: false) }
        case let .switchApp(forward):
            await switchApp(forward: forward)
        case .openSwitcher:
            break
        case .minimizeAllOnDisplay:
            await minimizeAll(on: NSScreen.screenFromQuartzPoint(cursor))
        case .restoreAllOnDisplay:
            await restoreAll(on: NSScreen.screenFromQuartzPoint(cursor))
        }
    }

    // MARK: - Windows

    @MainActor
    private func perform(_ action: WindowAction, on window: WindowInfo) async {
        if action == .center {
            let restoreSize = await registry.liveRecord(for: window)?.restoreFrame.size
            registry.remove(PreviewWindowIdentity(window))
            if await window.positionWindow(.center, size: restoreSize) {
                window.bringToFront()
            }
            return
        }
        guard let rect = action.positionRect, let current = await window.readWindowFrame() else {
            _ = action.perform(on: window)
            return
        }
        let restoreFrame = await registry.liveRecord(for: window)?.restoreFrame ?? current
        registry.remove(PreviewWindowIdentity(window))
        if await window.positionWindow(rect) {
            window.bringToFront()
            await registry.snapped(window, restoreFrame: restoreFrame)
        }
    }

    private func minimize(_ window: WindowInfo) async {
        if await !WindowUtil.minimizeWindowExitingFullscreen(window) {
            DebugLogger.log("WindowGestures", details: "Minimize failed for PID \(window.app.processIdentifier), window \(window.id)")
        }
    }

    private func frontWindow(of app: NSRunningApplication) -> WindowInfo? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let element = ((try? appElement.focusedWindow()) ?? nil)
            ?? ((try? appElement.attribute(kAXMainWindowAttribute, AXUIElement.self)) ?? nil)
        else { return nil }
        return WindowUtil.windowInfo(for: element, app: app)
    }

    private func restoreLastMinimized(of app: NSRunningApplication) async {
        let minimized = WindowUtil.readCachedWindows(for: app.processIdentifier)
            .filter { $0.isMinimized && !$0.isWindowlessApp }
            .max { $0.lastAccessedTime < $1.lastAccessedTime }
        guard let window = minimized else {
            await bringForward(app)
            return
        }
        await restore([window])
    }

    private func minimizeAll(on screen: NSScreen) async {
        let screenIdentifier = screen.uniqueIdentifier()
        let windows = WindowUtil.filterWindowsByCurrentSpace(WindowUtil.getAllWindowsIgnoringSwitcherFilters())
            .filter { !$0.isHidden && !$0.isWindowlessApp && $0.screenIdentifier == screenIdentifier }
        let changed = await WindowUtil.setMinimizedStateConfirmed(windows, isMinimized: true)
        if changed != windows.count {
            DebugLogger.log("WindowGestures", details: "Display minimization confirmed \(changed)/\(windows.count) windows")
        }
    }

    private func restoreAll(on screen: NSScreen) async {
        let screenIdentifier = screen.uniqueIdentifier()
        let windows = WindowUtil.getAllWindowsIgnoringSwitcherFilters()
            .filter { $0.isMinimized && !$0.isWindowlessApp && $0.screenIdentifier == screenIdentifier }
        await restore(windows)
    }

    private func restore(_ windows: [WindowInfo]) async {
        if WindowActionRequest.current == nil {
            _ = await WindowActionRequest.run(windows.map(PreviewWindowIdentity.init)) { _ in await self.restore(windows) }
            return
        }
        let restored = await WindowUtil.restoreWindowsConfirmed(windows)
        if restored.count != windows.count {
            DebugLogger.log("WindowGestures", details: "Restoration confirmed \(restored.count)/\(windows.count) windows")
        }
        if let target = restored.max(by: { $0.lastAccessedTime < $1.lastAccessedTime }), await !target.bringToFrontConfirmed() {
            DebugLogger.log("WindowGestures", details: "Restored window activation failed: \(target.id)")
        }
    }

    // MARK: - Tabs

    private func closeTab(in zone: WindowGestureZone) {
        guard case let .tab(window, tab, _, _) = zone else { return }
        if let closeButton = Self.closeButton(in: tab) {
            try? closeButton.performAction(kAXPressAction)
            return
        }
        guard select(tab, in: window) else { return }
        WindowUtil.postCommandShortcut(CGKeyCode(kVK_ANSI_W), to: window.ownerApp.processIdentifier)
    }

    private func select(_ tab: AXUIElement, in window: WindowInfo) -> Bool {
        window.bringToFront()
        try? tab.performAction(kAXPressAction)
        for _ in 0 ..< 15 {
            let focused = (try? window.appAxElement.focusedWindow()) ?? nil
            if Self.isSelected(tab), let focused, CFEqual(focused, window.axElement) {
                return true
            }
            Thread.sleep(forTimeInterval: 0.03)
        }
        return false
    }

    private static func isSelected(_ tab: AXUIElement) -> Bool {
        if let value = (try? tab.attribute(kAXValueAttribute, NSNumber.self)) ?? nil {
            return value.intValue == 1
        }
        return ((try? tab.attribute(kAXSelectedAttribute, Bool.self)) ?? nil) == true
    }

    private static func closeButton(in tab: AXUIElement) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(tab, 0)]
        var fallback: AXUIElement?
        while !queue.isEmpty {
            let (element, depth) = queue.removeFirst()
            guard depth < 3, let children = try? element.children() else { continue }
            for child in children {
                guard (try? child.role()) == kAXButtonRole as String else {
                    queue.append((child, depth + 1))
                    continue
                }
                if (try? child.subrole()) == kAXCloseButtonSubrole as String {
                    return child
                }
                let description = (try? child.attribute(kAXDescriptionAttribute, String.self)) ?? nil
                if fallback == nil, description?.localizedCaseInsensitiveContains("close") == true {
                    fallback = child
                }
            }
        }
        return fallback
    }

    // MARK: - Apps

    private func switchApp(forward: Bool) async {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ordered = DockObserver.activeInstance?.runningApplicationsInDockOrder() ?? []
        let apps = (ordered.isEmpty ? NSWorkspace.shared.runningApplications : ordered)
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != ownPID && !$0.isTerminated }
        guard !apps.isEmpty else { return }

        let current = NSWorkspace.shared.frontmostApplication
        let next: NSRunningApplication = if let index = apps.firstIndex(where: { $0.processIdentifier == current?.processIdentifier }) {
            apps[(index + (forward ? 1 : -1) + apps.count) % apps.count]
        } else {
            forward ? apps[0] : apps[apps.count - 1]
        }
        await bringForward(next)
    }

    private func bringForward(_ app: NSRunningApplication) async {
        if app.isHidden, await !WindowUtil.setHiddenStateConfirmed(for: app, isHidden: false) { return }
        let windows = WindowUtil.readCachedWindows(for: app.processIdentifier).filter { !$0.isMinimized && !$0.isWindowlessApp }
        if let window = windows.max(by: { $0.lastAccessedTime < $1.lastAccessedTime }) {
            window.bringToFront()
        } else {
            WindowInfo.windowlessEntry(for: app).bringToFront()
        }
    }
}
