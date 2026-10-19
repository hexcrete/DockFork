import AppKit

@MainActor
final class WindowActionsMenuController: NSObject, NSMenuDelegate {
    let menu: NSMenu

    private final class WindowMenu: NSMenu {
        let window: WindowInfo

        init(window: WindowInfo) {
            self.window = window
            super.init(title: "")
            // AppKit needs an item to expose a lazily populated submenu.
            let placeholder = NSMenuItem(title: String(localized: "Window Actions", comment: "Menu bar submenu title"), action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            addItem(placeholder)
        }

        @available(*, unavailable)
        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    override init() {
        menu = NSMenu(title: String(localized: "Window Actions", comment: "Menu bar submenu title"))
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let windowMenu = menu as? WindowMenu {
            let window = windowMenu.window
            let actions = WindowActionMenuBuilder.shared.makeMenu(
                for: window,
                showShortcutHints: false,
                handleWindowAction: { action in
                    let targets = action == .closeAllWindows
                        ? WindowUtil.readCachedWindows(for: window.app.processIdentifier).filter { !$0.isWindowlessApp }
                        : [window]
                    let resolvedTargets = action.previewTargets(from: targets)
                    let targetState = action.batchTargetState(for: resolvedTargets)
                    let feedback = ActionFeedbackController.begin(action, windows: targets, keyboard: NSApp.currentEvent?.type == .keyDown, usePreviews: false, resolvedTargets: resolvedTargets)
                    if action.usesConfirmedSingleWindowAction(on: window) {
                        let request = WindowUtil.beginPreviewActionRequest(action, windows: targets, resolvedTargets: resolvedTargets)
                        guard !request.admitted.isEmpty else { feedback?.finishRemaining(.failed); return }
                        let restoring = action == .openAppWindow || (action == .hide && window.app.isHidden) || (action == .minimize && window.isMinimized)
                        let task = Task { @MainActor in
                            defer { request.finish() }
                            await WindowActionRequest.$current.withValue(request) {
                                let result = await WindowUtil.performPreviewBatchAction(action, on: targets, allowFullscreenEntry: action == .toggleFullScreen, feedback: feedback, request: request, targetState: targetState, resolvedTargets: resolvedTargets)
                                if !Task.isCancelled, request.mayForeground, restoring, !result.succeeded.isEmpty { _ = await window.bringToFrontConfirmed() }
                            }
                        }
                        request.onSuperseded { task.cancel() }
                    } else {
                        _ = action.perform(on: window, feedback: feedback)
                    }
                }
            ).menu
            for item in actions.items {
                actions.removeItem(item)
                menu.addItem(item)
            }
            return
        }

        let windows = WindowUtil.getAllWindowsIgnoringSwitcherFilters()
        guard !windows.isEmpty else {
            let empty = NSMenuItem(title: String(localized: "No Windows", comment: "Empty window actions menu"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        let grouped = Dictionary(grouping: windows, by: { $0.app.processIdentifier })
        let sortedApps = grouped.sorted { lhs, rhs in
            let lhsName = lhs.value.first?.app.localizedName ?? ""
            let rhsName = rhs.value.first?.app.localizedName ?? ""
            return lhsName.localizedStandardCompare(rhsName) == .orderedAscending
        }

        for (_, appWindows) in sortedApps {
            guard let app = appWindows.first?.app else { continue }
            let appItem = NSMenuItem(title: app.localizedName ?? String(localized: "Unknown App", comment: "Fallback app name"), action: nil, keyEquivalent: "")
            appItem.image = app.icon?.resizedToFit(in: NSSize(width: 16, height: 16))

            let appSubmenu = NSMenu()
            for window in appWindows {
                let windowItem = NSMenuItem(title: title(for: window), action: nil, keyEquivalent: "")
                let actionsMenu = WindowMenu(window: window)
                actionsMenu.delegate = self
                windowItem.submenu = actionsMenu
                appSubmenu.addItem(windowItem)
            }
            appItem.submenu = appSubmenu
            menu.addItem(appItem)
        }
    }

    private func title(for window: WindowInfo) -> String {
        if window.isWindowlessApp {
            return String(localized: "No Open Windows", comment: "Window actions entry for an app with no windows")
        }
        let name = window.windowName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = name.isEmpty ? (window.app.localizedName ?? String(localized: "Untitled", comment: "Fallback window title")) : name
        var decorated = base
        if window.isMinimized {
            decorated += String(localized: " (minimized)", comment: "Suffix for a minimized window in the actions menu")
        } else if window.isHidden {
            decorated += String(localized: " (hidden)", comment: "Suffix for a hidden window in the actions menu")
        }
        return decorated
    }
}
