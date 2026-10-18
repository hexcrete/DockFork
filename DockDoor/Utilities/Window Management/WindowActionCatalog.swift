import AppKit
import Defaults

enum PreviewBatchTogglePolicy {
    static func targetState(_ states: [Bool]) -> Bool? {
        states.isEmpty ? nil : !states.allSatisfy { $0 }
    }
}

struct WindowActionGroup: Identifiable {
    let id: WindowAction.Group
    let actions: [WindowAction]
}

extension WindowAction {
    func usesConfirmedSingleWindowAction(on window: WindowInfo) -> Bool {
        [.minimize, .hide, .toggleFullScreen, .closeAllWindows].contains(self) ||
            (!window.isWindowlessApp && [.openAppWindow, .close].contains(self))
    }

    func autoTilingDirection(windowCount: Int, fillActionsAutoTile: Bool) -> PreviewTilingLayout.Direction? {
        guard self == .autoTileSelectedWindows || (windowCount > 1 && fillActionsAutoTile) else { return nil }
        return tilingDirection
    }

    var tilingDirection: PreviewTilingLayout.Direction? {
        switch self {
        case .autoTileSelectedWindows: .neutral
        case .fillLeftHalf: .left
        case .fillRightHalf: .right
        case .fillTopHalf: .top
        case .fillBottomHalf: .bottom
        case .fillTopLeftQuarter: .topLeft
        case .fillTopRightQuarter: .topRight
        case .fillBottomLeftQuarter: .bottomLeft
        case .fillBottomRightQuarter: .bottomRight
        default: nil
        }
    }

    func appliesToSelectedWindow(_ window: WindowInfo) -> Bool {
        !window.isWindowlessApp || isQuitAction || self == .openNewWindow
    }

    func batchTargets(from windows: [WindowInfo]) -> [WindowInfo] {
        var seenApps = Set<pid_t>()
        return windows.filter { window in
            guard appliesToSelectedWindow(window) else { return false }
            guard !isAppWidePreviewAction || seenApps.insert(window.app.processIdentifier).inserted else { return false }
            if self == .toggleFullScreen { return window.isFullscreen == true }
            if self == .hide, !window.app.isHidden {
                let appWindows = WindowUtil.readCachedWindows(for: window.app.processIdentifier)
                if !appWindows.isEmpty, appWindows.allSatisfy({ $0.isFullscreen == true }) { return false }
            }
            return true
        }
    }

    func batchTargetState(for windows: [WindowInfo]) -> Bool? {
        switch self {
        case .minimize, .minimizeAllWindows:
            let candidates = self == .minimizeAllWindows
                ? Set(windows.map(\.app.processIdentifier)).flatMap { WindowUtil.readCachedWindows(for: $0) }
                : windows
            let eligible = candidates.filter { !$0.isWindowlessApp && $0.isFullscreen != true }
            return PreviewBatchTogglePolicy.targetState(eligible.map(\.isMinimized))
        case .hide:
            return PreviewBatchTogglePolicy.targetState(batchTargets(from: windows).map(\.app.isHidden))
        default:
            return nil
        }
    }

    var isQuitAction: Bool { self == .quit || self == .forceQuit }

    var isAppWidePreviewAction: Bool {
        switch self {
        case .hide, .quit, .forceQuit, .closeAllWindows, .minimizeAllWindows, .openNewWindow: true
        default: false
        }
    }

    enum Group: String, CaseIterable {
        case window
        case arrange
        case app

        var localizedName: String {
            switch self {
            case .window:
                String(localized: "Window", comment: "Window action menu group")
            case .arrange:
                String(localized: "Arrange", comment: "Window action menu group")
            case .app:
                String(localized: "Application", comment: "Window action menu group")
            }
        }

        var actions: [WindowAction] {
            switch self {
            case .window:
                [.toggleWindowSelection, .selectAllWindows, .openAppWindow, .openNewWindow, .minimize, .hide, .maximize, .toggleFullScreen, .bringToCurrentSpace]
            case .arrange:
                [.autoTileSelectedWindows, .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
                 .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter, .center]
            case .app:
                [.close, .quit, .forceQuit]
            }
        }
    }

    static func availableGroups(for window: WindowInfo, batchTargets: [WindowInfo]? = nil,
                                includeSelectionActions: Bool = false) -> [WindowActionGroup]
    {
        Group.allCases.compactMap { group in
            let actions = group.actions.filter {
                (![.toggleWindowSelection, .selectAllWindows].contains($0) || includeSelectionActions) &&
                    (($0 == .toggleFullScreen && batchTargets?.contains(where: { $0.isFullscreen == true }) == true) || $0.isAvailable(for: window))
            }
            return actions.isEmpty ? nil : WindowActionGroup(id: group, actions: actions)
        }
    }

