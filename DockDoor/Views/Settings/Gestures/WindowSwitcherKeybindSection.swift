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
    @Default(.cmdShortcuts) private var cmdShortcuts
    @Default(.UserKeybind) private var mainKeybind
    @Default(.requireShiftTabToGoBack) var requireShiftTabToGoBack
    @Default(.switcherBackwardKeyCode) var switcherBackwardKeyCode
    @Default(.windowSwitcherSelectionKeyCode) var selectionKeyCode
    @Default(.enableVimMotions) var enableVimMotions
    @Default(.passArrowsThroughToSystem) var passArrowsThroughToSystem
    @Default(.openWindowSwitcherFromMenuBarIcon) var openWindowSwitcherFromMenuBarIcon
    @Default(.menuBarIconWindowSwitcherClick) var menuBarIconWindowSwitcherClick

    @StateObject private var keybindModel = KeybindModel()
    @State private var showingAddBlacklistAppSheet = false
    @State private var newBlacklistApp = ""
    @State private var autoCaptureAlternateShortcutID: UUID?

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

                if enableWindowSwitcherSearch {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Search Trigger Key").font(.headline)
                        Text("The key that activates search while the window switcher is open.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Text(modifierConverter.toString(keybindModel.modifierKey))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text("+")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)

                            KeyCaptureButton(keyCode: $searchTriggerKey)
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
            keybindModel.modifierKey = Defaults[.UserKeybind].modifierFlags
            keybindModel.currentKeybind = Defaults[.UserKeybind]
        }
    }

    // MARK: - Keyboard Shortcut Section

    private var keyboardShortcutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Current shortcut summary
            if let keybind = keybindModel.currentKeybind {
                HStack(spacing: 8) {
                    KeyCapView(text: modifierConverter.toString(keybind.modifierFlags), symbol: nil)
                    Text("+").foregroundColor(.secondary)
                    KeyCapView(text: KeyboardLabel.localizedKey(for: keybind.keyCode), symbol: nil)
                }
            } else {
                Text("No shortcut set").foregroundColor(.secondary)
            }

            // Controls: initializer modifier + capture button
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
                        let updatedKeybind = UserKeyBind(keyCode: currentKeybind.keyCode, modifierFlags: newValue)
                        Defaults[.UserKeybind] = updatedKeybind
                        keybindModel.currentKeybind = updatedKeybind
                    }
                }

                Button(action: { keybindModel.isRecording.toggle() }) {
                    HStack {
                        Image(systemName: keybindModel.isRecording ? "keyboard.fill" : "record.circle")
                        Text(keybindModel.isRecording ? "Press shortcut…" : "Change…")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(keybindModel.isRecording)

                Button("Reset") {
                    let def = UserKeyBind(keyCode: 48, modifierFlags: Defaults[.Int64maskAlternate])
                    Defaults[.UserKeybind] = def
                    keybindModel.currentKeybind = def
                    keybindModel.modifierKey = def.modifierFlags
                }
                .buttonStyle(.bordered)
            }

            Text("Either left or right Command, Option, or Control keys work. You can also hold the modifier while pressing the trigger to capture both.")
                .font(.caption)
                .foregroundColor(.secondary)
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
            Text("Alternate Shortcuts").font(.headline)
            Text("Additional trigger keys, each with its own modifier and window filter.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(indexedAlternateShortcuts, id: \.shortcut.id) { item in
                alternateShortcutRow(index: item.index, shortcut: item.shortcut)
            }
        }
        .settingsSearchTarget("gestures.alternateShortcuts")
        .onAppear {
            removePendingAlternateShortcutsIfNeeded()
        }
    }

    private var indexedAlternateShortcuts: [(index: Int, shortcut: AlternateSwitcherShortcut)] {
        Array(alternateSwitcherShortcuts.enumerated()).map { (index: $0.offset, shortcut: $0.element) }
    }

    private var hasPendingAlternateShortcut: Bool {
        alternateSwitcherShortcuts.contains { $0.isPending }
    }

    private var canAddAlternateShortcut: Bool {
        alternateSwitcherShortcuts.count < SwitcherInvocationMode.allCases.count && !hasPendingAlternateShortcut
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
                Text("Same as main (\(modifierConverter.toString(mainKeybind.modifierFlags)))").tag(0)
                Text("Control ⌃").tag(Defaults[.Int64maskControl])
                Text("Option ⌥").tag(Defaults[.Int64maskAlternate])
                Text("Command ⌘").tag(Defaults[.Int64maskCommand])
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .disabled(shortcut.isPending)

            Text("+")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            KeyCaptureButton(
                keyCode: alternateKeyBinding(for: shortcut.id),
                emptyLabel: "Not set",
                forceEmptyLabel: !shortcut.isConfigured,
                treatKeyCodeZeroAsEmpty: false,
                allowsEscape: true,
                autoStartCapture: autoCaptureAlternateShortcutID == shortcut.id,
                onCaptureFinished: { assigned in
                    handleAlternateCaptureFinished(for: shortcut.id, assigned: assigned)
                }
            )

            Picker("Mode", selection: alternateModeBinding(for: shortcut.id)) {
                ForEach(SwitcherInvocationMode.allCases) { mode in
                    Text(mode.localizedName).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 220)
            .disabled(shortcut.isPending)

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
            get: { alternateSwitcherShortcuts.first(where: { $0.id == id })?.modifierFlags ?? 0 },
            set: { newValue in
                guard let index = alternateSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
                alternateSwitcherShortcuts[index].modifierFlags = newValue
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
        let nextMode = SwitcherInvocationMode.allCases.first { !usedModes.contains($0) } ?? .activeAppOnly
        let pending = AlternateSwitcherShortcut(mode: nextMode, isPending: true)
        alternateSwitcherShortcuts.insert(pending, at: insertionIndex)
        autoCaptureAlternateShortcutID = pending.id
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
        if autoCaptureAlternateShortcutID == id {
            autoCaptureAlternateShortcutID = nil
        }
    }

    private func handleAlternateCaptureFinished(for id: UUID, assigned: Bool) {
        defer {
            if autoCaptureAlternateShortcutID == id {
                autoCaptureAlternateShortcutID = nil
            }
        }

        guard !assigned,
              let index = alternateSwitcherShortcuts.firstIndex(where: { $0.id == id }),
              alternateSwitcherShortcuts[index].isPending
        else { return }

        if alternateSwitcherShortcuts.count == 1 {
            alternateSwitcherShortcuts[index].isPending = false
            alternateSwitcherShortcuts[index].isConfigured = false
        } else {
            alternateSwitcherShortcuts.remove(at: index)
        }
    }

    private func removePendingAlternateShortcutsIfNeeded() {
        let configuredRows = alternateSwitcherShortcuts.filter { !$0.isPending }
        alternateSwitcherShortcuts = configuredRows.isEmpty ? AlternateSwitcherShortcut.defaultShortcuts : configuredRows
        if let autoCaptureAlternateShortcutID,
           !alternateSwitcherShortcuts.contains(where: { $0.id == autoCaptureAlternateShortcutID })
        {
            self.autoCaptureAlternateShortcutID = nil
        }
    }

    // MARK: - Persistent Alternate Shortcuts Section

    private var persistentShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Alternate Shortcuts (Keep Open)").font(.headline)
            (Text("Releasing initializer keys will always keep the Window Switcher open. Window preview keyboard shortcuts use the default modifier key.")
                + Text(" (currently \(modifierConverter.toSymbol(mainKeybind.modifierFlags)))."))
                .font(.caption)
                .foregroundColor(.secondary)
            Text("Each shortcut can use either a standard key combination pressed once or a single modifier key pressed twice.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(indexedPersistentShortcuts, id: \.shortcut.id) { item in
                persistentShortcutRow(index: item.index, shortcut: item.shortcut)
            }
        }
        .settingsSearchTarget("gestures.persistentSwitcherShortcuts")
        .onAppear {
            ensurePersistentShortcutRow()
        }
    }

    private var indexedPersistentShortcuts: [(index: Int, shortcut: PersistentSwitcherShortcut)] {
        Array(persistentSwitcherShortcuts.enumerated()).map { (index: $0.offset, shortcut: $0.element) }
    }

    private var hasPendingPersistentShortcut: Bool {
        persistentSwitcherShortcuts.contains { $0.isPending || !$0.isConfigured }
    }

    private var canAddPersistentShortcut: Bool {
        persistentSwitcherShortcuts.count < SwitcherInvocationMode.allCases.count && !hasPendingPersistentShortcut
    }

    private func persistentShortcutRow(index: Int, shortcut: PersistentSwitcherShortcut) -> some View {
        let conflict = WindowSwitcherShortcutResolver.persistentConflict(
            at: index,
            shortcuts: persistentSwitcherShortcuts,
            mainKeybind: mainKeybind,
            alternateShortcuts: alternateSwitcherShortcuts,
            previewShortcuts: cmdShortcuts
        )

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Toggle("Double-tap key", isOn: persistentDoubleTapBinding(for: shortcut.id))
                    .toggleStyle(.checkbox)
                    .fixedSize()

                if shortcut.usesDoubleTap {
                    Picker("Modifier", selection: persistentDoubleTapKeyBinding(for: shortcut.id)) {
                        ForEach(ModifierDoubleTapKey.allCases) { key in
                            Text(key.localizedName).tag(key)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()

                    Picker("Side", selection: persistentDoubleTapSideBinding(for: shortcut.id)) {
                        ForEach(ModifierKeySide.allCases) { side in
                            Text(side.localizedName).tag(side)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                } else {
                    KeyCombinationCaptureButton(
                        keyCode: persistentKeyBinding(for: shortcut.id),
                        modifierFlags: persistentModifierBinding(for: shortcut.id),
                        isConfigured: shortcut.isConfigured,
                        onCaptureFinished: { assigned in
                            handlePersistentCaptureFinished(for: shortcut.id, assigned: assigned)
                        }
                    )
                }

                Picker("Mode", selection: persistentModeBinding(for: shortcut.id)) {
                    ForEach(SwitcherInvocationMode.allCases) { mode in
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
                    Button("-") {
                        removePersistentShortcut(shortcut.id)
                    }
                    Button("+") {
                        addPersistentShortcut(after: shortcut.id)
                    }
                    .disabled(!canAddPersistentShortcut)
                }
                .labelsHidden()
            }
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

    private func persistentKeyBinding(for id: UUID) -> Binding<UInt16> {
        Binding(
            get: { persistentSwitcherShortcuts.first(where: { $0.id == id })?.keyCode ?? 0 },
            set: { newValue in
                guard let index = persistentSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
                persistentSwitcherShortcuts[index].keyCode = newValue
            }
        )
    }

    private func persistentModifierBinding(for id: UUID) -> Binding<Int> {
        Binding(
            get: { persistentSwitcherShortcuts.first(where: { $0.id == id })?.modifierFlags ?? 0 },
            set: { newValue in
                guard let index = persistentSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
                persistentSwitcherShortcuts[index].modifierFlags = newValue
                persistentSwitcherShortcuts[index].isConfigured = newValue != 0
                persistentSwitcherShortcuts[index].isPending = false
            }
        )
    }

    private func persistentModeBinding(for id: UUID) -> Binding<SwitcherInvocationMode> {
        Binding(
            get: { persistentSwitcherShortcuts.first(where: { $0.id == id })?.mode ?? .allWindows },
            set: { newValue in
                guard let index = persistentSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
                persistentSwitcherShortcuts[index].mode = newValue
            }
        )
    }

    private func persistentDoubleTapBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { persistentSwitcherShortcuts.first(where: { $0.id == id })?.usesDoubleTap ?? false },
            set: { newValue in
                guard let index = persistentSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
                persistentSwitcherShortcuts[index].usesDoubleTap = newValue
                persistentSwitcherShortcuts[index].isConfigured = newValue || persistentSwitcherShortcuts[index].modifierFlags != 0
                persistentSwitcherShortcuts[index].isPending = false
            }
        )
    }

    private func persistentDoubleTapKeyBinding(for id: UUID) -> Binding<ModifierDoubleTapKey> {
        Binding(
            get: { persistentSwitcherShortcuts.first(where: { $0.id == id })?.doubleTapKey ?? .option },
            set: { newValue in
                guard let index = persistentSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
                persistentSwitcherShortcuts[index].doubleTapKey = newValue
            }
        )
    }

    private func persistentDoubleTapSideBinding(for id: UUID) -> Binding<ModifierKeySide> {
        Binding(
            get: { persistentSwitcherShortcuts.first(where: { $0.id == id })?.doubleTapSide ?? .both },
            set: { newValue in
                guard let index = persistentSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
                persistentSwitcherShortcuts[index].doubleTapSide = newValue
            }
        )
    }

    private func addPersistentShortcut(after id: UUID) {
        guard canAddPersistentShortcut else { return }
        let insertionIndex = min(
            (persistentSwitcherShortcuts.firstIndex(where: { $0.id == id }) ?? (persistentSwitcherShortcuts.count - 1)) + 1,
            persistentSwitcherShortcuts.count
        )
        let usedModes = Set(persistentSwitcherShortcuts.map(\.mode))
        let nextMode = SwitcherInvocationMode.allCases.first { !usedModes.contains($0) } ?? .allWindows
        let pending = PersistentSwitcherShortcut(mode: nextMode, isPending: true)
        persistentSwitcherShortcuts.insert(pending, at: insertionIndex)
    }

    private func removePersistentShortcut(_ id: UUID) {
        guard let index = persistentSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return }
        if persistentSwitcherShortcuts.count == 1 {
            let mode = persistentSwitcherShortcuts[index].mode
            persistentSwitcherShortcuts[index] = PersistentSwitcherShortcut(mode: mode)
        } else {
            persistentSwitcherShortcuts.remove(at: index)
        }
    }

    private func handlePersistentCaptureFinished(for id: UUID, assigned: Bool) {
        guard assigned,
              let index = persistentSwitcherShortcuts.firstIndex(where: { $0.id == id })
        else { return }
        persistentSwitcherShortcuts[index].isConfigured = true
        persistentSwitcherShortcuts[index].isPending = false
    }

    private func ensurePersistentShortcutRow() {
        if persistentSwitcherShortcuts.isEmpty {
            persistentSwitcherShortcuts = PersistentSwitcherShortcut.defaultShortcuts
        }
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
