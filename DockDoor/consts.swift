import Carbon.HIToolbox.Events
import Cocoa
import Defaults
import Foundation
import SwiftUI

let optimisticScreenSizeWidth = NSScreen.main!.frame.width
let optimisticScreenSizeHeight = NSScreen.main!.frame.height

let roughHeightCap = optimisticScreenSizeHeight / 3
let roughWidthCap = optimisticScreenSizeWidth / 3

let spotifyAppIdentifier = "com.spotify.client"
let appleMusicAppIdentifier = "com.apple.Music"
let calendarAppIdentifier = "com.apple.iCal"

@MainActor func isMediaApp(_ bundleIdentifier: String?) -> Bool {
    guard let bundleId = bundleIdentifier else { return false }
    switch Defaults[.mediaDetectionMode] {
    case .universal:
        return MediaRemoteService.shared.matchesMediaSource(bundleIdentifier: bundleId)
    case .appleScriptOnly:
        return bundleId == spotifyAppIdentifier || bundleId == appleMusicAppIdentifier
    }
}

struct CmdShortcut: Codable, Defaults.Serializable, Identifiable, Hashable {
    var id: UUID
    var keyCode: UInt16
    var action: WindowAction
    var isPending: Bool

    init(id: UUID = UUID(), keyCode: UInt16, action: WindowAction, isPending: Bool = false) {
        self.id = id
        self.keyCode = keyCode
        self.action = action
        self.isPending = isPending
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case keyCode
        case action
        case isPending
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let actionRawValue = try container.decode(String.self, forKey: .action)
        action = WindowAction(rawValue: actionRawValue) ?? .none
        isPending = try container.decodeIfPresent(Bool.self, forKey: .isPending) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(action.rawValue, forKey: .action)
        try container.encode(isPending, forKey: .isPending)
    }

    static let defaultShortcuts: [CmdShortcut] = [
        CmdShortcut(keyCode: UInt16(kVK_ANSI_W), action: .close),
        CmdShortcut(keyCode: UInt16(kVK_ANSI_M), action: .minimize),
        CmdShortcut(keyCode: UInt16(kVK_ANSI_Q), action: .quit),
    ]
}

struct AlternateSwitcherShortcut: Codable, Defaults.Serializable, Identifiable, Hashable {
    var id: UUID
    var keyCode: UInt16
    var modifierFlags: Int
    var mode: SwitcherInvocationMode
    var isConfigured: Bool
    var isPending: Bool

    init(
        id: UUID = UUID(),
        keyCode: UInt16 = 0,
        modifierFlags: Int = 0,
        mode: SwitcherInvocationMode = .activeAppOnly,
        isConfigured: Bool = false,
        isPending: Bool = false
    ) {
        self.id = id
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.mode = mode
        self.isConfigured = isConfigured
        self.isPending = isPending
    }

    func resolvedKeybind(mainKeybind: UserKeyBind) -> UserKeyBind? {
        guard isConfigured, !isPending else { return nil }
        return UserKeyBind(
            keyCode: keyCode,
            modifierFlags: modifierFlags == 0 ? mainKeybind.modifierFlags : modifierFlags
        )
    }

    static let defaultShortcuts = [AlternateSwitcherShortcut()]
}

enum AlternateSwitcherShortcutConflict: Equatable {
    case spacesShortcut
    case duplicate
    case previewAction

    var localizedMessage: String {
        switch self {
        case .spacesShortcut:
            String(localized: "Conflicts with a Spaces shortcut. Shortcut disabled.", comment: "Window Switcher shortcut conflict")
        case .duplicate:
            String(localized: "Duplicate shortcut. Shortcut disabled.", comment: "Alternate Window Switcher shortcut conflict")
        case .previewAction:
            String(localized: "Conflicts with a window preview shortcut. Shortcut disabled.", comment: "Alternate Window Switcher shortcut conflict")
        }
    }
}

struct ResolvedAlternateSwitcherShortcut {
    let id: UUID
    let keybind: UserKeyBind
    let mode: SwitcherInvocationMode
}

enum ModifierDoubleTapKey: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case shift
    case control
    case option
    case command

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .shift: String(localized: "Shift", comment: "Modifier key name")
        case .control: String(localized: "Control", comment: "Modifier key name")
        case .option: String(localized: "Option", comment: "Modifier key name")
        case .command: String(localized: "Command", comment: "Modifier key name")
        }
    }

    var keyCodes: (left: UInt16, right: UInt16) {
        switch self {
        case .shift: (UInt16(kVK_Shift), UInt16(kVK_RightShift))
        case .control: (UInt16(kVK_Control), UInt16(kVK_RightControl))
        case .option: (UInt16(kVK_Option), UInt16(kVK_RightOption))
        case .command: (UInt16(kVK_Command), UInt16(kVK_RightCommand))
        }
    }
}

enum ModifierKeySide: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case both
    case left
    case right

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .both: String(localized: "Both", comment: "Modifier key side option")
        case .left: String(localized: "Left", comment: "Modifier key side option")
        case .right: String(localized: "Right", comment: "Modifier key side option")
        }
    }
}

struct PersistentSwitcherShortcut: Codable, Defaults.Serializable, Identifiable, Hashable {
    var id: UUID
    var keyCode: UInt16
    var modifierFlags: Int
    var mode: SwitcherInvocationMode
    var usesDoubleTap: Bool
    var doubleTapKey: ModifierDoubleTapKey
    var doubleTapSide: ModifierKeySide
    var isConfigured: Bool
    var isPending: Bool

    init(
        id: UUID = UUID(),
        keyCode: UInt16 = 0,
        modifierFlags: Int = 0,
        mode: SwitcherInvocationMode = .allWindows,
        usesDoubleTap: Bool = false,
        doubleTapKey: ModifierDoubleTapKey = .option,
        doubleTapSide: ModifierKeySide = .both,
        isConfigured: Bool = false,
        isPending: Bool = false
    ) {
        self.id = id
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.mode = mode
        self.usesDoubleTap = usesDoubleTap
        self.doubleTapKey = doubleTapKey
        self.doubleTapSide = doubleTapSide
        self.isConfigured = isConfigured
        self.isPending = isPending
    }

    static let defaultShortcuts = [PersistentSwitcherShortcut()]
}

struct ResolvedPersistentSwitcherShortcut {
    let id: UUID
    let keyCode: UInt16
    let modifierFlags: Int
    let mode: SwitcherInvocationMode
    let doubleTapKey: ModifierDoubleTapKey?
    let doubleTapSide: ModifierKeySide?
}

enum WindowSwitcherShortcutResolver {
    static func spaceNumber(forPhysicalKeyCode keyCode: Int64) -> Int? {
        switch keyCode {
        case Int64(kVK_ANSI_1): 1
        case Int64(kVK_ANSI_2): 2
        case Int64(kVK_ANSI_3): 3
        case Int64(kVK_ANSI_4): 4
        case Int64(kVK_ANSI_5): 5
        case Int64(kVK_ANSI_6): 6
        case Int64(kVK_ANSI_7): 7
        case Int64(kVK_ANSI_8): 8
        case Int64(kVK_ANSI_9): 9
        case Int64(kVK_ANSI_0): 10
        default: nil
        }
    }

    static func conflictsWithSpacesShortcut(
        keyCode: UInt16,
        modifierFlags: Int,
        mainKeybind: UserKeyBind
    ) -> Bool {
        let mainModifiers = normalizedModifiers(mainKeybind.modifierFlags)
        return Defaults[.enableSpacesShortcuts] &&
            mainModifiers != 0 &&
            spaceNumber(forPhysicalKeyCode: Int64(keyCode)) != nil &&
            normalizedModifiers(modifierFlags) == mainModifiers
    }

    static func alternateConflict(
        at index: Int,
        shortcuts: [AlternateSwitcherShortcut],
        mainKeybind: UserKeyBind,
        previewShortcuts: [CmdShortcut]
    ) -> AlternateSwitcherShortcutConflict? {
        guard shortcuts.indices.contains(index),
              let candidate = shortcuts[index].resolvedKeybind(mainKeybind: mainKeybind)
        else { return nil }

        if conflictsWithSpacesShortcut(
            keyCode: UInt16(candidate.keyCode),
            modifierFlags: candidate.modifierFlags,
            mainKeybind: mainKeybind
        ) {
            return .spacesShortcut
        }

        if combinationsMatch(candidate, mainKeybind) {
            return .duplicate
        }

        for earlierIndex in 0 ..< index {
            guard let earlier = shortcuts[earlierIndex].resolvedKeybind(mainKeybind: mainKeybind) else { continue }
            if combinationsMatch(candidate, earlier) {
                return .duplicate
            }
        }

        let conflictsWithPreviewAction = candidate.modifierFlags == mainKeybind.modifierFlags && previewShortcuts.contains {
            !$0.isPending && $0.action != .none && $0.keyCode == candidate.keyCode
        }
        return conflictsWithPreviewAction ? .previewAction : nil
    }

    static func resolvedAlternateShortcuts(
        _ shortcuts: [AlternateSwitcherShortcut],
        mainKeybind: UserKeyBind,
        previewShortcuts: [CmdShortcut]
    ) -> [ResolvedAlternateSwitcherShortcut] {
        shortcuts.indices.compactMap { index in
            guard alternateConflict(
                at: index,
                shortcuts: shortcuts,
                mainKeybind: mainKeybind,
                previewShortcuts: previewShortcuts
            ) == nil,
                let keybind = shortcuts[index].resolvedKeybind(mainKeybind: mainKeybind)
            else { return nil }

            return ResolvedAlternateSwitcherShortcut(
                id: shortcuts[index].id,
                keybind: keybind,
                mode: shortcuts[index].mode
            )
        }
    }

    static func persistentConflict(
        at index: Int,
        shortcuts: [PersistentSwitcherShortcut],
        mainKeybind: UserKeyBind,
        alternateShortcuts: [AlternateSwitcherShortcut],
        previewShortcuts: [CmdShortcut]
    ) -> AlternateSwitcherShortcutConflict? {
        guard shortcuts.indices.contains(index) else { return nil }
        let candidate = shortcuts[index]
        guard candidate.isConfigured, !candidate.isPending else { return nil }

        if candidate.usesDoubleTap {
            for earlierIndex in 0 ..< index {
                let earlier = shortcuts[earlierIndex]
                guard earlier.isConfigured, !earlier.isPending, earlier.usesDoubleTap,
                      earlier.doubleTapKey == candidate.doubleTapKey
                else { continue }
                if sidesOverlap(earlier.doubleTapSide, candidate.doubleTapSide) {
                    return .duplicate
                }
            }
            return nil
        }

        if conflictsWithSpacesShortcut(
            keyCode: candidate.keyCode,
            modifierFlags: candidate.modifierFlags,
            mainKeybind: mainKeybind
        ) {
            return .spacesShortcut
        }

        let combination = UserKeyBind(keyCode: candidate.keyCode, modifierFlags: candidate.modifierFlags)
        if combinationsMatch(combination, mainKeybind) {
            return .duplicate
        }
        if resolvedAlternateShortcuts(
            alternateShortcuts,
            mainKeybind: mainKeybind,
            previewShortcuts: previewShortcuts
        ).contains(where: { combinationsMatch(combination, $0.keybind) }) {
            return .duplicate
        }
        for earlierIndex in 0 ..< index {
            let earlier = shortcuts[earlierIndex]
            guard earlier.isConfigured, !earlier.isPending, !earlier.usesDoubleTap else { continue }
            if combinationsMatch(
                combination,
                UserKeyBind(keyCode: earlier.keyCode, modifierFlags: earlier.modifierFlags)
            ) {
                return .duplicate
            }
        }

        let mainModifiers = normalizedModifiers(mainKeybind.modifierFlags)
        let conflictsWithPreviewAction = normalizedModifiers(candidate.modifierFlags) == mainModifiers && previewShortcuts.contains {
            !$0.isPending && $0.action != .none && $0.keyCode == candidate.keyCode
        }
        return conflictsWithPreviewAction ? .previewAction : nil
    }