    func isAvailable(for window: WindowInfo) -> Bool {
        if self == .none { return false }

        if window.isWindowlessApp {
            if self == .toggleWindowSelection || self == .selectAllWindows {
                return Defaults[.enableMultiWindowSelection] && Defaults[.enableWindowlessAppSelection]
            }
            return self == .openAppWindow || self == .openNewWindow || isQuitAction || self == .hide
        }

        switch self {
        case .toggleWindowSelection, .selectAllWindows:
            return Defaults[.enableMultiWindowSelection]
        case .autoTileSelectedWindows:
            return true
        case .close:
            return window.closeButton != nil
        case .fillLeftHalf, .fillRightHalf, .fillTopHalf, .fillBottomHalf,
             .fillTopLeftQuarter, .fillTopRightQuarter, .fillBottomLeftQuarter, .fillBottomRightQuarter,
             .center, .maximize, .toggleFullScreen:
            return !window.isMinimized && !window.isHidden
        default:
            return true
        }
    }

    var positionRect: WindowInfo.WindowPositionRect? {
        switch self {
        case .maximize: .full
        case .fillLeftHalf: .leftHalf
        case .fillRightHalf: .rightHalf
        case .fillTopHalf: .topHalf
        case .fillBottomHalf: .bottomHalf
        case .fillTopLeftQuarter: .topLeftQuarter
        case .fillTopRightQuarter: .topRightQuarter
        case .fillBottomLeftQuarter: .bottomLeftQuarter
        case .fillBottomRightQuarter: .bottomRightQuarter
        case .center: .center
        default: nil
        }
    }

    func feedbackTitle(for window: WindowInfo, batchTargets: [WindowInfo]? = nil) -> String {
        if self == .autoTileSelectedWindows { return String(localized: "Auto Tile") }
        if self == .close || self == .closeAllWindows { return String(localized: "Close") }
        if self == .minimize || self == .minimizeAllWindows {
            return batchTargetState(for: batchTargets ?? [window]) == false
                ? String(localized: "Un-minimize") : String(localized: "Minimize")
        }
        if let batchTargets, batchTargets.count > 1 {
            switch self {
            case .hide:
                return batchTargetState(for: batchTargets) == false
                    ? String(localized: "Unhide App") : String(localized: "Hide App")
            case .toggleFullScreen:
                return batchTargets.contains { $0.isFullscreen == true }
                    ? String(localized: "Exit Full Screen") : String(localized: "Enter Full Screen")
            default: break
            }
        }
        return menuTitle(for: window, batchTargets: batchTargets)
    }

    func menuTitle(for window: WindowInfo, batchTargets: [WindowInfo]? = nil) -> String {
        if self == .toggleWindowSelection {
            return batchTargets == nil ? String(localized: "Add to Selection") : String(localized: "Remove from Selection")
        }
        if self == .autoTileSelectedWindows {
            return (batchTargets?.count ?? 0) > 1 ? localizedName : String(localized: "Auto Tile Window")
        }
        if let batchTargets, batchTargets.count > 1 {
            switch self {
            case .minimize:
                return batchTargetState(for: batchTargets) == false
                    ? String(localized: "Un-minimize Selected Windows") : String(localized: "Minimize Selected Windows")
            case .hide:
                return batchTargetState(for: batchTargets) == false
                    ? String(localized: "Unhide Selected Apps") : String(localized: "Hide Selected Apps")
            case .toggleFullScreen:
                return batchTargets.contains { $0.isFullscreen == true }
                    ? String(localized: "Exit Full Screen for Selected Windows") : String(localized: "Enter Full Screen (This Window)")
            default: break
            }
        }
        return switch self {
        case .minimize where window.isMinimized:
            String(localized: "Un-minimize", comment: "Window action for an already minimized window")
        case .hide where window.isHidden:
            String(localized: "Unhide App", comment: "Window action for an already hidden app")
        default:
            localizedName
        }
    }

    func menuIcon(for window: WindowInfo, batchTargets: [WindowInfo]? = nil) -> String {
        if self == .minimize || self == .minimizeAllWindows {
            return batchTargetState(for: batchTargets ?? [window]) == false ? "arrow.up.left.and.arrow.down.right.square" : iconName
        }
        if let batchTargets, batchTargets.count > 1 {
            if self == .hide { return batchTargetState(for: batchTargets) == false ? "eye" : iconName }
        }
        return switch self {
        case .hide where window.isHidden:
            "eye"
        default:
            iconName
        }
    }
}
