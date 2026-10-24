import Carbon.HIToolbox
import Defaults
import SwiftUI

struct WindowSwitcherKeybindSection: View {
    @Default(.enableWindowSwitcher) var enableWindowSwitcher
    @Default(.enableWindowSwitcherSearch) var enableWindowSwitcherSearch
    @Default(.searchTriggerKey) var searchTriggerKey
    @Default(.fullscreenAppBlacklist) var fullscreenAppBlacklist
    @Default(.alternateSwitcherShortcuts) var alternateSwitcherShortcuts
    @Default(.persistentSwitcherShortcuts) var persistentSwitcherShortcuts
    @Default(.persistentSwitcherStartsUnfocused) private var persistentSwitcherStartsUnfocused
    @Default(.lastFocusedWindowShortcuts) var lastFocusedWindowShortcuts
    @Default(.cmdShortcuts) private var cmdShortcuts
    @Default(.UserKeybind) private var mainKeybind
    @Default(.enableSpacesShortcuts) private var enableSpacesShortcuts
    @Default(.enableSpacesBar) private var enableSpacesBar
    @Default(.spacesBarCycleKey) private var spacesBarCycleKey
    @Default(.spacesBarBackwardCycleKey) private var spacesBarBackwardCycleKey
    @Default(.requireShiftTabToGoBack) var requireShiftTabToGoBack
    @Default(.ignoreMainModifierSideForDependentShortcuts) private var ignoreMainModifierSideForDependentShortcuts
    @Default(.switcherBackwardKeyCode) var switcherBackwardKeyCode
    @Default(.windowSwitcherSelectionKeyCode) var selectionKeyCode
    @Default(.enableVimMotions) var enableVimMotions
    @Default(.passArrowsThroughToSystem) var passArrowsThroughToSystem
    @Default(.openWindowSwitcherFromMenuBarIcon) var openWindowSwitcherFromMenuBarIcon
    @Default(.menuBarIconWindowSwitcherClick) var menuBarIconWindowSwitcherClick

    @StateObject private var keybindModel = KeybindModel()
    @State private var showingAddBlacklistAppSheet = false
    @State private var newBlacklistApp = ""

    private var searchShortcutKeybind: UserKeyBind {
        WindowSwitcherShortcutResolver.dependentShortcutKeybind(mainKeybind, ignoreModifierSide: ignoreMainModifierSideForDependentShortcuts)
    }

    private var searchShortcutConflict: AlternateSwitcherShortcutConflict? {
        let _ = (cmdShortcuts, alternateSwitcherShortcuts, persistentSwitcherShortcuts, lastFocusedWindowShortcuts,
                 enableSpacesShortcuts, enableSpacesBar, spacesBarCycleKey, spacesBarBackwardCycleKey,
                 switcherBackwardKeyCode, selectionKeyCode, enableVimMotions, searchTriggerKey)
        return WindowSwitcherShortcutResolver.searchTriggerConflict(previewKeybind: searchShortcutKeybind, mainKeybind: mainKeybind)
    }