    static func resolvedPersistentShortcuts(
        _ shortcuts: [PersistentSwitcherShortcut],
        mainKeybind: UserKeyBind,
        alternateShortcuts: [AlternateSwitcherShortcut],
        previewShortcuts: [CmdShortcut]
    ) -> [ResolvedPersistentSwitcherShortcut] {
        shortcuts.indices.compactMap { index in
            let shortcut = shortcuts[index]
            guard shortcut.isConfigured, !shortcut.isPending,
                  persistentConflict(
                      at: index,
                      shortcuts: shortcuts,
                      mainKeybind: mainKeybind,
                      alternateShortcuts: alternateShortcuts,
                      previewShortcuts: previewShortcuts
                  ) == nil
            else { return nil }

            return ResolvedPersistentSwitcherShortcut(
                id: shortcut.id,
                keyCode: shortcut.keyCode,
                modifierFlags: normalizedModifiers(shortcut.modifierFlags),
                mode: shortcut.mode,
                doubleTapKey: shortcut.usesDoubleTap ? shortcut.doubleTapKey : nil,
                doubleTapSide: shortcut.usesDoubleTap ? shortcut.doubleTapSide : nil
            )
        }
    }

    static func lastFocusedConflict(
        at index: Int,
        shortcuts: [PersistentSwitcherShortcut],
        mainKeybind: UserKeyBind,
        alternateShortcuts: [AlternateSwitcherShortcut],
        persistentShortcuts: [PersistentSwitcherShortcut],
        previewShortcuts: [CmdShortcut]
    ) -> AlternateSwitcherShortcutConflict? {
        guard shortcuts.indices.contains(index) else { return nil }
        let candidate = shortcuts[index]
        guard candidate.isConfigured, !candidate.isPending else { return nil }

        if candidate.usesDoubleTap {
            let conflictsWithPersistent = resolvedPersistentShortcuts(
                persistentShortcuts,
                mainKeybind: mainKeybind,
                alternateShortcuts: alternateShortcuts,
                previewShortcuts: previewShortcuts
            ).contains { resolved in
                resolved.doubleTapKey == candidate.doubleTapKey &&
                    resolved.doubleTapSide.map { sidesOverlap($0, candidate.doubleTapSide) } == true
            }
            if conflictsWithPersistent { return .duplicate }

            for earlierIndex in 0 ..< index {
                let earlier = shortcuts[earlierIndex]
                guard earlier.isConfigured, !earlier.isPending, earlier.usesDoubleTap,
                      earlier.doubleTapKey == candidate.doubleTapKey
                else { continue }
                if sidesOverlap(earlier.doubleTapSide, candidate.doubleTapSide) {
                    return .duplicate
                }
            }
            return nil
        }

        if conflictsWithSpacesShortcut(
            keyCode: candidate.keyCode,
            modifierFlags: candidate.modifierFlags,
            mainKeybind: mainKeybind
        ) {
            return .spacesShortcut
        }

        let combination = UserKeyBind(keyCode: candidate.keyCode, modifierFlags: candidate.modifierFlags)
        if combinationsMatch(combination, mainKeybind) { return .duplicate }
        if resolvedAlternateShortcuts(
            alternateShortcuts,
            mainKeybind: mainKeybind,
            previewShortcuts: previewShortcuts
        ).contains(where: { combinationsMatch(combination, $0.keybind) }) {
            return .duplicate
        }
        if resolvedPersistentShortcuts(
            persistentShortcuts,
            mainKeybind: mainKeybind,
            alternateShortcuts: alternateShortcuts,
            previewShortcuts: previewShortcuts
        ).contains(where: {
            $0.doubleTapKey == nil && combinationsMatch(
                combination,
                UserKeyBind(keyCode: $0.keyCode, modifierFlags: $0.modifierFlags)
            )
        }) {
            return .duplicate
        }
        for earlierIndex in 0 ..< index {
            let earlier = shortcuts[earlierIndex]
            guard earlier.isConfigured, !earlier.isPending, !earlier.usesDoubleTap else { continue }
            if combinationsMatch(
                combination,
                UserKeyBind(keyCode: earlier.keyCode, modifierFlags: earlier.modifierFlags)
            ) {
                return .duplicate
            }
        }

        let conflictsWithPreviewAction = normalizedModifiers(candidate.modifierFlags) == normalizedModifiers(mainKeybind.modifierFlags) && previewShortcuts.contains {
            !$0.isPending && $0.action != .none && $0.keyCode == candidate.keyCode
        }
        return conflictsWithPreviewAction ? .previewAction : nil
    }

    static func resolvedLastFocusedShortcuts(
        _ shortcuts: [PersistentSwitcherShortcut],
        mainKeybind: UserKeyBind,
        alternateShortcuts: [AlternateSwitcherShortcut],
        persistentShortcuts: [PersistentSwitcherShortcut],
        previewShortcuts: [CmdShortcut]
    ) -> [ResolvedPersistentSwitcherShortcut] {
        shortcuts.indices.compactMap { index in
            let shortcut = shortcuts[index]
            guard shortcut.isConfigured, !shortcut.isPending,
                  lastFocusedConflict(
                      at: index,
                      shortcuts: shortcuts,
                      mainKeybind: mainKeybind,
                      alternateShortcuts: alternateShortcuts,
                      persistentShortcuts: persistentShortcuts,
                      previewShortcuts: previewShortcuts
                  ) == nil
            else { return nil }

            return ResolvedPersistentSwitcherShortcut(
                id: shortcut.id,
                keyCode: shortcut.keyCode,
                modifierFlags: normalizedModifiers(shortcut.modifierFlags),
                mode: shortcut.mode,
                doubleTapKey: shortcut.usesDoubleTap ? shortcut.doubleTapKey : nil,
                doubleTapSide: shortcut.usesDoubleTap ? shortcut.doubleTapSide : nil
            )
        }
    }

    static func normalizedModifiers(_ flags: Int) -> Int {
        let supported = CGEventFlags.maskShift.rawValue |
            CGEventFlags.maskControl.rawValue |
            CGEventFlags.maskAlternate.rawValue |
            CGEventFlags.maskCommand.rawValue
        return flags & Int(supported)
    }

    private static func combinationsMatch(_ first: UserKeyBind, _ second: UserKeyBind) -> Bool {
        first.keyCode == second.keyCode && normalizedModifiers(first.modifierFlags) == normalizedModifiers(second.modifierFlags)
    }

    private static func sidesOverlap(_ first: ModifierKeySide, _ second: ModifierKeySide) -> Bool {
        first == .both || second == .both || first == second
    }
}

extension Defaults.Keys {
    static let previewWidth = Key<CGFloat>("previewWidth", default: 300)
    static let previewHeight = Key<CGFloat>("previewHeight", default: 187.5)
    static let lockAspectRatio = Key<Bool>("lockAspectRatio", default: true)
    static let bufferFromDock = Key<CGFloat>("bufferFromDock", default: CoreDockIsMagnificationEnabled() ? -25 : DockUtils.getDockPosition() == .right ? -18 : -20)
    static let globalPaddingMultiplier = Key<CGFloat>("globalPaddingMultiplier", default: 0.7)
    static let hoverWindowOpenDelay = Key<CGFloat>("openDelay", default: 0.2)
    static let useDelayOnlyForInitialOpen = Key<Bool>("useDelayOnlyForInitialOpen", default: false)
    static let anchorDockPreviewPosition = Key<Bool>("anchorDockPreviewPosition", default: true)
    static let preventDockHide = Key<Bool>("preventDockHide", default: false)
    static let preventSwitcherHide = Key<Bool>("preventSwitcherHide", default: false)
    static let requireShiftTabToGoBack = Key<Bool>("requireShiftTabToGoBack", default: false)
    static let switcherBackwardKeyCode = Key<UInt16>("switcherBackwardKeyCode", default: 56)
    static let shouldHideOnDockItemClick = Key<Bool>("shouldHideOnDockItemClick", default: false)
    static let dockClickAction = Key<DockClickAction>("dockClickAction", default: .hide)
    static let restoreAllMinimizedWindowsOnDockClick = Key<Bool>("restoreAllMinimizedWindowsOnDockClick", default: true)
    static let enableCmdRightClickQuit = Key<Bool>("enableCmdRightClickQuit", default: true)
    static let quitAppOnWindowClose = Key<Bool>("quitAppOnWindowClose", default: false)
    static let enableDockScrollGesture = Key<Bool>("enableDockScrollGesture", default: false)
    static let enableTitleBarScrollGesture = Key<Bool>("enableTitleBarScrollGesture", default: false)
    static let titleBarScrollCenteredWindowScale = Key<CGFloat>("titleBarScrollCenteredWindowScale", default: 0.8)
    static let titleBarScrollCenteredWindowSizingMode = Key<TitleBarCenteredWindowSizingMode>("titleBarScrollCenteredWindowSizingMode", default: .uniform)
    static let titleBarScrollCenteredWindowWidthScale = Key<CGFloat>("titleBarScrollCenteredWindowWidthScale", default: 0.8)
    static let titleBarScrollCenteredWindowHeightScale = Key<CGFloat>("titleBarScrollCenteredWindowHeightScale", default: 0.8)
    static let titleBarScrollCenteredWindowLockAspectRatio = Key<Bool>("titleBarScrollCenteredWindowLockAspectRatio", default: false)
    static let titleBarScrollRestoreWindowInterval = Key<CGFloat>("titleBarScrollRestoreWindowInterval", default: 1.5)

    // Dock Locking
    static let enableDockLocking = Key<Bool>("enableDockLocking", default: false)
    static let lockedDockScreenIdentifier = Key<String>("lockedDockScreenIdentifier", default: "")
    static let dockLockOverrideModifier = Key<Int>("dockLockOverrideModifier", default: DockLockModifier.option.rawValue)
    static let dockIconScrollBehavior = Key<DockIconScrollBehavior>("dockIconScrollBehavior", default: .activateHide)
    static let dockIconMediaScrollBehavior = Key<DockIconMediaScrollBehavior>("dockIconMediaScrollBehavior", default: .adjustVolume)
    static let mediaWidgetScrollBehavior = Key<MediaWidgetScrollBehavior>("mediaWidgetScrollBehavior", default: .seekPlayback)
    static let mediaWidgetScrollDirection = Key<MediaWidgetScrollDirection>("mediaWidgetScrollDirection", default: .vertical)

