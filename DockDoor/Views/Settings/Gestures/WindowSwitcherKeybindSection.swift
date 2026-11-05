import Carbon.HIToolbox
import Defaults
import SwiftUI

struct WindowSwitcherKeybindSection: View {
    @Default(.enableWindowSwitcherSearch) var enableWindowSwitcherSearch
    @Default(.searchTriggerKey) var searchTriggerKey
    @Default(.fullscreenAppBlacklist) var fullscreenAppBlacklist
    @Default(.requireShiftTabToGoBack) var requireShiftTabToGoBack
    @Default(.switcherBackwardKeyCode) var switcherBackwardKeyCode
    @Default(.windowSwitcherSelectionKeyCode) var selectionKeyCode
    @Default(.enableVimMotions) var enableVimMotions
    @Default(.passArrowsThroughToSystem) var passArrowsThroughToSystem
    @Default(.showSettingsDescriptions) var showSettingsDescriptions

    @Default(.alternateSwitcherShortcuts) var alternateSwitcherShortcuts
    @Default(.cmdShortcuts) private var cmdShortcuts
    @Default(.UserKeybind) private var mainKeybind
    @Default(.enableSpacesShortcuts) private var enableSpacesShortcuts
    @Default(.enableSpacesBar) private var enableSpacesBar
    @Default(.spacesBarCycleKey) private var spacesBarCycleKey
    @Default(.spacesBarBackwardCycleKey) private var spacesBarBackwardCycleKey
    @Default(.ignoreMainModifierSideForDependentShortcuts) private var ignoreMainModifierSideForDependentShortcuts
    @Default(.openWindowSwitcherFromMenuBarIcon) var openWindowSwitcherFromMenuBarIcon
    @Default(.menuBarIconWindowSwitcherClick) var menuBarIconWindowSwitcherClick

    @StateObject private var keybindModel = KeybindModel()
    @State private var showingAddBlacklistAppSheet = false
    @State private var newBlacklistApp = ""
    @State private var primaryCaptureToken: UUID?