    var body: some View {
        SettingsGroup(header: "Window Switcher Shortcuts") {
            VStack(alignment: .leading, spacing: 12) {
                if !enableWindowSwitcher {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.yellow)
                        Text("Window Switcher is disabled. Enable it in General settings to use keyboard shortcuts.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(8)
                }

                keyboardShortcutSection
                    .disabled(!enableWindowSwitcher)
                    .opacity(enableWindowSwitcher ? 1.0 : 0.5)

                Divider()

                menuBarIconSection
                    .disabled(!enableWindowSwitcher)
                    .opacity(enableWindowSwitcher ? 1.0 : 0.5)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Backward Key")
                        Spacer()
                        KeyCaptureButton(keyCode: $switcherBackwardKeyCode, captureModifiers: true)
                        Button("Reset") { switcherBackwardKeyCode = 56 }
                            .buttonStyle(.bordered)
                    }
                    .settingsSearchTarget("gestures.backwardKey")
                    Text("The key used to navigate backward in the window switcher.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle(isOn: $requireShiftTabToGoBack) {
                        Text("Require \(KeyboardLabel.localizedKey(for: switcherBackwardKeyCode))+Tab to go back in Switcher")
                    }
                    .settingsSearchTarget("gestures.requireShiftTab")
                    Text("When enabled, pressing the backward key alone won't go back. Use it with Tab to navigate backward.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
                .disabled(!enableWindowSwitcher)
                .opacity(enableWindowSwitcher ? 1.0 : 0.5)

                Divider()

                selectionKeySection
                    .disabled(!enableWindowSwitcher)
                    .opacity(enableWindowSwitcher ? 1.0 : 0.5)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $enableVimMotions) {
                        Text("Enable Vim Motions")
                    }
                    .settingsSearchTarget("gestures.vimMotions")
                    Text("Use H/J/K/L keys to navigate left/down/up/right in the window switcher. Disabled while search is focused.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)

                    Toggle(isOn: $passArrowsThroughToSystem) {
                        Text("Pass Arrow Keys Through to System")
                    }
                    .settingsSearchTarget("gestures.arrowPassthrough")
                    Text("When enabled, Ctrl+Arrow keys will be passed through to the system instead of navigating the switcher. Useful for Spaces switching.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
                .disabled(!enableWindowSwitcher)
                .opacity(enableWindowSwitcher ? 1.0 : 0.5)

                Divider()

                alternateShortcutsSection
                    .disabled(!enableWindowSwitcher)
                    .opacity(enableWindowSwitcher ? 1.0 : 0.5)

                Divider()

                persistentShortcutsSection
                    .disabled(!enableWindowSwitcher)
                    .opacity(enableWindowSwitcher ? 1.0 : 0.5)

                Divider()

                lastFocusedShortcutsSection
                    .disabled(!enableWindowSwitcher)
                    .opacity(enableWindowSwitcher ? 1.0 : 0.5)

                if enableWindowSwitcherSearch {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Search Trigger Key").font(.headline)
                        Text("The key that activates search while the window switcher is open.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 4) {
                            Text(modifierConverter.toSymbol(searchShortcutKeybind))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.secondary)
                            KeyCaptureButton(keyCode: $searchTriggerKey)
                        }
                        if let conflict = searchShortcutConflict {
                            Text(conflict.localizedMessage).font(.caption2).foregroundStyle(.red)
                        }
                    }
                    .settingsSearchTarget("gestures.searchTriggerKey")
                    .disabled(!enableWindowSwitcher)
                    .opacity(enableWindowSwitcher ? 1.0 : 0.5)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Fullscreen App Blacklist").font(.headline)
                    Text("Apps in this list will not respond to window switcher shortcuts when in fullscreen mode.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    fullscreenAppBlacklistView
                }
                .settingsSearchTarget("gestures.fullscreenBlacklist")
            }
            .settingsSearchTarget("gestures.switcherKeybind")
        }
        .onAppear {
            materializeInheritedAlternateModifiers()
            keybindModel.modifierKey = Defaults[.UserKeybind].modifierFlags
            keybindModel.modifierSide = Defaults[.UserKeybind].modifierSide
            keybindModel.currentKeybind = Defaults[.UserKeybind]
        }
    }

    // MARK: - Keyboard Shortcut Section

    private var keyboardShortcutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Main Window Switcher Shortcut")
                .font(.headline)