    static let screenCaptureCacheLifespan = Key<CGFloat>("screenCaptureCacheLifespan", default: 30)
    static let windowProcessingDebounceInterval = Key<CGFloat>("windowProcessingDebounceInterval", default: 0.3)
    static let programmaticResizePreviewRefreshDelay = Key<CGFloat>("programmaticResizePreviewRefreshDelay", default: 0.18)
    static let nativeResizePreviewRefreshDelay = Key<CGFloat>("nativeResizePreviewRefreshDelay", default: 0.36)
    static let windowPreviewImageScale = Key<CGFloat>("windowPreviewImageScale", default: 1)
    static let windowImageCaptureQuality = Key<WindowImageCaptureQuality>("windowImageCaptureQuality", default: .nominal)

    static let enableLivePreview = Key<Bool>("enableLivePreview", default: false)
    static let enableLivePreviewForDock = Key<Bool>("enableLivePreviewForDock", default: true)
    static let enableLivePreviewForWindowSwitcher = Key<Bool>("enableLivePreviewForWindowSwitcher", default: false)
    static let dockLivePreviewQuality = Key<LivePreviewQuality>("dockLivePreviewQuality", default: .high)
    static let dockLivePreviewFrameRate = Key<LivePreviewFrameRate>("dockLivePreviewFrameRate", default: .fps24)
    static let windowSwitcherLivePreviewQuality = Key<LivePreviewQuality>("windowSwitcherLivePreviewQuality", default: .low)
    static let windowSwitcherLivePreviewFrameRate = Key<LivePreviewFrameRate>("windowSwitcherLivePreviewFrameRate", default: .fps10)
    static let windowSwitcherLivePreviewScope = Key<WindowSwitcherLivePreviewScope>("windowSwitcherLivePreviewScope", default: .selectedAppWindows)
    static let livePreviewStreamKeepAlive = Key<Int>("livePreviewStreamKeepAlive", default: 0)

    static let uniformCardRadius = Key<Bool>("uniformCardRadius", default: true)
    static let allowDynamicImageSizing = Key<Bool>("allowDynamicImageSizing", default: false)
    static let tapEquivalentInterval = Key<CGFloat>("tapEquivalentInterval", default: 1.5)
    static let switcherTapEquivalentInterval = Key<CGFloat>("switcherTapEquivalentInterval", default: Defaults.Keys.tapEquivalentInterval.defaultValue)
    static let cmdTabTapEquivalentInterval = Key<CGFloat>("cmdTabTapEquivalentInterval", default: Defaults.Keys.tapEquivalentInterval.defaultValue)
    static let fadeOutDuration = Key<CGFloat>("fadeOutDuration", default: 0.4)
    static let preventPreviewReentryDuringFadeOut = Key<Bool>("preventPreviewReentryDuringFadeOut", default: false)
    static let inactivityTimeout = Key<CGFloat>("inactivityTimeout", default: 0.2)
    static let previewHoverAction = Key<PreviewHoverAction>("previewHoverAction", default: .none)
    static let switcherPreviewHoverAction = Key<PreviewHoverAction>("switcherPreviewHoverAction", default: .none)
    static let cmdTabPreviewHoverAction = Key<PreviewHoverAction>("cmdTabPreviewHoverAction", default: .none)
    static let keepPreviewOnHoverActivation = Key<Bool>("keepPreviewOnHoverActivation", default: false)
    static let aeroShakeAction = Key<AeroShakeAction>("aeroShakeAction", default: .none)

    static let showSpecialAppControls = Key<Bool>("showSpecialAppControls", default: true)
    static let enableMediaWidget = Key<Bool>("enableMediaWidget", default: true)
    static let mediaDetectionMode = Key<MediaDetectionMode>("mediaDetectionMode", default: .universal)
    static let enableCalendarWidget = Key<Bool>("enableCalendarWidget", default: true)
    static let enableFolderWidget = Key<Bool>("enableFolderWidget", default: false)
    static let folderWidgetDefaultSortOrder = Key<FolderWidgetSortOrder>("folderWidgetDefaultSortOrder", default: .dateModified)
    static let folderWidgetDefaultSortReversed = Key<Bool>("folderWidgetDefaultSortReversed", default: true)
    static let folderWidgetRememberSortPerFolder = Key<Bool>("folderWidgetRememberSortPerFolder", default: true)
    static let folderWidgetSortOrders = Key<[String: FolderWidgetSortOrder]>("folderWidgetSortOrders", default: [:])
    static let folderWidgetSortReversed = Key<[String: Bool]>("folderWidgetSortReversed", default: [:])
    static let folderWidgetShowHiddenFiles = Key<Bool>("folderWidgetShowHiddenFiles", default: false)
    static let folderWidgetAuthorizedBookmarks = Key<[String: String]>("folderWidgetAuthorizedBookmarks", default: [:])
    static let useEmbeddedMediaControls = Key<Bool>("useEmbeddedMediaControls", default: true)
    static let useEmbeddedDockPreviewElements = Key<Bool>("useEmbeddedDockPreviewElements", default: false)
    static let disableDockStyleTrafficLights = Key<Bool>("disableDockStyleTrafficLights", default: false)
    static let disableDockStyleTitles = Key<Bool>("disableDockStyleTitles", default: false)
    static let showBigControlsWhenNoValidWindows = Key<Bool>("showBigControlsWhenNoValidWindows", default: true)
    static let showMassActionButtons = Key<Bool>("showMassActionButtons", default: true)
    static let enablePinning = Key<Bool>("enablePinning", default: true)

    static let persistedWindowOrder = Key<[WindowOrderPersistence.PersistedWindowEntry]>("persistedWindowOrder", default: [])
    static let showAnimations = Key<Bool>("showAnimations", default: true)
    static let gradientColorPalette = Key<GradientColorPaletteSettings>("gradientColorPalette", default: .init())
    static let enableWindowSwitcher = Key<Bool>("enableWindowSwitcher", default: true)
    static let instantWindowSwitcher = Key<Bool>("instantWindowSwitcher", default: false)
    static let enableDockPreviews = Key<Bool>("enableDockPreviews", default: true)
    static let dockPreviewActivationMode = Key<DockPreviewActivationMode>("dockPreviewActivationMode", default: .hover)
    static let dockPreviewActivationModifier = Key<DockPreviewActivationModifier>("dockPreviewActivationModifier", default: .option)
    static let showWindowsFromCurrentSpaceOnly = Key<Bool>("showWindowsFromCurrentSpaceOnly", default: false)
    static let showWindowsFromCurrentMonitorOnly = Key<Bool>("showWindowsFromCurrentMonitorOnly", default: false)
    static let windowPreviewSortOrder = Key<WindowPreviewSortOrder>("windowPreviewSortOrder", default: .recentlyUsed)
    static let showWindowsFromCurrentSpaceOnlyInSwitcher = Key<Bool>("showWindowsFromCurrentSpaceOnlyInSwitcher", default: false)
    static let showWindowsFromCurrentMonitorOnlyInSwitcher = Key<Bool>("showWindowsFromCurrentMonitorOnlyInSwitcher", default: false)
    static let windowSwitcherSortOrder = Key<WindowPreviewSortOrder>("windowSwitcherSortOrder", default: .recentlyUsed)
    static let showWindowsFromCurrentSpaceOnlyInCmdTab = Key<Bool>("showWindowsFromCurrentSpaceOnlyInCmdTab", default: false)
    static let showWindowsFromCurrentMonitorOnlyInCmdTab = Key<Bool>("showWindowsFromCurrentMonitorOnlyInCmdTab", default: false)
    static let cmdTabSortOrder = Key<WindowPreviewSortOrder>("cmdTabSortOrder", default: .recentlyUsed)
    static let sortMinimizedToEnd = Key<Bool>("sortMinimizedToEnd", default: false)
    static let enableCmdTabEnhancements = Key<Bool>("enableCmdTabEnhancements", default: false)
    static let cmdTabAutoSelectFirstWindow = Key<Bool>("cmdTabAutoSelectFirstWindow", default: false)
    static let cmdTabCycleKey = Key<UInt16>("cmdTabCycleKey", default: UInt16(kVK_ANSI_A))
    static let cmdTabBackwardCycleKey = Key<UInt16>("cmdTabBackwardCycleKey", default: UInt16(kVK_ANSI_Grave))
    static let enableMouseHoverInSwitcher = Key<Bool>("enableMouseHoverInSwitcher", default: true)
    static let enableWindowSwitcherEdgeAutoScroll = Key<Bool>("enableWindowSwitcherEdgeAutoScroll", default: true)
    static let mouseHoverAutoScrollSpeed = Key<CGFloat>("mouseHoverAutoScrollSpeed", default: 4.0)
    static let enableDockPreviewEdgeAutoScroll = Key<Bool>("enableDockPreviewEdgeAutoScroll", default: true)
    static let dockPreviewEdgeAutoScrollSpeed = Key<CGFloat>("dockPreviewEdgeAutoScrollSpeed", default: 4.0)
    static let enableCmdTabEdgeAutoScroll = Key<Bool>("enableCmdTabEdgeAutoScroll", default: true)
    static let cmdTabEdgeAutoScrollSpeed = Key<CGFloat>("cmdTabEdgeAutoScrollSpeed", default: 4.0)
    static let keepPreviewOnAppTerminate = Key<Bool>("keepPreviewOnAppTerminate", default: false)
    static let enableVimMotions = Key<Bool>("enableVimMotions", default: false)
    static let passArrowsThroughToSystem = Key<Bool>("passArrowsThroughToSystem", default: false)
    static let enableWindowSwitcherSearch = Key<Bool>("enableWindowSwitcherSearch", default: false)
    static let focusSearchOnWindowSwitcherOpen = Key<Bool>("focusSearchOnWindowSwitcherOpen", default: false)
    static let searchTriggerKey = Key<UInt16>("searchTriggerKey", default: UInt16(kVK_ANSI_Slash))
    static let compactModeTitleFormat = Key<CompactModeTitleFormat>("compactModeTitleFormat", default: .appNameAndTitle)
    static let compactModeItemSize = Key<CompactModeItemSize>("compactModeItemSize", default: .medium)
    static let compactModeHideTrafficLights = Key<Bool>("compactModeHideTrafficLights", default: false)
    static let compactModeWidth = Key<CGFloat>("compactModeWidth", default: 500)
    static let enableHoverActionsInCompactMode = Key<Bool>("enableHoverActionsInCompactMode", default: false)
    static let showWindowlessAppQuitButton = Key<Bool>("showWindowlessAppQuitButton", default: true)