    var body: some View {
        SettingsSection("Window Switcher Shortcuts") {
            initializerRow
                .settingsSearchTarget("gestures.switcherKeybind")
                .settingsAnnotation("Click modifier keys to combine them, then choose Left, Right, or Either. You can also hold the modifiers while recording a trigger key.")

            if keybindModel.modifierSide != .either {
                Toggle("Ignore modifier key side for Window Preview Keyboard Shortcuts", isOn: $ignoreMainModifierSideForDependentShortcuts)
                    .settingsSearchTarget("gestures.ignoreMainModifierSideForDependentShortcuts")
                    .settingsAnnotation("Allows either side of the selected modifier to trigger shortcuts that inherit the main Window Switcher modifier. The main Window Switcher shortcut still uses the selected side.")
            }
            triggerKeyRow

            LabeledContent("Backward Key") {
                SettingsKeyCaptureControls(keyCode: $switcherBackwardKeyCode, defaultKeyCode: 56, captureModifiers: true)
            }
            .settingsSearchTarget("gestures.backwardKey")
            .settingsAnnotation("The key used to navigate backward in the window switcher.")

            Toggle(isOn: $requireShiftTabToGoBack) {
                Text("Require \(KeyboardLabel.localizedKey(for: switcherBackwardKeyCode))+Tab to go back in Switcher")
            }
            .settingsSearchTarget("gestures.requireShiftTab")
            .settingsAnnotation("When enabled, pressing the backward key alone won't go back. Use it with Tab to navigate backward.")

            LabeledContent("Selection Key") {
                SettingsKeyCaptureControls(keyCode: $selectionKeyCode, defaultKeyCode: UInt16(kVK_Return))
            }
            .settingsSearchTarget("gestures.selectionKey")
            .settingsAnnotation("The key used to select and bring to front the highlighted window in the switcher.")

            if enableWindowSwitcherSearch {
                LabeledContent("Search Trigger Key") {
                    SettingsKeyCaptureControls(keyCode: $searchTriggerKey, defaultKeyCode: Defaults.Keys.searchTriggerKey.defaultValue, modifierLabel: modifierConverter.toSymbol(searchShortcutKeybind), conflict: searchShortcutConflict)
                }
                .settingsSearchTarget("gestures.searchTriggerKey")
                .settingsAnnotation("The key that activates search while the window switcher is open.")
            }
        }
        .onChange(of: keybindModel.isRecording) { recording in
            if recording {
                primaryCaptureToken = SettingsShortcutCaptureState.shared.begin { keybindModel.isRecording = false }
            } else {
                SettingsShortcutCaptureState.shared.end(primaryCaptureToken)
                primaryCaptureToken = nil
            }
        }
        .onDisappear {
            keybindModel.isRecording = false
            SettingsShortcutCaptureState.shared.end(primaryCaptureToken)
            primaryCaptureToken = nil
        }
        .onAppear {
            keybindModel.modifierSide = Defaults[.UserKeybind].modifierSide
            keybindModel.modifierKey = Defaults[.UserKeybind].modifierFlags
            keybindModel.currentKeybind = Defaults[.UserKeybind]
        }

        Section {
            ForEach(alternateSwitcherShortcuts.map(\.id), id: \.self) { id in
                alternateShortcutRow(id: id)
            }
            SettingsShortcutListFooter(title: "Add Alternate Shortcut", canAdd: canAddAlternateShortcut, onAdd: { addAlternateShortcut(after: nil) }) {
                alternateSwitcherShortcuts = Defaults.Keys.alternateSwitcherShortcuts.defaultValue
            }
        } header: {
            VStack(alignment: .leading, spacing: 3) {
                Text("Alternate Shortcuts")
                if showSettingsDescriptions {
                    Text("Additional shortcuts open the switcher with their selected filter mode. Persistent keeps it open after releasing the modifiers.")
                        .font(.footnote)
                        .fontWeight(.regular)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text("When no modifiers are selected, the main shortcut's modifiers and side are inherited. Persistent keeps the switcher open after release. Double-tap uses the chosen modifier twice instead of a trigger key. Quick Switch activates the last-focused window within the selected filter mode without opening the switcher.")
        }
        .settingsSearchTarget("gestures.alternateShortcut")
        SettingsSection("Menu Bar Icon") { menuBarIconSection }

        SettingsSection("Navigation") {
            Toggle(isOn: $enableVimMotions) {
                Text("Enable Vim Motions")
            }
            .settingsSearchTarget("gestures.vimMotions")
            .settingsAnnotation("Use H/J/K/L keys to navigate left/down/up/right in the window switcher. Disabled while search is focused.")

            Toggle(isOn: $passArrowsThroughToSystem) {
                Text("Pass Arrow Keys Through to System")
            }
            .settingsSearchTarget("gestures.arrowPassthrough")
            .settingsAnnotation("When enabled, Ctrl+Arrow keys will be passed through to the system instead of navigating the switcher. Useful for Spaces switching.")
        }

        SettingsListSection(
            title: "Fullscreen App Blacklist",
            footer: "Apps in this list will not respond to window switcher shortcuts when in fullscreen mode.",
            items: fullscreenAppBlacklist,
            itemIcon: "app",
            emptyText: "No apps in blacklist",
            addTitle: "Add App",
            onAdd: { showingAddBlacklistAppSheet = true },
            onRemove: { appName in fullscreenAppBlacklist.removeAll { $0 == appName } },
            onRemoveAll: { fullscreenAppBlacklist.removeAll() }
        )
        .settingsSearchTarget("gestures.fullscreenBlacklist")
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

    // MARK: - Shortcut

    private var initializerRow: some View {
        LabeledContent("Initializer") {
            HStack(spacing: 8) {
                ModifierKeyToggles(modifierFlags: $keybindModel.modifierKey)
                ModifierSidePicker(selection: $keybindModel.modifierSide)
            }
        }
        .onChange(of: keybindModel.modifierKey) { _ in updatePrimaryKeybind() }
        .onChange(of: keybindModel.modifierSide) { _ in updatePrimaryKeybind() }
    }

    private var triggerKeyRow: some View {
        LabeledContent("Trigger Key") {
            HStack(spacing: 8) {
                if let keybind = keybindModel.currentKeybind {
                    KeyCapView(text: KeyboardLabel.localizedKey(for: keybind.keyCode), symbol: nil)
                } else {
                    Text("No shortcut set").foregroundStyle(.secondary)
                }

                Button(keybindModel.isRecording ? "Press shortcut…" : "Change…") {
                    keybindModel.isRecording.toggle()
                }
                .buttonStyle(.settings)
                .disabled(keybindModel.isRecording)

                SettingsResetButton(isModified: !isDefaultShortcut) {
                    Defaults[.UserKeybind] = Self.defaultKeybind
                    keybindModel.currentKeybind = Self.defaultKeybind
                    keybindModel.modifierKey = Self.defaultKeybind.modifierFlags
                    keybindModel.modifierSide = Self.defaultKeybind.modifierSide
                }
                .frame(width: 16)
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

    // MARK: - Alternate Shortcuts

    private static let defaultKeybind = UserKeyBind(keyCode: 48, modifierFlags: Defaults[.Int64maskAlternate], modifierSide: .left)

    private var isDefaultShortcut: Bool {
        keybindModel.currentKeybind == Self.defaultKeybind
    }

    private var searchShortcutKeybind: UserKeyBind {
        WindowSwitcherShortcutResolver.dependentShortcutKeybind(mainKeybind, ignoreModifierSide: ignoreMainModifierSideForDependentShortcuts)
    }

    private var searchShortcutConflict: AlternateSwitcherShortcutConflict? {
        let _ = (cmdShortcuts, alternateSwitcherShortcuts,
                 enableSpacesShortcuts, enableSpacesBar, spacesBarCycleKey, spacesBarBackwardCycleKey,
                 switcherBackwardKeyCode, selectionKeyCode, enableVimMotions, searchTriggerKey)
        return WindowSwitcherShortcutResolver.searchTriggerConflict(previewKeybind: searchShortcutKeybind, mainKeybind: mainKeybind)
    }

    private var canAddAlternateShortcut: Bool {
        !alternateSwitcherShortcuts.contains { $0.isPending || (!$0.isConfigured && !$0.usesDoubleTap) }
    }

    private func editedShortcut(_ id: UUID) -> AlternateSwitcherShortcut? {
        alternateSwitcherShortcuts.first { $0.id == id }
    }

    private func editShortcut(_ id: UUID, _ update: (inout AlternateSwitcherShortcut) -> Void) {
        guard var shortcut = editedShortcut(id) else { return }
        update(&shortcut)
        if let index = alternateSwitcherShortcuts.firstIndex(where: { $0.id == id }) {
            alternateSwitcherShortcuts[index] = shortcut
        }
    }

    private func alternateKeyBinding(for id: UUID) -> Binding<UInt16> {
        Binding(get: { editedShortcut(id)?.keyCode ?? 0 }, set: { value in
            editShortcut(id) { $0.keyCode = value; $0.isConfigured = true; $0.isPending = false }
        })
    }

    private func alternateModifierBinding(for id: UUID) -> Binding<Int> {
        Binding(get: { editedShortcut(id)?.modifierFlags ?? 0 }, set: { value in
            editShortcut(id) { $0.modifierFlags = value }
        })
    }

    private func alternateSideBinding(for id: UUID) -> Binding<ModifierKeySide> {
        Binding(get: { editedShortcut(id)?.modifierSide ?? .either }, set: { value in
            editShortcut(id) { $0.modifierSide = value }
        })
    }

    private func alternateModeBinding(for id: UUID) -> Binding<SwitcherInvocationMode> {
        Binding(get: { editedShortcut(id)?.mode ?? .activeAppOnly }, set: { value in
            editShortcut(id) { $0.mode = value }
        })
    }

    private func persistentBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { editedShortcut(id)?.persistent ?? false }, set: { value in
            editShortcut(id) { $0.persistent = value }
        })
    }

    private func doubleTapBinding(for id: UUID) -> Binding<Bool> {
        Binding(get: { editedShortcut(id)?.usesDoubleTap ?? false }, set: { value in
            editShortcut(id) { $0.usesDoubleTap = value; $0.isPending = !value && !$0.isConfigured }
        })
    }

    private func addAlternateShortcut(after _: UUID?) {
        guard canAddAlternateShortcut else { return }
        alternateSwitcherShortcuts.append(AlternateSwitcherShortcut(modifierSide: mainKeybind.modifierSide, isPending: true))
    }

    private func removeAlternateShortcut(_ id: UUID) {
        alternateSwitcherShortcuts.removeAll { $0.id == id }
    }

    private var menuBarIconSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Menu bar icon", isOn: $openWindowSwitcherFromMenuBarIcon)
                .settingsSearchTarget("gestures.menuBarIconWindowSwitcher")
                .settingsAnnotation("Open Window Switcher when clicking on menu bar icon")

            if openWindowSwitcherFromMenuBarIcon {
                Picker("Clicks trigger:", selection: $menuBarIconWindowSwitcherClick) {
                    ForEach(MenuBarIconWindowSwitcherClick.allCases, id: \.self) { click in
                        Text(click.localizedName).tag(click)
                    }
                }

                .pickerStyle(.menu)
                .settingsSearchTarget("gestures.menuBarIconClickBehavior")
            }
        }
    }

    private func updatePrimaryKeybind() {
        guard let current = keybindModel.currentKeybind else { return }
        let updated = UserKeyBind(keyCode: current.keyCode, modifierFlags: keybindModel.modifierKey, modifierSide: keybindModel.modifierSide)
        Defaults[.UserKeybind] = updated
        keybindModel.currentKeybind = updated
    }

    @ViewBuilder
    private func alternateShortcutRow(id: UUID) -> some View {
        if let shortcut = editedShortcut(id) {
            let conflict = alternateConflict(for: id)
            VStack(alignment: .leading, spacing: 8) {
                SettingsShortcutRow {
                    HStack(spacing: 8) {
                        if shortcut.usesDoubleTap {
                            Picker("Modifier", selection: Binding(get: { editedShortcut(id)?.doubleTapKey ?? .option }, set: { value in editShortcut(id) { $0.doubleTapKey = value } })) {
                                ForEach(ShortcutModifierKey.allCases) { key in Text(key.localizedName).tag(key) }
                            }
                            .labelsHidden()
                            ModifierSidePicker(selection: Binding(get: { editedShortcut(id)?.doubleTapSide ?? .either }, set: { value in editShortcut(id) { $0.doubleTapSide = value } }))
                        } else {
                            ModifierKeyToggles(modifierFlags: alternateModifierBinding(for: id), compact: true, inheritedModifierFlags: mainKeybind.modifierFlags, includesShift: true)
                            if shortcut.modifierFlags != 0 { ModifierSidePicker(selection: alternateSideBinding(for: id)) }
                            KeyCaptureButton(keyCode: alternateKeyBinding(for: id), emptyLabel: "Not set", forceEmptyLabel: !shortcut.isConfigured,
                                             treatKeyCodeZeroAsEmpty: false, allowsEscape: true, cancelOnOutsideClick: true,
                                             modifierFlags: alternateModifierBinding(for: id))
                        }
                        SettingsShortcutConflictWarning(conflict: conflict)
                    }
                } options: {
                    SettingsShortcutModePicker(selection: alternateModeBinding(for: id))
                } onRemove: {
                    removeAlternateShortcut(id)
                }
                SettingsDependentRows {
                    HStack(spacing: 12) {
                        Toggle("Double-tap", isOn: doubleTapBinding(for: id))
                            .toggleStyle(.checkbox)
                            .fixedSize()
                            .help("Press and release the chosen modifier, then press it again to open the switcher without a trigger key.")
                        Toggle("Persistent", isOn: persistentBinding(for: id)).toggleStyle(.checkbox).fixedSize()
                            .help("Keep the switcher open after releasing the shortcut modifiers.")
                            .disabled(shortcut.quickSwitch)
                        Toggle("Quick Switch", isOn: Binding(get: { editedShortcut(id)?.quickSwitch ?? false }, set: { value in
                            editShortcut(id) { $0.quickSwitch = value }
                        }))
                        .toggleStyle(.checkbox)
                        .fixedSize()
                        .help("Switch immediately to the last focused window in this scope without opening the switcher.")
                        .settingsSearchTarget("gestures.alternateQuickSwitch")
                    }
                }
            }
        }
    }

    private func alternateConflict(for id: UUID) -> AlternateSwitcherShortcutConflict? {
        guard let index = alternateSwitcherShortcuts.firstIndex(where: { $0.id == id }) else { return nil }
        return WindowSwitcherShortcutResolver.alternateConflict(at: index, shortcuts: alternateSwitcherShortcuts, mainKeybind: mainKeybind, previewShortcuts: cmdShortcuts)
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