            HStack(spacing: 8) {
                if let keybind = keybindModel.currentKeybind {
                    KeyCapView(
                        text: modifierConverter.toString(keybind),
                        symbol: nil
                    )
                    Text("+").foregroundColor(.secondary)
                    KeyCapView(text: KeyboardLabel.localizedKey(for: keybind.keyCode), symbol: nil)
                } else {
                    Text("No shortcut set").foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                Button(action: { keybindModel.isRecording.toggle() }) {
                    HStack {
                        Image(systemName: keybindModel.isRecording ? "keyboard.fill" : "record.circle")
                        Text(keybindModel.isRecording ? "Press shortcut…" : "Change…")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(keybindModel.isRecording)

                Button("Reset") {
                    let defaultKeybind = UserKeyBind(
                        keyCode: 48,
                        modifierFlags: Defaults[.Int64maskAlternate],
                        modifierSide: .left
                    )
                    Defaults[.UserKeybind] = defaultKeybind
                    keybindModel.currentKeybind = defaultKeybind
                    keybindModel.modifierKey = defaultKeybind.modifierFlags
                    keybindModel.modifierSide = defaultKeybind.modifierSide
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Picker("Initializer", selection: $keybindModel.modifierKey) {
                    Text("Control ⌃").tag(Defaults[.Int64maskControl])
                    Text("Option ⌥").tag(Defaults[.Int64maskAlternate])
                    Text("Command ⌘").tag(Defaults[.Int64maskCommand])
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: keybindModel.modifierKey) { newValue in
                    if let currentKeybind = keybindModel.currentKeybind {
                        let updatedKeybind = UserKeyBind(
                            keyCode: currentKeybind.keyCode,
                            modifierFlags: newValue,
                            modifierSide: keybindModel.modifierSide
                        )
                        Defaults[.UserKeybind] = updatedKeybind
                        keybindModel.currentKeybind = updatedKeybind
                    }
                }

                Picker("Side", selection: $keybindModel.modifierSide) {
                    ForEach(ModifierKeySide.allCases) { side in
                        Text(side.localizedName).tag(side)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: keybindModel.modifierSide) { newValue in
                    if let currentKeybind = keybindModel.currentKeybind {
                        let updatedKeybind = UserKeyBind(
                            keyCode: currentKeybind.keyCode,
                            modifierFlags: currentKeybind.modifierFlags,
                            modifierSide: newValue
                        )
                        Defaults[.UserKeybind] = updatedKeybind
                        keybindModel.currentKeybind = updatedKeybind
                    }
                }
            }

            Text("Choose whether the left, right, or either modifier key activates the Window Switcher.")
                .font(.caption)
                .foregroundColor(.secondary)

            if keybindModel.modifierSide != .either {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Ignore modifier key side for Window Preview Keyboard Shortcuts", isOn: $ignoreMainModifierSideForDependentShortcuts)
                        .settingsSearchTarget("gestures.ignoreMainModifierSideForDependentShortcuts")

                    Text("Allows either side of the selected modifier to trigger shortcuts that inherit the main Window Switcher modifier. The main Window Switcher shortcut still uses the selected side.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 20)
                }
            }
        }
        .background(
            ShortcutCaptureView(
                currentKeybind: $keybindModel.currentKeybind,
                isRecording: $keybindModel.isRecording,
                modifierKey: $keybindModel.modifierKey
            )
            .allowsHitTesting(false)
            .frame(width: 0, height: 0)
        )
    }

    // MARK: - Menu Bar Icon

    private var menuBarIconSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Menu bar icon", isOn: $openWindowSwitcherFromMenuBarIcon)
                .settingsSearchTarget("gestures.menuBarIconWindowSwitcher")
            Text("Open Window Switcher when clicking on menu bar icon")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            if openWindowSwitcherFromMenuBarIcon {
                Picker("Left/right clicks trigger:", selection: $menuBarIconWindowSwitcherClick) {
                    ForEach(MenuBarIconWindowSwitcherClick.allCases, id: \.self) { click in
                        Text(click.localizedName).tag(click)
                    }
                }
                .pickerStyle(.menu)
                .settingsSearchTarget("gestures.menuBarIconClickBehavior")
            }
        }
    }

    // MARK: - Selection Key Section

    private var selectionKeySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Selection Key")
                Spacer()
                KeyCaptureButton(keyCode: $selectionKeyCode)
                Button("Reset") { selectionKeyCode = UInt16(kVK_Return) }
                    .buttonStyle(.bordered)
            }
            .settingsSearchTarget("gestures.selectionKey")
            Text("The key used to select and bring to front the highlighted window in the switcher.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Alternate Shortcuts Section

    private var alternateShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Alternate Shortcuts (Inherit Default Window Switcher)")).font(.headline)
            Text("Additional trigger keys, each with its own modifier and window filter.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(indexedAlternateShortcuts, id: \.shortcut.id) { item in
                alternateShortcutRow(index: item.index, shortcut: item.shortcut)
            }
        }
        .settingsSearchTarget("gestures.alternateShortcuts")
    }

    private var indexedAlternateShortcuts: [(index: Int, shortcut: AlternateSwitcherShortcut)] {
        Array(alternateSwitcherShortcuts.enumerated()).map { (index: $0.offset, shortcut: $0.element) }
    }

    private var hasIncompleteAlternateShortcut: Bool {
        alternateSwitcherShortcuts.contains { $0.isPending || !$0.isConfigured }
    }

    private var canAddAlternateShortcut: Bool {
        alternateSwitcherShortcuts.count < SwitcherInvocationMode.allCases.count && !hasIncompleteAlternateShortcut
    }

    private func alternateShortcutRow(index: Int, shortcut: AlternateSwitcherShortcut) -> some View {
        let conflict = WindowSwitcherShortcutResolver.alternateConflict(
            at: index,
            shortcuts: alternateSwitcherShortcuts,
            mainKeybind: mainKeybind,
            previewShortcuts: cmdShortcuts
        )

        return HStack(spacing: 12) {
            Picker("Modifier", selection: alternateModifierBinding(for: shortcut.id)) {
                ForEach(ShortcutModifierKey.allCases) { modifier in
                    Text(modifier.localizedName).tag(modifier.modifierFlags)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()

            ModifierSidePicker(selection: alternateSideBinding(for: shortcut.id))

            Text("+")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            KeyCaptureButton(
                keyCode: alternateKeyBinding(for: shortcut.id),
                emptyLabel: "Not set",
                forceEmptyLabel: !shortcut.isConfigured,
                treatKeyCodeZeroAsEmpty: false,
                allowsEscape: true,
                cancelOnOutsideClick: true
            )

            Picker("Mode", selection: alternateModeBinding(for: shortcut.id)) {
                ForEach(SwitcherInvocationMode.sortedCases) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 220)

            if let conflict {
                Text(conflict.localizedMessage)
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            Spacer(minLength: 0)

            ControlGroup {
                Button("-") {
                    removeAlternateShortcut(shortcut.id)
                }
                Button("+") {
                    addAlternateShortcut(after: shortcut.id)
                }
                .disabled(!canAddAlternateShortcut)
            }
            .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if conflict != nil {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if conflict != nil {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.28), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func alternateKeyBinding(for id: UUID) -> Binding<UInt16> {
        Binding(
            get: { alternateSwitcherShortcuts.first(where: { $0.id == id })?.keyCode ?? 0 },
            set: { newValue in
                guard let index = alternateSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
                alternateSwitcherShortcuts[index].keyCode = newValue
                alternateSwitcherShortcuts[index].isConfigured = true
                alternateSwitcherShortcuts[index].isPending = false
            }
        )
    }

    private func alternateModifierBinding(for id: UUID) -> Binding<Int> {
        Binding(
            get: {
                guard let shortcut = alternateSwitcherShortcuts.first(where: { $0.id == id }) else {
                    return Defaults[.Int64maskAlternate]
                }
                let flags = shortcut.modifierFlags == 0 ? mainKeybind.modifierFlags : shortcut.modifierFlags
                return WindowSwitcherShortcutResolver.normalizedModifiers(flags)
            },
            set: { newValue in
                guard let index = alternateSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
                alternateSwitcherShortcuts[index].modifierFlags = newValue
            }
        )
    }

    private func alternateSideBinding(for id: UUID) -> Binding<ModifierKeySide> {
        Binding(
            get: { alternateSwitcherShortcuts.first(where: { $0.id == id })?.modifierSide ?? .either },
            set: { newValue in
                guard let index = alternateSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
                alternateSwitcherShortcuts[index].modifierSide = newValue
            }
        )
    }

    private func alternateModeBinding(for id: UUID) -> Binding<SwitcherInvocationMode> {
        Binding(
            get: { alternateSwitcherShortcuts.first(where: { $0.id == id })?.mode ?? .activeAppOnly },
            set: { newValue in
                guard let index = alternateSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
                alternateSwitcherShortcuts[index].mode = newValue
            }
        )
    }

    private func addAlternateShortcut(after id: UUID) {
        guard canAddAlternateShortcut else { return }
        let insertionIndex = min(
            (alternateSwitcherShortcuts.firstIndex(where: { $0.id == id }) ?? (alternateSwitcherShortcuts.count - 1)) + 1,
            alternateSwitcherShortcuts.count
        )
        let usedModes = Set(alternateSwitcherShortcuts.map(\.mode))
        let nextMode = SwitcherInvocationMode.sortedCases.first { !usedModes.contains($0) } ?? .activeAppOnly
        let pending = AlternateSwitcherShortcut(
            modifierFlags: WindowSwitcherShortcutResolver.normalizedModifiers(mainKeybind.modifierFlags),
            modifierSide: mainKeybind.modifierSide,
            mode: nextMode,
            isPending: true
        )
        alternateSwitcherShortcuts.insert(pending, at: insertionIndex)
    }

    private func materializeInheritedAlternateModifiers() {
        for index in alternateSwitcherShortcuts.indices where alternateSwitcherShortcuts[index].modifierFlags == 0 {
            alternateSwitcherShortcuts[index].modifierFlags = WindowSwitcherShortcutResolver.normalizedModifiers(mainKeybind.modifierFlags)
            alternateSwitcherShortcuts[index].modifierSide = mainKeybind.modifierSide
        }
    }

    private func removeAlternateShortcut(_ id: UUID) {
        guard let index = alternateSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
        if alternateSwitcherShortcuts.count == 1 {
            alternateSwitcherShortcuts[index].keyCode = 0
            alternateSwitcherShortcuts[index].isConfigured = false
            alternateSwitcherShortcuts[index].isPending = false
        } else {
            alternateSwitcherShortcuts.remove(at: index)
        }
    }

    // MARK: - Persistent Alternate Shortcuts Section

    private var persistentShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Alternate Shortcuts (Persistent Window Switcher)")).font(.headline)
            (Text("Releasing initializer keys will always keep the Window Switcher open. Window preview keyboard shortcuts use the default modifier key.")
                + Text(" (currently \(modifierConverter.toSymbol(WindowSwitcherShortcutResolver.dependentShortcutKeybind(mainKeybind))))."))
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Each shortcut can use either a standard key combination pressed once or a single modifier key pressed twice.")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle(String(localized: "Start Persistent Window Switcher with no window highlighted"), isOn: $persistentSwitcherStartsUnfocused)
                .settingsSearchTarget("gestures.persistentSwitcherStartsUnfocused")
            Text("Also applies when opening the Window Switcher from the menu bar icon.")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 20)

            ScopedShortcutRows(
                shortcuts: $persistentSwitcherShortcuts,
                defaultMode: .allWindows,
                conflictAtIndex: { index, shortcuts in
                    WindowSwitcherShortcutResolver.persistentConflict(
                        at: index,
                        shortcuts: shortcuts,
                        mainKeybind: mainKeybind,
                        alternateShortcuts: alternateSwitcherShortcuts,
                        previewShortcuts: cmdShortcuts
                    )
                }
            )
        }
        .settingsSearchTarget("gestures.persistentSwitcherShortcuts")
    }

    private var lastFocusedShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Switch to Last Focused Window").font(.headline)
            Text("Instantly switch to the last focused window.")
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Each shortcut can use either a standard key combination pressed once or a single modifier key pressed twice.")
                .font(.caption)
                .foregroundColor(.secondary)

            ScopedShortcutRows(
                shortcuts: $lastFocusedWindowShortcuts,
                defaultMode: .globalAllWindows,
                conflictAtIndex: { index, shortcuts in
                    WindowSwitcherShortcutResolver.lastFocusedConflict(
                        at: index,
                        shortcuts: shortcuts,
                        mainKeybind: mainKeybind,
                        alternateShortcuts: alternateSwitcherShortcuts,
                        persistentShortcuts: persistentSwitcherShortcuts,
                        previewShortcuts: cmdShortcuts
                    )
                }
            )
        }
        .settingsSearchTarget("gestures.lastFocusedWindowShortcuts")
    }

    // MARK: - Fullscreen App Blacklist

    private var fullscreenAppBlacklistView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !fullscreenAppBlacklist.isEmpty {
                        ForEach(fullscreenAppBlacklist, id: \.self) { appName in
                            HStack {
                                Text(appName)
                                    .foregroundColor(.primary)

                                Spacer()

                                Button(action: {
                                    fullscreenAppBlacklist.removeAll { $0 == appName }
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)

                            if appName != fullscreenAppBlacklist.last {
                                Divider()
                            }
                        }
                    } else {
                        Text("No apps in blacklist")
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(8)
            }
            .frame(maxHeight: 120)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.25), lineWidth: 1)
            )

            HStack {
                Button(action: { showingAddBlacklistAppSheet.toggle() }) {
                    Text("Add App")
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(!enableWindowSwitcher)

                Spacer()

                if !fullscreenAppBlacklist.isEmpty {
                    DangerButton(action: {
                        fullscreenAppBlacklist.removeAll()
                    }) {
                        Text("Remove All")
                    }
                    .disabled(!enableWindowSwitcher)
                }
            }
        }
        .sheet(isPresented: $showingAddBlacklistAppSheet) {
            AddBlacklistAppSheet(
                isPresented: $showingAddBlacklistAppSheet,
                appNameToAdd: $newBlacklistApp,
                onAdd: { appName in
                    if !appName.isEmpty, !fullscreenAppBlacklist.contains(where: { $0.caseInsensitiveCompare(appName) == .orderedSame }) {
                        fullscreenAppBlacklist.append(appName)
                    }
                }
            )
        }
    }
}