    // Per-feature compact mode thresholds (0 = disabled, 1+ = enable when window count >= threshold)
    static let windowSwitcherCompactThreshold = Key<Int>("windowSwitcherCompactThreshold", default: 0)
    static let dockPreviewCompactThreshold = Key<Int>("dockPreviewCompactThreshold", default: 0)
    static let cmdTabCompactThreshold = Key<Int>("cmdTabCompactThreshold", default: 0)
    static let searchFuzziness = Key<Int>("searchFuzziness", default: 3)
    static let useClassicWindowOrdering = Key<Bool>("useClassicWindowOrdering", default: true)
    static let includeHiddenWindowsInSwitcher = Key<Bool>("includeHiddenWindowsInSwitcher", default: true)
    static let includeHiddenWindowsInDockPreview = Key<Bool>("includeHiddenWindowsInDockPreview", default: true)
    static let includeHiddenWindowsInCmdTab = Key<Bool>("includeHiddenWindowsInCmdTab", default: true)
    static let showWindowlessAppsInSwitcher = Key<Bool>("showWindowlessAppsInSwitcher", default: true)
    static let excludeWindowlessAppsFromCurrentMonitorSwitcherScopes = Key<Bool>("excludeWindowlessAppsFromCurrentMonitorSwitcherScopes", default: false)
    static let excludeWindowlessAppsFromCurrentSpaceSwitcherScopes = Key<Bool>("excludeWindowlessAppsFromCurrentSpaceSwitcherScopes", default: false)
    static let showWindowlessAppsInDockPreview = Key<Bool>("showWindowlessAppsInDockPreview", default: false)
    static let showWindowlessAppsInCmdTab = Key<Bool>("showWindowlessAppsInCmdTab", default: false)
    static let windowlessAppActivationMode = Key<WindowlessAppActivationMode>("windowlessAppActivationMode", default: .simulateDockClick)
    static let ignoreAppsWithSingleWindow = Key<Bool>("ignoreAppsWithSingleWindow", default: false)
    static let ignoreAppsWithSingleWindowInCmdTab = Key<Bool>("ignoreAppsWithSingleWindowInCmdTab", default: false)
    static let groupAppInstancesInDock = Key<Bool>("groupAppInstancesInDock", default: true)
    static let collapseNativeTabsIntoSingleWindow = Key<Bool>("collapseNativeTabsIntoSingleWindow", default: false)
    static let showMenuBarIcon = Key<Bool>("showMenuBarIcon", default: true)
    static let openWindowSwitcherFromMenuBarIcon = Key<Bool>("openWindowSwitcherFromMenuBarIcon", default: false)
    static let menuBarIconWindowSwitcherClick = Key<MenuBarIconWindowSwitcherClick>("menuBarIconWindowSwitcherClick", default: .leftClick)
    static let hideDockDoorProBanner = Key<Bool>("hideDockDoorProBanner", default: false)
    static let raisedWindowLevel = Key<Bool>("raisedWindowLevel", default: true)
    static let launched = Key<Bool>("launched", default: false)
    static let reopenSettingsAfterRestart = Key<Bool>("reopenSettingsAfterRestart", default: false)
    static let disableMinWindowSizeFilter = Key<Bool>("disableMinWindowSizeFilter", default: false)
    static let Int64maskCommand = Key<Int>("Int64maskCommand", default: 1_048_840)
    static let Int64maskControl = Key<Int>("Int64maskControl", default: 262_401)
    static let Int64maskAlternate = Key<Int>("Int64maskAlternate", default: 524_576)
    static let UserKeybind = Key<UserKeyBind>("UserKeybind", default: UserKeyBind(keyCode: 48, modifierFlags: Defaults[.Int64maskAlternate]))

    static let showAppName = Key<Bool>("showAppName", default: true)
    static let appNameStyle = Key<AppNameStyle>("appNameStyle", default: .default)
    static let selectionOpacity = Key<CGFloat>("selectionOpacity", default: 0.4)
    static let unselectedContentOpacity = Key<CGFloat>("unselectedContentOpacity", default: 0.75)
    static let hoverHighlightColor = Key<Color?>("hoverHighlightColor", default: nil)
    static let dockPreviewBackgroundOpacity = Key<CGFloat>("dockPreviewBackgroundOpacity", default: 1.0)
    static let hidePreviewCardBackground = Key<Bool>("hidePreviewCardBackground", default: false)
    static let hideHoverContainerBackground = Key<Bool>("hideHoverContainerBackground", default: false)
    static let hideWidgetContainerBackground = Key<Bool>("hideWidgetContainerBackground", default: false)
    static let useOpaquePreviewBackground = Key<Bool>("useOpaquePreviewBackground", default: false)
    static let customBackgroundColor = Key<Color?>("customBackgroundColor", default: nil)
    static let appAppearanceMode = Key<AppAppearanceMode>("appAppearanceMode", default: .system)
    static let showActiveWindowBorder = Key<Bool>("showActiveWindowBorder", default: false)
    static let fullSizePreviewOpacity = Key<CGFloat>("fullSizePreviewOpacity", default: 1.0)
    static let fullSizePreviewFadeInDuration = Key<CGFloat>("fullSizePreviewFadeInDuration", default: 0)
    static let fullSizePreviewFadeOutDuration = Key<CGFloat>("fullSizePreviewFadeOutDuration", default: 0)
    static let enableFullSizePreviewBackdropBlur = Key<Bool>("enableFullSizePreviewBackdropBlur", default: false)
    static let showFullSizePreviewBorder = Key<Bool>("showFullSizePreviewBorder", default: false)

    // MARK: - Glass Effect

    static let dockBackgroundStyle = Key<DockBackgroundStyle>("dockBackgroundStyle", default: .liquidGlass)
    static let dockGlassOpacity = Key<CGFloat>("dockGlassOpacity", default: 0.95)
    static let dockGlassBlurRadius = Key<CGFloat>("dockGlassBlurRadius", default: 0)
    static let dockGlassSaturation = Key<CGFloat>("dockGlassSaturation", default: 1.8)
    static let dockGlassVariant = Key<Int>("dockGlassVariant", default: 4)
    static let dockBackgroundTintOpacity = Key<CGFloat>("dockBackgroundTintOpacity", default: 0.18)
    static let dockBackgroundBorderOpacity = Key<CGFloat>("dockBackgroundBorderOpacity", default: 0.15)
    static let dockBackgroundBorderWidth = Key<CGFloat>("dockBackgroundBorderWidth", default: 1)
    static let dockBackgroundMaterial = Key<DockBackgroundMaterial>("dockBackgroundMaterial", default: .ultraThin)

    // MARK: - Dock Preview Appearance Settings

    static let showWindowTitle = Key<Bool>("showWindowTitle", default: true)
    static let showAppIconOnly = Key<Bool>("showAppIconOnly", default: false)
    static let windowTitleDisplayCondition = Key<WindowTitleDisplayCondition>("windowTitleDisplayCondition", default: .all)
    static let windowTitleVisibility = Key<WindowTitleVisibility>("windowTitleVisibility", default: .alwaysVisible)
    static let windowTitlePosition = Key<WindowTitlePosition>("windowTitlePosition", default: .bottomLeft)
    static let titleOverflowStyle = Key<TitleOverflowStyle>("titleOverflowStyle", default: .truncateMiddle)
    static let windowTitleFontSize = Key<WindowTitleFontSize>("windowTitleFontSize", default: .system)
    static let trafficLightButtonsVisibility = Key<TrafficLightButtonsVisibility>("trafficLightButtonsVisibility", default: .dimmedOnPreviewHover)
    static let trafficLightButtonsPosition = Key<TrafficLightButtonsPosition>("trafficLightButtonsPosition", default: .topLeft)
    static let enabledTrafficLightButtons = Key<Set<WindowAction>>("enabledTrafficLightButtons", default: [.quit, .close, .minimize, .toggleFullScreen])
    static let useMonochromeTrafficLights = Key<Bool>("useMonochromeTrafficLights", default: false)
    static let trafficLightButtonScale = Key<CGFloat>("trafficLightButtonScale", default: 1.0)
    static let dimMinimizedHiddenPreviews = Key<Bool>("showMinimizedHiddenLabels", default: true)
    static let didMigrateWindowStateIndicatorPlacement = Key<Bool>("didMigrateWindowStateIndicatorPlacement", default: false)
    static let showDockPreviewSpaceNumberIndicator = Key<Bool>("showDockPreviewSpaceNumberIndicator", default: true)
    static let highlightDockPreviewCurrentSpaceIndicator = Key<Bool>("highlightDockPreviewCurrentSpaceIndicator", default: false)
    static let dockPreviewWindowStateIndicatorPlacement = Key<WindowStateIndicatorPlacement>("dockPreviewWindowStateIndicatorPlacement", default: .onWindowPreviews)
    static let disableDockStyleWindowStateIndicator = Key<Bool>("disableDockStyleSpaceNumberIndicator", default: true)
    static let swapDockPreviewTrafficLightsAndWindowStateIndicator = Key<Bool>("swapDockPreviewTrafficLightsAndWindowStateIndicator", default: false)
    static let limitDockPreviewIndicatorSwapToCompactMode = Key<Bool>("limitDockPreviewIndicatorSwapToCompactMode", default: false)

    // MARK: - Window Switcher Appearance Settings

    static let switcherShowAppHeader = Key<Bool>("switcherShowAppHeader", default: true)
    static let switcherShowWindowTitle = Key<Bool>("switcherShowWindowTitle", default: true)
    static let switcherWindowTitleVisibility = Key<WindowTitleVisibility>("switcherWindowTitleVisibility", default: .alwaysVisible)
    static let switcherAppIconSize = Key<CGFloat>("switcherAppIconSize", default: 0)
    static let switcherTrafficLightButtonsVisibility = Key<TrafficLightButtonsVisibility>("switcherTrafficLightButtonsVisibility", default: .dimmedOnPreviewHover)
    static let switcherEnabledTrafficLightButtons = Key<Set<WindowAction>>("switcherEnabledTrafficLightButtons", default: [.quit, .close, .minimize, .toggleFullScreen])
    static let switcherUseMonochromeTrafficLights = Key<Bool>("switcherUseMonochromeTrafficLights", default: false)
    static let switcherUseEmbeddedDockPreviewElements = Key<Bool>("switcherUseEmbeddedDockPreviewElements", default: false)
    static let switcherDisableDockStyleTrafficLights = Key<Bool>("switcherDisableDockStyleTrafficLights", default: false)
    static let showSwitcherSpaceNumberIndicator = Key<Bool>("showSwitcherSpaceNumberIndicator", default: true)
    static let highlightSwitcherCurrentSpaceIndicator = Key<Bool>("highlightSwitcherCurrentSpaceIndicator", default: false)
    static let switcherWindowStateIndicatorPlacement = Key<WindowStateIndicatorPlacement>("switcherWindowStateIndicatorPlacement", default: .onWindowPreviews)
    static let switcherDisableDockStyleWindowStateIndicator = Key<Bool>("switcherDisableDockStyleSpaceNumberIndicator", default: true)
    static let swapSwitcherTrafficLightsAndWindowStateIndicator = Key<Bool>("swapSwitcherTrafficLightsAndWindowStateIndicator", default: false)
    static let limitSwitcherIndicatorSwapToCompactMode = Key<Bool>("limitSwitcherIndicatorSwapToCompactMode", default: false)

    // MARK: - Cmd+Tab Appearance Settings

    static let cmdTabShowAppName = Key<Bool>("cmdTabShowAppName", default: true)
    static let cmdTabAppNameStyle = Key<AppNameStyle>("cmdTabAppNameStyle", default: .default)
    static let cmdTabShowAppIconOnly = Key<Bool>("cmdTabShowAppIconOnly", default: false)
    static let cmdTabShowWindowTitle = Key<Bool>("cmdTabShowWindowTitle", default: true)
    static let cmdTabWindowTitleVisibility = Key<WindowTitleVisibility>("cmdTabWindowTitleVisibility", default: .alwaysVisible)
    static let cmdTabWindowTitlePosition = Key<WindowTitlePosition>("cmdTabWindowTitlePosition", default: .bottomLeft)
    static let cmdTabTrafficLightButtonsVisibility = Key<TrafficLightButtonsVisibility>("cmdTabTrafficLightButtonsVisibility", default: .dimmedOnPreviewHover)
    static let cmdTabTrafficLightButtonsPosition = Key<TrafficLightButtonsPosition>("cmdTabTrafficLightButtonsPosition", default: .topLeft)
    static let cmdTabEnabledTrafficLightButtons = Key<Set<WindowAction>>("cmdTabEnabledTrafficLightButtons", default: [.quit, .close, .minimize, .toggleFullScreen])
    static let cmdTabUseMonochromeTrafficLights = Key<Bool>("cmdTabUseMonochromeTrafficLights", default: false)
    static let cmdTabControlPosition = Key<WindowSwitcherControlPosition>("cmdTabControlPosition", default: .topTrailing)
    static let cmdTabUseEmbeddedDockPreviewElements = Key<Bool>("cmdTabUseEmbeddedDockPreviewElements", default: false)
    static let cmdTabDisableDockStyleTrafficLights = Key<Bool>("cmdTabDisableDockStyleTrafficLights", default: false)
    static let cmdTabDisableDockStyleTitles = Key<Bool>("cmdTabDisableDockStyleTitles", default: false)
    static let showCmdTabSpaceNumberIndicator = Key<Bool>("showCmdTabSpaceNumberIndicator", default: true)
    static let highlightCmdTabCurrentSpaceIndicator = Key<Bool>("highlightCmdTabCurrentSpaceIndicator", default: false)
    static let cmdTabWindowStateIndicatorPlacement = Key<WindowStateIndicatorPlacement>("cmdTabWindowStateIndicatorPlacement", default: .onWindowPreviews)
    static let cmdTabDisableDockStyleWindowStateIndicator = Key<Bool>("cmdTabDisableDockStyleSpaceNumberIndicator", default: true)
    static let swapCmdTabTrafficLightsAndWindowStateIndicator = Key<Bool>("swapCmdTabTrafficLightsAndWindowStateIndicator", default: false)
    static let limitCmdTabIndicatorSwapToCompactMode = Key<Bool>("limitCmdTabIndicatorSwapToCompactMode", default: false)

    static let previewMaxColumns = Key<Int>("previewMaxColumns", default: 2) // For left/right dock
    static let previewMaxRows = Key<Int>("previewMaxRows", default: 1) // For bottom dock only
    static let switcherMaxRows = Key<Int>("switcherMaxRows", default: 8) // For window switcher
    static let switcherIgnoreScreenLimit = Key<Bool>("switcherIgnoreScreenLimit", default: false)
    static let windowSwitcherScrollDirection = Key<WindowSwitcherScrollDirection>("windowSwitcherScrollDirection", default: .vertical)

    static let windowSwitcherPlacementStrategy = Key<WindowSwitcherPlacementStrategy>("windowSwitcherPlacementStrategy", default: .screenWithMouse)
    static let windowSwitcherControlPosition = Key<WindowSwitcherControlPosition>("windowSwitcherControlPosition", default: .topTrailing)
    static let windowSwitcherHorizontalAnchor = Key<WindowSwitcherHorizontalAnchor>("windowSwitcherHorizontalAnchor", default: .center)
    static let windowSwitcherVerticalAnchor = Key<WindowSwitcherVerticalAnchor>("windowSwitcherVerticalAnchor", default: .center)
    static let enableShiftWindowSwitcherPlacement = Key<Bool>("enableShiftWindowSwitcherPlacement", default: false)
    static let windowSwitcherHorizontalOffsetPercent = Key<CGFloat>("windowSwitcherHorizontalOffsetPercent", default: 0)
    static let windowSwitcherVerticalOffsetPercent = Key<CGFloat>("windowSwitcherVerticalOffsetPercent", default: 0)
    static let dockPreviewControlPosition = Key<WindowSwitcherControlPosition>("dockPreviewControlPosition", default: .topTrailing)
    static let pinnedScreenIdentifier = Key<String>("pinnedScreenIdentifier", default: NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? String ?? "")

    // MARK: - Mouse Follows Focus

    static let mouseFollowsFocusMode = Key<MouseFollowsFocusMode>("mouseFollowsFocusMode", default: .never)

    // MARK: - Window Switcher Filters

    static let limitSwitcherToFrontmostApp = Key<Bool>("limitSwitcherToFrontmostApp", default: false)
    static let fullscreenAppBlacklist = Key<[String]>("fullscreenAppBlacklist", default: [])

    // MARK: - Filters

    static let appNameFilters = Key<[String]>("appNameFilters", default: [])
    static let windowTitleFilters = Key<[String]>("windowTitleFilters", default: [])
    static let widgetAppFilters = Key<[String]>("widgetAppFilters", default: [])
    static let groupedAppsInSwitcher = Key<[String]>("groupedAppsInSwitcher", default: [])
    static let customAppDirectories = Key<[String]>("customAppDirectories", default: [])
    static let filteredCalendarIdentifiers = Key<[String]>("filteredCalendarIdentifiers", default: [])
    static let hasSeenCmdTabFocusHint = Key<Bool>("hasSeenCmdTabFocusHint", default: false)
    static let disableImagePreview = Key<Bool>("disableImagePreview", default: false)
    static let lastKnownScreenRecordingPermission = Key<Bool>("lastKnownScreenRecordingPermission", default: false)
    static let debugMode = Key<Bool>("debugMode", default: false)
    static let limitDebugLogFileSize = Key<Bool>("limitDebugLogFileSize", default: true)
    static let debugLogMaximumSizeMB = Key<Double>("debugLogMaximumSizeMB", default: 10)

    // MARK: - Active App Indicator

    static let showActiveAppIndicator = Key<Bool>("showActiveAppIndicator", default: false)
    static let activeAppIndicatorColor = Key<Color>("activeAppIndicatorColor", default: Color.accentColor)
    static let activeAppIndicatorAutoSize = Key<Bool>("activeAppIndicatorAutoSize", default: true)
    static let activeAppIndicatorAutoLength = Key<Bool>("activeAppIndicatorAutoLength", default: false)
    static let activeAppIndicatorHeight = Key<CGFloat>("activeAppIndicatorHeight", default: 4.0)
    static let activeAppIndicatorOffset = Key<CGFloat>("activeAppIndicatorOffset", default: 5.0)
    static let activeAppIndicatorLength = Key<CGFloat>("activeAppIndicatorLength", default: 40.0)
    static let activeAppIndicatorShift = Key<CGFloat>("activeAppIndicatorShift", default: 0.0)

    // MARK: - Trackpad Gestures

    static let gestureSwipeThreshold = Key<CGFloat>("gestureSwipeThreshold", default: 50)

    // Dock Preview Gestures (towards/away from dock - automatically translates based on dock position)
    static let enableDockPreviewGestures = Key<Bool>("enableDockPreviewGestures", default: true)
    static let dockSwipeTowardsDockAction = Key<WindowAction>("dockSwipeTowardsDockAction", default: .minimize)
    static let dockSwipeAwayFromDockAction = Key<WindowAction>("dockSwipeAwayFromDockAction", default: .maximize)

    // Window Switcher Gestures (up/down only - switcher is always horizontally centered)
    static let enableWindowSwitcherGestures = Key<Bool>("enableWindowSwitcherGestures", default: true)
    static let switcherSwipeUpAction = Key<WindowAction>("switcherSwipeUpAction", default: .maximize)
    static let switcherSwipeDownAction = Key<WindowAction>("switcherSwipeDownAction", default: .minimize)

    // MARK: - Middle Click Action

    static let middleClickAction = Key<WindowAction>("middleClickAction", default: .close)

    // MARK: - Spaces

    static let enableSpaceIndicatorWindowMoving = Key<Bool>("enableSpaceIndicatorWindowMoving", default: true)
    static let spaceMenuDisplayMode = Key<SpaceMenuDisplayMode>("spaceMenuDisplayMode", default: .numberOnly)
    static let switchToDestinationSpaceAfterMoving = Key<Bool>("switchToDestinationSpaceAfterMoving", default: false)
    static let showUnavailableSpacesInMenu = Key<Bool>("showUnavailableSpacesInMenu", default: false)
    static let showCurrentSpaceBadgeInMenu = Key<Bool>("showCurrentSpaceBadgeInMenu", default: false)
    static let enableSpacesShortcuts = Key<Bool>("enableSpacesShortcuts", default: false)

    // MARK: - Window Preview Keyboard Shortcuts

    static let cmdShortcuts = Key<[CmdShortcut]>("cmdShortcuts", default: CmdShortcut.defaultShortcuts)
    static let movingResizingPostActionBehavior = Key<Bool>("movingResizingPostActionBehavior", default: true)
    static let hidingPostActionBehavior = Key<Bool>("hidingPostActionBehavior", default: true)
    static let unhidingPostActionBehavior = Key<Bool>("unhidingPostActionBehavior", default: true)
    static let closingPostActionBehavior = Key<Bool>("closingPostActionBehavior", default: true)
    static let newWindowPostActionBehavior = Key<Bool>("newWindowPostActionBehavior", default: false)
    static let moveResizeBringToForeground = Key<Bool>("moveResizeBringToForeground", default: true)

    // MARK: - Window Switcher Selection Key

    static let windowSwitcherSelectionKeyCode = Key<UInt16>("windowSwitcherSelectionKeyCode", default: UInt16(kVK_Return))

    // MARK: - Alternate Window Switcher Shortcuts

    static let alternateSwitcherShortcuts = Key<[AlternateSwitcherShortcut]>(
        "alternateSwitcherShortcuts",
        default: AlternateSwitcherShortcut.defaultShortcuts
    )
    static let persistentSwitcherShortcuts = Key<[PersistentSwitcherShortcut]>(
        "persistentSwitcherShortcuts",
        default: PersistentSwitcherShortcut.defaultShortcuts
    )
    static let persistentSwitcherStartsUnfocused = Key<Bool>("persistentSwitcherStartsUnfocused", default: false)
    static let lastFocusedWindowShortcuts = Key<[PersistentSwitcherShortcut]>(
        "lastFocusedWindowShortcuts",
        default: [PersistentSwitcherShortcut(mode: .globalAllWindows)]
    )
}

// MARK: Dock Locking