private struct ModifierSidePicker: View {
    @Binding var selection: ModifierKeySide

    var body: some View {
        Picker("Side", selection: $selection) {
            ForEach(ModifierKeySide.allCases) { side in
                Text(side.localizedName).tag(side)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
    }
}

private struct ScopedShortcutRows: View {
    @Binding var shortcuts: [PersistentSwitcherShortcut]
    let defaultMode: SwitcherInvocationMode
    let conflictAtIndex: (Int, [PersistentSwitcherShortcut]) -> AlternateSwitcherShortcutConflict?

    private var indexedShortcuts: [(index: Int, shortcut: PersistentSwitcherShortcut)] {
        Array(shortcuts.enumerated()).map { (index: $0.offset, shortcut: $0.element) }
    }

    private var canAddShortcut: Bool {
        shortcuts.count < SwitcherInvocationMode.allCases.count &&
            !shortcuts.contains { $0.isPending || !$0.isConfigured }
    }

    var body: some View {
        ForEach(indexedShortcuts, id: \.shortcut.id) { item in
            shortcutRow(index: item.index, shortcut: item.shortcut)
        }
        .onAppear {
            if shortcuts.isEmpty {
                shortcuts = [PersistentSwitcherShortcut(mode: defaultMode)]
            }
        }
    }

    private func shortcutRow(index: Int, shortcut: PersistentSwitcherShortcut) -> some View {
        let conflict = conflictAtIndex(index, shortcuts)

        return HStack(spacing: 12) {
            Toggle("Double-tap key", isOn: doubleTapBinding(for: shortcut.id))
                .toggleStyle(.checkbox)
                .fixedSize()

            if shortcut.usesDoubleTap {
                Picker("Modifier", selection: doubleTapKeyBinding(for: shortcut.id)) {
                    ForEach(ShortcutModifierKey.allCases) { key in
                        Text(key.localizedName).tag(key)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()

                ModifierSidePicker(selection: doubleTapSideBinding(for: shortcut.id))
            } else {
                KeyCombinationCaptureButton(
                    keyCode: keyBinding(for: shortcut.id),
                    modifierFlags: modifierBinding(for: shortcut.id),
                    isConfigured: shortcut.isConfigured,
                    onCaptureFinished: { assigned in
                        guard assigned,
                              let rowIndex = shortcuts.firstIndex(where: { $0.id == shortcut.id })
                        else { return }
                        shortcuts[rowIndex].isConfigured = true
                        shortcuts[rowIndex].isPending = false
                    }
                )
            }

            Picker("Mode", selection: modeBinding(for: shortcut.id)) {
                ForEach(SwitcherInvocationMode.sortedCases) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 220)

            if let conflict {
                Text(conflict.localizedMessage)
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            Spacer(minLength: 0)

            ControlGroup {
                Button("-") { removeShortcut(shortcut.id) }
                Button("+") { addShortcut(after: shortcut.id) }
                    .disabled(!canAddShortcut)
            }
            .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if conflict != nil {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if conflict != nil {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.28), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func rowIndex(for id: UUID) -> Int? {
        shortcuts.firstIndex { $0.id == id }
    }

    private func keyBinding(for id: UUID) -> Binding<UInt16> {
        Binding(
            get: { rowIndex(for: id).map { shortcuts[$0].keyCode } ?? 0 },
            set: { if let index = rowIndex(for: id) { shortcuts[index].keyCode = $0 } }
        )
    }

    private func modifierBinding(for id: UUID) -> Binding<Int> {
        Binding(
            get: { rowIndex(for: id).map { shortcuts[$0].modifierFlags } ?? 0 },
            set: { newValue in
                guard let index = rowIndex(for: id) else { return }
                shortcuts[index].modifierFlags = newValue
                shortcuts[index].isConfigured = newValue != 0
                shortcuts[index].isPending = false
            }
        )
    }

    private func modeBinding(for id: UUID) -> Binding<SwitcherInvocationMode> {
        Binding(
            get: { rowIndex(for: id).map { shortcuts[$0].mode } ?? defaultMode },
            set: { if let index = rowIndex(for: id) { shortcuts[index].mode = $0 } }
        )
    }

    private func doubleTapBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { rowIndex(for: id).map { shortcuts[$0].usesDoubleTap } ?? false },
            set: { newValue in
                guard let index = rowIndex(for: id) else { return }
                shortcuts[index].usesDoubleTap = newValue
                shortcuts[index].isConfigured = newValue || shortcuts[index].modifierFlags != 0
                shortcuts[index].isPending = false
            }
        )
    }

    private func doubleTapKeyBinding(for id: UUID) -> Binding<ShortcutModifierKey> {
        Binding(
            get: { rowIndex(for: id).map { shortcuts[$0].doubleTapKey } ?? .option },
            set: { if let index = rowIndex(for: id) { shortcuts[index].doubleTapKey = $0 } }
        )
    }

    private func doubleTapSideBinding(for id: UUID) -> Binding<ModifierKeySide> {
        Binding(
            get: { rowIndex(for: id).map { shortcuts[$0].doubleTapSide } ?? .either },
            set: { if let index = rowIndex(for: id) { shortcuts[index].doubleTapSide = $0 } }
        )
    }

    private func addShortcut(after id: UUID) {
        guard canAddShortcut else { return }
        let insertionIndex = min((rowIndex(for: id) ?? (shortcuts.count - 1)) + 1, shortcuts.count)
        let usedModes = Set(shortcuts.map(\.mode))
        let nextMode = SwitcherInvocationMode.sortedCases.first { !usedModes.contains($0) } ?? defaultMode
        shortcuts.insert(PersistentSwitcherShortcut(mode: nextMode, isPending: true), at: insertionIndex)
    }

    private func removeShortcut(_ id: UUID) {
        guard let index = rowIndex(for: id) else { return }
        if shortcuts.count == 1 {
            shortcuts[index] = PersistentSwitcherShortcut(mode: shortcuts[index].mode)
        } else {
            shortcuts.remove(at: index)
        }
    }
}

private struct KeyCombinationCaptureButton: View {
    @Binding var keyCode: UInt16
    @Binding var modifierFlags: Int
    let isConfigured: Bool
    let onCaptureFinished: (Bool) -> Void

    @State private var isCapturing = false
    @State private var monitors: [Any] = []

    var body: some View {
        Group {
            if isCapturing {
                Text("Press shortcut…")
                    .font(.system(size: 12))
                    .foregroundColor(.accentColor)
                    .frame(minWidth: 120)
            } else {
                Button(action: startCapture) {
                    Text(isConfigured ? shortcutLabel : String(localized: "Not set"))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(minWidth: 120)
                        .background(Color.secondary.opacity(isConfigured ? 0.2 : 0.1))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .onDisappear {
            stopCapture()
        }
    }

    private var shortcutLabel: String {
        let flags = CGEventFlags(rawValue: UInt64(WindowSwitcherShortcutResolver.normalizedModifiers(modifierFlags)))
        var label = ""
        if flags.contains(.maskControl) { label += "⌃" }
        if flags.contains(.maskAlternate) { label += "⌥" }
        if flags.contains(.maskShift) { label += "⇧" }
        if flags.contains(.maskCommand) { label += "⌘" }
        return label + KeyboardLabel.localizedKey(for: keyCode)
    }

    private func startCapture() {
        stopCapture()
        isCapturing = true

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            let capturedModifiers = Self.modifierFlags(from: event.modifierFlags)
            if event.keyCode == UInt16(kVK_Escape), capturedModifiers == 0 {
                stopCapture(reportAssigned: false)
                return nil
            }
            guard !Self.modifierKeyCodes.contains(event.keyCode) else { return nil }
            guard capturedModifiers != 0 else {
                NSSound.beep()
                return nil
            }

            keyCode = event.keyCode
            modifierFlags = capturedModifiers
            stopCapture(reportAssigned: true)
            return nil
        }) {
            monitors.append(monitor)
        }

        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { event in
            stopCapture(reportAssigned: false)
            return event
        }) {
            monitors.append(monitor)
        }
    }

    private func stopCapture(reportAssigned assigned: Bool? = nil) {
        isCapturing = false
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let assigned { onCaptureFinished(assigned) }
    }

    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Shift), UInt16(kVK_RightShift),
        UInt16(kVK_Control), UInt16(kVK_RightControl),
        UInt16(kVK_Option), UInt16(kVK_RightOption),
        UInt16(kVK_Command), UInt16(kVK_RightCommand),
    ]

    private static func modifierFlags(from flags: NSEvent.ModifierFlags) -> Int {
        var result: UInt64 = 0
        if flags.contains(.shift) { result |= CGEventFlags.maskShift.rawValue }
        if flags.contains(.control) { result |= CGEventFlags.maskControl.rawValue }
        if flags.contains(.option) { result |= CGEventFlags.maskAlternate.rawValue }
        if flags.contains(.command) { result |= CGEventFlags.maskCommand.rawValue }
        return Int(result)
    }
}