enum DockLockModifier: Int, CaseIterable, Codable, Defaults.Serializable {
    case option = 0
    case control = 1
    case shift = 2
    case command = 3

    var cgEventFlag: CGEventFlags {
        switch self {
        case .option: .maskAlternate
        case .control: .maskControl
        case .shift: .maskShift
        case .command: .maskCommand
        }
    }

    var localizedName: String {
        switch self {
        case .option: String(localized: "Option (\u{2325})")
        case .control: String(localized: "Control (\u{2303})")
        case .shift: String(localized: "Shift (\u{21E7})")
        case .command: String(localized: "Command (\u{2318})")
        }
    }
}

// MARK: Display Configurations

enum WindowImageCaptureQuality: String, CaseIterable, Defaults.Serializable {
    case nominal
    case best

    var localizedName: String {
        switch self {
        case .nominal:
            String(localized: "Improved performance (nominal)", comment: "Window image capture quality option")
        case .best:
            String(localized: "Best quality (full resolution)", comment: "Window image capture quality option")
        }
    }
}

enum WindowTitleDisplayCondition: String, CaseIterable, Defaults.Serializable {
    case all
    case dockPreviewsOnly
    case windowSwitcherOnly

    var localizedName: String {
        switch self {
        case .all:
            String(localized: "Dock Previews & Window Switcher", comment: "Preview window title display condition option")
        case .dockPreviewsOnly:
            String(localized: "Dock Previews only", comment: "Preview window title condition display option")
        case .windowSwitcherOnly:
            String(localized: "Window Switcher only", comment: "Preview window title condition display option")
        }
    }
}

enum WindowTitlePosition: String, CaseIterable, Defaults.Serializable {
    case bottomLeft
    case bottomRight
    case topRight
    case topLeft

    var localizedName: String {
        switch self {
        case .bottomLeft:
            String(localized: "Bottom Left", comment: "Preview window title position option")
        case .bottomRight:
            String(localized: "Bottom Right", comment: "Preview window title position option")
        case .topRight:
            String(localized: "Top Right", comment: "Preview window title position option")
        case .topLeft:
            String(localized: "Top Left", comment: "Preview window title position option")
        }
    }
}

enum AppNameStyle: String, CaseIterable, Defaults.Serializable {
    case `default`
    case shadowed
    case popover

    var localizedName: String {
        switch self {
        case .default:
            String(localized: "Default", comment: "Preview title style option")
        case .shadowed:
            String(localized: "Shadowed", comment: "Preview title style option")
        case .popover:
            String(localized: "Popover", comment: "Preview title style option")
        }
    }
}

enum WindowTitleVisibility: String, CaseIterable, Defaults.Serializable {
    case whenHoveringPreview
    case alwaysVisible

    var localizedName: String {
        switch self {
        case .whenHoveringPreview:
            String(localized: "When hovering over the preview", comment: "Window title visibility option")
        case .alwaysVisible:
            String(localized: "Always visible", comment: "Window title visibility option")
        }
    }
}

enum WindowStateIndicatorPlacement: String, CaseIterable, Defaults.Serializable {
    case off
    case onWindowPreviews
    case nextToTrafficLightButtons

    var localizedName: String {
        switch self {
        case .off:
            String(localized: "Off", comment: "Window state indicator placement option")
        case .onWindowPreviews:
            String(localized: "On Window Previews", comment: "Window state indicator placement option")
        case .nextToTrafficLightButtons:
            String(localized: "Next to Traffic Light Buttons", comment: "Window state indicator placement option")
        }
    }
}

enum SpaceMenuDisplayMode: String, CaseIterable, Defaults.Serializable {
    case numberOnly
    case fullName

    var localizedName: String {
        switch self {
        case .numberOnly:
            String(localized: "Space number only", comment: "Space destination menu display mode")
        case .fullName:
            String(localized: "Full name", comment: "Space destination menu display mode")
        }
    }
}

enum TitleOverflowStyle: String, CaseIterable, Defaults.Serializable {
    case truncateTail
    case truncateMiddle
    case truncateHead
    case marquee

    var localizedName: String {
        switch self {
        case .truncateTail:
            String(localized: "Truncate end", comment: "Title overflow style option")
        case .truncateMiddle:
            String(localized: "Truncate middle", comment: "Title overflow style option")
        case .truncateHead:
            String(localized: "Truncate start", comment: "Title overflow style option")
        case .marquee:
            String(localized: "Marquee (scrolling)", comment: "Title overflow style option")
        }
    }
}

enum TrafficLightButtonsVisibility: String, CaseIterable, Defaults.Serializable {
    case never
    case dimmedOnPreviewHover
    case fullOpacityOnPreviewHover
    case dimmedUntilButtonHover
    case alwaysVisible

    func isVisible(hoveringOverParentWindow: Bool, mockPreviewActive: Bool) -> Bool {
        switch self {
        case .never:
            false
        case .dimmedOnPreviewHover, .fullOpacityOnPreviewHover:
            hoveringOverParentWindow || mockPreviewActive
        case .dimmedUntilButtonHover, .alwaysVisible:
            true
        }
    }

    var localizedName: String {
        switch self {
        case .never:
            String(localized: "Never visible", comment: "Traffic light buttons visibility option")
        case .dimmedOnPreviewHover:
            String(localized: "On window hover; Dimmed until button hover", comment: "Traffic light buttons visibility option")
        case .fullOpacityOnPreviewHover:
            String(localized: "On window hover; Full opacity", comment: "Traffic light buttons visibility option")
        case .dimmedUntilButtonHover:
            String(localized: "Always visible; Dimmed until button hover", comment: "Traffic light buttons visibility option")
        case .alwaysVisible:
            String(localized: "Always visible; Full opacity", comment: "Traffic light buttons visibility option")
        }
    }
}

enum TrafficLightButtonsPosition: String, CaseIterable, Defaults.Serializable {
    case topLeft
    case topRight
    case bottomRight
    case bottomLeft

    var localizedName: String {
        switch self {
        case .topLeft:
            String(localized: "Top Left", comment: "Traffic light buttons position option")
        case .topRight:
            String(localized: "Top Right", comment: "Traffic light buttons position option")
        case .bottomRight:
            String(localized: "Bottom Right", comment: "Traffic light buttons position option")
        case .bottomLeft:
            String(localized: "Bottom Left", comment: "Traffic light buttons position option")
        }
    }
}

enum WindowSwitcherPlacementStrategy: String, CaseIterable, Defaults.Serializable {
    case screenWithMouse
    case screenWithLastActiveWindow
    case pinnedToScreen

    var localizedName: String {
        switch self {
        case .screenWithMouse:
            String(localized: "Screen with mouse", comment: "Window switcher placement option")
        case .screenWithLastActiveWindow:
            String(localized: "Screen with last active window", comment: "Window switcher placement option")
        case .pinnedToScreen:
            String(localized: "Pinned to screen", comment: "Window switcher placement option")
        }
    }
}

enum WindowSwitcherVerticalAnchor: String, CaseIterable, Defaults.Serializable {
    case top
    case center
    case bottom

    var localizedName: String {
        switch self {
        case .top:
            String(localized: "Top", comment: "Window switcher vertical anchor option")
        case .center:
            String(localized: "Center", comment: "Window switcher vertical anchor option")
        case .bottom:
            String(localized: "Bottom", comment: "Window switcher vertical anchor option")
        }
    }
}

enum WindowSwitcherHorizontalAnchor: String, CaseIterable, Defaults.Serializable {
    case left
    case center
    case right

    var localizedName: String {
        switch self {
        case .left:
            String(localized: "Left", comment: "Window switcher horizontal anchor option")
        case .center:
            String(localized: "Center", comment: "Window switcher horizontal anchor option")
        case .right:
            String(localized: "Right", comment: "Window switcher horizontal anchor option")
        }
    }
}

enum MouseFollowsFocusMode: String, CaseIterable, Defaults.Serializable {
    case never
    case always
    case differentDisplayOnly

    var localizedName: String {
        switch self {
        case .never:
            String(localized: "Never", comment: "Mouse follows focus mode option")
        case .always:
            String(localized: "Always", comment: "Mouse follows focus mode option")
        case .differentDisplayOnly:
            String(localized: "Only when switching displays", comment: "Mouse follows focus mode option")
        }
    }
}

enum MenuBarIconWindowSwitcherClick: String, CaseIterable, Defaults.Serializable {
    case leftClick
    case rightClick

    var localizedName: String {
        switch self {
        case .leftClick:
            String(localized: "Left click activates Window Switcher; right click activates DockDoor menu")
        case .rightClick:
            String(localized: "Right click activates Window Switcher; left click activates DockDoor menu")
        }
    }
}

enum WindowSwitcherControlPosition: String, CaseIterable, Defaults.Serializable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing
    case centeredTitleTopControlsBottom
    case centeredControlsTopTitleBottom
    case diagonalTopLeftBottomRight
    case diagonalTopRightBottomLeft
    case diagonalBottomLeftTopRight
    case diagonalBottomRightTopLeft
    case parallelTopLeftBottomLeft
    case parallelTopRightBottomRight
    case parallelBottomLeftTopLeft
    case parallelBottomRightTopRight

    var localizedName: String {
        switch self {
        case .topLeading:
            String(localized: "At top - Title on left, controls on right")
        case .topTrailing:
            String(localized: "At top - Controls on left, title on right")
        case .bottomLeading:
            String(localized: "At bottom - Title on left, controls on right")
        case .bottomTrailing:
            String(localized: "At bottom - Controls on left, title on right")
        case .centeredTitleTopControlsBottom:
            String(localized: "Centered - Title top, controls bottom")
        case .centeredControlsTopTitleBottom:
            String(localized: "Centered - Controls top, title bottom")
        case .diagonalTopLeftBottomRight:
            String(localized: "Diagonal - Title top left, controls bottom right")
        case .diagonalTopRightBottomLeft:
            String(localized: "Diagonal - Title top right, controls bottom left")
        case .diagonalBottomLeftTopRight:
            String(localized: "Diagonal - Title bottom left, controls top right")
        case .diagonalBottomRightTopLeft:
            String(localized: "Diagonal - Title bottom right, controls top left")
        case .parallelTopLeftBottomLeft:
            String(localized: "Parallel - Title top left, controls bottom left")
        case .parallelTopRightBottomRight:
            String(localized: "Parallel - Title top right, controls bottom right")
        case .parallelBottomLeftTopLeft:
            String(localized: "Parallel - Title bottom left, controls top left")
        case .parallelBottomRightTopRight:
            String(localized: "Parallel - Title bottom right, controls top right")
        }
    }

    var showsOnTop: Bool {
        switch self {
        case .topLeading, .topTrailing,
             .centeredTitleTopControlsBottom, .centeredControlsTopTitleBottom,
             .diagonalTopLeftBottomRight, .diagonalTopRightBottomLeft,
             .diagonalBottomLeftTopRight, .diagonalBottomRightTopLeft,
             .parallelTopLeftBottomLeft, .parallelTopRightBottomRight,
             .parallelBottomLeftTopLeft, .parallelBottomRightTopRight:
            true
        case .bottomLeading, .bottomTrailing:
            false
        }
    }

    var showsOnBottom: Bool {
        switch self {
        case .bottomLeading, .bottomTrailing,
             .centeredTitleTopControlsBottom, .centeredControlsTopTitleBottom,
             .diagonalTopLeftBottomRight, .diagonalTopRightBottomLeft,
             .diagonalBottomLeftTopRight, .diagonalBottomRightTopLeft,
             .parallelTopLeftBottomLeft, .parallelTopRightBottomRight,
             .parallelBottomLeftTopLeft, .parallelBottomRightTopRight:
            true
        case .topLeading, .topTrailing:
            false
        }
    }

    /// Total height added by toolbar row(s) for this position (~38px per row)
    var toolbarHeightOffset: CGFloat {
        let rowHeight: CGFloat = 38
        var offset: CGFloat = 0
        if showsOnTop { offset += rowHeight }
        if showsOnBottom { offset += rowHeight }
        return offset
    }

    var isCentered: Bool {
        switch self {
        case .centeredTitleTopControlsBottom, .centeredControlsTopTitleBottom:
            true
        default:
            false
        }
    }

    var topConfiguration: (isLeadingControls: Bool, showTitle: Bool, showControls: Bool) {
        switch self {
        case .topLeading, .bottomLeading:
            (false, true, true)
        case .topTrailing, .bottomTrailing:
            (true, true, true)
        case .centeredTitleTopControlsBottom:
            (false, true, false)
        case .centeredControlsTopTitleBottom:
            (false, false, true)
        case .diagonalTopLeftBottomRight, .parallelTopLeftBottomLeft:
            (false, true, false)
        case .diagonalTopRightBottomLeft, .parallelTopRightBottomRight:
            (true, true, false)
        case .diagonalBottomLeftTopRight, .parallelBottomRightTopRight:
            (false, false, true)
        case .diagonalBottomRightTopLeft, .parallelBottomLeftTopLeft:
            (true, false, true)
        }
    }

    var bottomConfiguration: (isLeadingControls: Bool, showTitle: Bool, showControls: Bool) {
        switch self {
        case .topLeading, .bottomLeading:
            (false, true, true)
        case .topTrailing, .bottomTrailing:
            (true, true, true)
        case .centeredTitleTopControlsBottom:
            (false, false, true)
        case .centeredControlsTopTitleBottom:
            (false, true, false)
        case .diagonalTopLeftBottomRight:
            (false, false, true)
        case .diagonalTopRightBottomLeft:
            (true, false, true)
        case .diagonalBottomLeftTopRight:
            (false, true, false)
        case .diagonalBottomRightTopLeft:
            (true, true, false)
        case .parallelTopLeftBottomLeft:
            (true, false, true) // controls on left
        case .parallelTopRightBottomRight:
            (false, false, true) // controls on right
        case .parallelBottomLeftTopLeft:
            (false, true, false) // title on left
        case .parallelBottomRightTopRight:
            (true, true, false) // title on right
        }
    }
}

// MARK: Action Configurations

enum PreviewHoverAction: String, CaseIterable, Defaults.Serializable {
    case none
    case tap
    case previewFullSize

    var localizedName: String {
        switch self {
        case .none:
            String(localized: "No action", comment: "Window popup hover action option")
        case .tap:
            String(localized: "Simulate a click (open the window)", comment: "Window popup hover action option")
        case .previewFullSize:
            String(localized: "Present a full size preview of the window", comment: "Window popup hover action option")
        }
    }
}

enum AeroShakeAction: String, CaseIterable, Defaults.Serializable {
    case none
    case all
    case except

    var localizedName: String {
        switch self {
        case .none:
            String(localized: "No action", comment: "Aero shake action option")
        case .all:
            String(localized: "Minimize all windows", comment: "Aero shake action option")
        case .except:
            String(localized: "Minimize all windows except the current one", comment: "Aero shake action option")
        }
    }
}

enum DockClickAction: String, CaseIterable, Defaults.Serializable {
    case minimize
    case hide
    case cycleWindows

    var localizedName: String {
        switch self {
        case .minimize:
            String(localized: "Minimize windows", comment: "Dock click action option")
        case .hide:
            String(localized: "Hide application", comment: "Dock click action option")
        case .cycleWindows:
            String(localized: "Cycle through windows", comment: "Dock click action option")
        }
    }
}

enum WindowlessAppActivationMode: String, CaseIterable, Defaults.Serializable {
    case openNewWindow
    case simulateDockClick
    case activateOnly

    var localizedName: String {
        switch self {
        case .openNewWindow:
            String(localized: "Opens a new window", comment: "Windowless app activation mode option")
        case .simulateDockClick:
            String(localized: "Simulates a click", comment: "Windowless app activation mode option")
        case .activateOnly:
            String(localized: "Activates app only", comment: "Windowless app activation mode option")
        }
    }

    var localizedDescription: String {
        switch self {
        case .openNewWindow:
            String(localized: "Automatically sends ⌘N to open a new window when activating an app with no windows.", comment: "Description for open new window setting")
        case .simulateDockClick:
            String(localized: "Simulates clicking the Dock icon when activating an app with no windows.", comment: "Description for dock-click simulation behavior")
        case .activateOnly:
            String(localized: "Performs a plain app activation with no attempts at opening a window.", comment: "Description for activate-only behavior")
        }
    }
}

enum DockPreviewActivationMode: String, CaseIterable, Defaults.Serializable {
    case hover
    case middleClick
    case modifierClick

    var localizedName: String {
        switch self {
        case .hover:
            String(localized: "Hover", comment: "Dock preview activation mode option")
        case .middleClick:
            String(localized: "Middle Click", comment: "Dock preview activation mode option")
        case .modifierClick:
            String(localized: "Modifier Click", comment: "Dock preview activation mode option")
        }
    }
}

enum DockPreviewActivationModifier: String, CaseIterable, Defaults.Serializable {
    case option
    case control
    case shift
    case command

    var localizedName: String {
        switch self {
        case .option:
            String(localized: "Option ⌥", comment: "Dock preview activation modifier option")
        case .control:
            String(localized: "Control ⌃", comment: "Dock preview activation modifier option")
        case .shift:
            String(localized: "Shift ⇧", comment: "Dock preview activation modifier option")
        case .command:
            String(localized: "Command ⌘", comment: "Dock preview activation modifier option")
        }
    }

    var eventFlag: CGEventFlags {
        switch self {
        case .option:
            .maskAlternate
        case .control:
            .maskControl
        case .shift:
            .maskShift
        case .command:
            .maskCommand
        }
    }
}

enum MediaDetectionMode: String, CaseIterable, Defaults.Serializable {
    case universal
    case appleScriptOnly

    var localizedName: String {
        switch self {
        case .universal:
            String(localized: "Universal (any app)", comment: "Media detection mode option")
        case .appleScriptOnly:
            String(localized: "Spotify & Apple Music only", comment: "Media detection mode option")
        }
    }

    var localizedDescription: String {
        switch self {
        case .universal:
            String(localized: "Shows controls for whichever app is currently playing — browsers, third-party players, etc. Only one source is active at a time.", comment: "Media detection mode description")
        case .appleScriptOnly:
            String(localized: "Only shows controls for Spotify and Apple Music. Each app gets its own controls that work independently, even when other apps are playing audio.", comment: "Media detection mode description")
        }
    }
}

enum DockIconScrollBehavior: String, CaseIterable, Defaults.Serializable {
    case activateHide
    case bringAppWindowsToCurrentSpace

    var localizedName: String {
        switch self {
        case .activateHide:
            String(localized: "Activate/Hide", comment: "Dock icon scroll option")
        case .bringAppWindowsToCurrentSpace:
            String(localized: "Bring App Windows to Current Space", comment: "Dock icon scroll option")
        }
    }
}

// Dock icon scroll behavior for Music/Spotify
enum DockIconMediaScrollBehavior: String, CaseIterable, Defaults.Serializable {
    case adjustVolume
    case activateHide

    var localizedName: String {
        switch self {
        case .adjustVolume:
            String(localized: "Adjust volume", comment: "Dock icon media scroll option")
        case .activateHide:
            String(localized: "Activate/Hide (same as other apps)", comment: "Dock icon media scroll option")
        }
    }
}

enum TitleBarCenteredWindowSizingMode: String, CaseIterable, Defaults.Serializable {
    case uniform
    case separate

    var localizedName: String {
        switch self {
        case .uniform:
            String(localized: "Whole window", comment: "Title bar centered window sizing mode")
        case .separate:
            String(localized: "Width & height", comment: "Title bar centered window sizing mode")
        }
    }
}

// Media widget scroll behavior
enum MediaWidgetScrollBehavior: String, CaseIterable, Defaults.Serializable {
    case adjustVolume
    case seekPlayback

    var localizedName: String {
        switch self {
        case .adjustVolume:
            String(localized: "Adjust volume", comment: "Media widget scroll option")
        case .seekPlayback:
            String(localized: "Seek playback (scrub through track)", comment: "Media widget scroll option")
        }
    }
}

enum WindowSwitcherScrollDirection: String, CaseIterable, Defaults.Serializable {
    case horizontal
    case vertical

    var localizedName: String {
        switch self {
        case .horizontal:
            String(localized: "Horizontal", comment: "Scroll direction option")
        case .vertical:
            String(localized: "Vertical", comment: "Scroll direction option")
        }
    }
}

// Media widget scroll direction
enum MediaWidgetScrollDirection: String, CaseIterable, Defaults.Serializable {
    case vertical
    case horizontal

    var localizedName: String {
        switch self {
        case .vertical:
            String(localized: "Vertical", comment: "Media widget scroll direction option")
        case .horizontal:
            String(localized: "Horizontal", comment: "Media widget scroll direction option")
        }
    }
}

enum FolderWidgetSortOrder: String, CaseIterable, Defaults.Serializable {
    case dateModified
    case dateAdded
    case name
    case kind
    case size

    var localizedName: String {
        switch self {
        case .dateModified:
            String(localized: "Date Modified", comment: "Folder widget sort option")
        case .dateAdded:
            String(localized: "Date Added", comment: "Folder widget sort option")
        case .name:
            String(localized: "Name", comment: "Folder widget sort option")
        case .kind:
            String(localized: "Kind", comment: "Folder widget sort option")
        case .size:
            String(localized: "Size", comment: "Folder widget sort option")
        }
    }

    var iconName: String {
        switch self {
        case .dateModified:
            "calendar"
        case .dateAdded:
            "calendar.badge.plus"
        case .name:
            "textformat.abc"
        case .kind:
            "doc"
        case .size:
            "scalemass"
        }
    }
}

enum WindowPreviewSortOrder: String, CaseIterable, Defaults.Serializable, Identifiable {
    case recentlyUsed
    case creationOrder
    case alphabeticalByTitle
    case alphabeticalByAppName

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .recentlyUsed:
            String(localized: "Recently used", comment: "Window preview sort order option")
        case .creationOrder:
            String(localized: "Creation order (fixed)", comment: "Window preview sort order option")
        case .alphabeticalByTitle:
            String(localized: "Alphabetical by title", comment: "Window preview sort order option")
        case .alphabeticalByAppName:
            String(localized: "Grouped by app name", comment: "Window preview sort order option")
        }
    }

    /// Whether this sort order is applicable only for window switcher (multi-app context)
    var isWindowSwitcherOnly: Bool {
        switch self {
        case .alphabeticalByAppName:
            true
        default:
            false
        }
    }
}

enum SwitcherInvocationMode: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case allWindows
    case globalAllWindows
    case activeAppOnly
    case currentSpaceOnly
    case currentMonitorOnly
    case currentMonitorCurrentSpace
    case activeAppCurrentSpace

    var id: String { rawValue }

    static var sortedCases: [SwitcherInvocationMode] {
        allCases.sorted {
            $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending
        }
    }

    var localizedName: String {
        switch self {
        case .allWindows:
            String(localized: "Window Switcher Defaults", comment: "Switcher invocation mode")
        case .globalAllWindows:
            String(localized: "All Windows", comment: "Switcher invocation mode")
        case .activeAppOnly:
            String(localized: "Active App Only", comment: "Switcher invocation mode")
        case .currentSpaceOnly:
            String(localized: "Current Space Only", comment: "Switcher invocation mode")
        case .currentMonitorOnly:
            String(localized: "Current Monitor Only", comment: "Switcher invocation mode")
        case .currentMonitorCurrentSpace:
            String(localized: "Current Monitor + Current Space", comment: "Switcher invocation mode")
        case .activeAppCurrentSpace:
            String(localized: "Active App + Current Space", comment: "Switcher invocation mode")
        }
    }

    var localizedDescription: String {
        switch self {
        case .allWindows:
            String(localized: "Uses your default window switcher settings", comment: "Switcher invocation mode description")
        case .globalAllWindows:
            String(localized: "Shows all eligible windows regardless of Space, display, or frontmost app", comment: "Switcher invocation mode description")
        case .activeAppOnly:
            String(localized: "Shows only windows from the frontmost application", comment: "Switcher invocation mode description")
        case .currentSpaceOnly:
            String(localized: "Shows only windows from the current Space", comment: "Switcher invocation mode description")
        case .currentMonitorOnly:
            String(localized: "Shows only windows from the current monitor", comment: "Switcher invocation mode description")
        case .currentMonitorCurrentSpace:
            String(localized: "Shows only windows from the current monitor in the current Space", comment: "Switcher invocation mode description")
        case .activeAppCurrentSpace:
            String(localized: "Shows only windows from the frontmost app in the current Space", comment: "Switcher invocation mode description")
        }
    }
}

enum LivePreviewQuality: String, CaseIterable, Defaults.Serializable, Identifiable {
    case thumbnail
    case low
    case standard
    case high
    case retina
    case native

    var id: String { rawValue }

    var scaleFactor: Int {
        switch self {
        case .thumbnail: 1
        case .low: 1
        case .standard: 1
        case .high: 1
        case .retina: 2
        case .native: 2
        }
    }

    var useFullResolution: Bool {
        switch self {
        case .thumbnail, .low: false
        case .standard, .high, .retina, .native: true
        }
    }

    var maxDimension: Int {
        switch self {
        case .thumbnail: 320
        case .low: 480
        case .standard: 640
        case .high: 960
        case .retina: 1280
        case .native: 0 // No limit
        }
    }

    var localizedName: String {
        switch self {
        case .thumbnail:
            String(localized: "Thumbnail (320px)")
        case .low:
            String(localized: "Low (480px)")
        case .standard:
            String(localized: "Standard (640px)")
        case .high:
            String(localized: "High (960px)")
        case .retina:
            String(localized: "Retina (1280px)")
        case .native:
            String(localized: "Native (Best)")
        }
    }
}

enum LivePreviewFrameRate: String, CaseIterable, Defaults.Serializable, Identifiable {
    case fps5
    case fps10
    case fps15
    case fps24
    case fps30
    case fps60
    case fps120

    var id: String { rawValue }

    var frameRate: Int32 {
        switch self {
        case .fps5: 5
        case .fps10: 10
        case .fps15: 15
        case .fps24: 24
        case .fps30: 30
        case .fps60: 60
        case .fps120: 120
        }
    }

    var localizedName: String {
        switch self {
        case .fps5:
            String(localized: "5 FPS")
        case .fps10:
            String(localized: "10 FPS")
        case .fps15:
            String(localized: "15 FPS")
        case .fps24:
            String(localized: "24 FPS")
        case .fps30:
            String(localized: "30 FPS")
        case .fps60:
            String(localized: "60 FPS")
        case .fps120:
            String(localized: "120 FPS (ProMotion)")
        }
    }
}

enum CompactModeTitleFormat: String, CaseIterable, Defaults.Serializable, Identifiable {
    case appNameAndTitle // App name on top, window title below
    case titleOnly // Window title only (or app name if no title)
    case appNameOnly // App name only

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .appNameAndTitle:
            String(localized: "App Name + Window Title")
        case .titleOnly:
            String(localized: "Window Title Only")
        case .appNameOnly:
            String(localized: "App Name Only")
        }
    }
}

enum WindowTitleFontSize: Int, CaseIterable, Defaults.Serializable, Identifiable {
    case system = 0
    case caption2 = 1
    case caption = 2
    case footnote = 3
    case subheadline = 4
    case body = 5
    case headline = 6
    case title3 = 7
    case title2 = 8
    case title = 9

    var id: Int { rawValue }

    var localizedName: String {
        switch self {
        case .system:
            String(localized: "System Default", comment: "Window title font size option")
        case .caption2:
            String(localized: "Caption 2", comment: "Window title font size option")
        case .caption:
            String(localized: "Caption", comment: "Window title font size option")
        case .footnote:
            String(localized: "Footnote", comment: "Window title font size option")
        case .subheadline:
            String(localized: "Subheadline", comment: "Window title font size option")
        case .body:
            String(localized: "Body", comment: "Window title font size option")
        case .headline:
            String(localized: "Headline", comment: "Window title font size option")
        case .title3:
            String(localized: "Title 3", comment: "Window title font size option")
        case .title2:
            String(localized: "Title 2", comment: "Window title font size option")
        case .title:
            String(localized: "Title", comment: "Window title font size option")
        }
    }

    var font: Font {
        switch self {
        case .system: .subheadline
        case .caption2: .caption2
        case .caption: .caption
        case .footnote: .footnote
        case .subheadline: .subheadline
        case .body: .body
        case .headline: .headline
        case .title3: .title3
        case .title2: .title2
        case .title: .title
        }
    }
}

enum CompactModeItemSize: Int, CaseIterable, Defaults.Serializable, Identifiable {
    case xSmall = 0
    case small = 1
    case medium = 2
    case large = 3
    case xLarge = 4
    case xxLarge = 5
    case xxxLarge = 6

    var id: Int { rawValue }

    var localizedName: String {
        switch self {
        case .xSmall:
            String(localized: "X-Small", comment: "Compact mode item size option")
        case .small:
            String(localized: "Small", comment: "Compact mode item size option")
        case .medium:
            String(localized: "Medium", comment: "Compact mode item size option")
        case .large:
            String(localized: "Large", comment: "Compact mode item size option")
        case .xLarge:
            String(localized: "X-Large", comment: "Compact mode item size option")
        case .xxLarge:
            String(localized: "2X-Large", comment: "Compact mode item size option")
        case .xxxLarge:
            String(localized: "3X-Large", comment: "Compact mode item size option")
        }
    }

    var primaryFont: Font {
        switch self {
        case .xSmall: .caption
        case .small: .callout
        case .medium: .system(size: 13, weight: .medium)
        case .large: .headline
        case .xLarge: .title3
        case .xxLarge: .title2
        case .xxxLarge: .title
        }
    }

    var secondaryFont: Font {
        switch self {
        case .xSmall: .caption2
        case .small: .caption
        case .medium: .system(size: 11)
        case .large: .callout
        case .xLarge: .body
        case .xxLarge: .headline
        case .xxxLarge: .title3
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .xSmall: 24
        case .small: 28
        case .medium: 32
        case .large: 36
        case .xLarge: 40
        case .xxLarge: 48
        case .xxxLarge: 56
        }
    }

    var rowHeight: CGFloat {
        switch self {
        case .xSmall: 36
        case .small: 40
        case .medium: 48
        case .large: 52
        case .xLarge: 56
        case .xxLarge: 64
        case .xxxLarge: 72
        }
    }
}

enum AppAppearanceMode: String, CaseIterable, Defaults.Serializable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .system:
            String(localized: "System", comment: "App appearance mode option")
        case .light:
            String(localized: "Light", comment: "App appearance mode option")
        case .dark:
            String(localized: "Dark", comment: "App appearance mode option")
        }
    }
}

/// Window Switcher live preview scope - determines which windows get live preview
enum WindowSwitcherLivePreviewScope: String, CaseIterable, Defaults.Serializable, Identifiable {
    case selectedWindowOnly
    case selectedAppWindows
    case allWindows

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .selectedWindowOnly:
            String(localized: "Selected Window Only")
        case .selectedAppWindows:
            String(localized: "Selected App's Windows")
        case .allWindows:
            String(localized: "All Windows")
        }
    }

    var localizedDescription: String {
        switch self {
        case .selectedWindowOnly:
            String(localized: "Only the currently selected window gets live preview")
        case .selectedAppWindows:
            String(localized: "All windows from the selected app get live preview")
        case .allWindows:
            String(localized: "All windows get live preview (may cause lag with many windows)")
        }
    }
}

// MARK: - Dock Background

enum DockBackgroundMaterial: String, CaseIterable, Defaults.Serializable {
    case ultraThin, thin, regular, thick, ultraThick

    var displayName: String {
        switch self {
        case .ultraThin:
            String(localized: "Ultra Thin", comment: "Dock background material thickness option")
        case .thin:
            String(localized: "Thin", comment: "Dock background material thickness option")
        case .regular:
            String(localized: "Regular", comment: "Dock background material thickness option")
        case .thick:
            String(localized: "Thick", comment: "Dock background material thickness option")
        case .ultraThick:
            String(localized: "Ultra Thick", comment: "Dock background material thickness option")
        }
    }

    var swiftUIMaterial: Material {
        switch self {
        case .ultraThin: .ultraThinMaterial
        case .thin: .thinMaterial
        case .regular: .regularMaterial
        case .thick: .thickMaterial
        case .ultraThick: .ultraThickMaterial
        }
    }
}

enum DockBackgroundStyle: String, CaseIterable, Defaults.Serializable {
    case liquidGlass
    case frostedMaterial
    case clear

    var displayName: String {
        switch self {
        case .liquidGlass:
            String(localized: "Liquid Glass", comment: "Dock background style option")
        case .frostedMaterial:
            String(localized: "Frosted", comment: "Dock background style option")
        case .clear:
            String(localized: "Clear", comment: "Dock background style option")
        }
    }

    @available(macOS 26.0, *)
    static var allAvailable: [DockBackgroundStyle] { allCases }

    static var preTahoe: [DockBackgroundStyle] { [.frostedMaterial, .clear] }
}
