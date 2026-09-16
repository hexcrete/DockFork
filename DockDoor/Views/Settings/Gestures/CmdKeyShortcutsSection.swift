import Defaults
import SwiftUI

struct CmdKeyShortcutsSection: View {
    @Default(.cmdShortcuts) var cmdShortcuts
    @Default(.UserKeybind) private var windowSwitcherKeybind
    @State private var autoCaptureShortcutID: UUID?

    var body: some View {
        SettingsGroup(header: "Window Preview Keyboard Shortcuts") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Uses the active Window Switcher modifier for preview actions. Cmd+Tab uses Command while the macOS switcher is active.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                if cmdShortcuts.isEmpty {
                    HStack(spacing: 8) {
                        Text("No shortcuts configured.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer(minLength: 0)

                        Button("Add a Shortcut") {
                            addShortcut(after: nil)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!canAddShortcut)
                    }
                } else {
                    ForEach(indexedShortcuts, id: \.shortcut.id) { item in
                        cmdShortcutRow(index: item.index, shortcut: item.shortcut)
                    }
                }

                HStack(spacing: 8) {
                    Button("Reset to Defaults") {
                        cmdShortcuts = Defaults.Keys.cmdShortcuts.defaultValue
                        autoCaptureShortcutID = nil
                    }
                    .buttonStyle(AccentButtonStyle(small: true))
                }
                .padding(.top, 4)
            }
            .settingsSearchTarget("gestures.cmdShortcuts")
            .onAppear {
                removeUnassignedRowsIfNeeded()
            }
        }
    }

    private var indexedShortcuts: [(index: Int, shortcut: CmdShortcut)] {
        Array(cmdShortcuts.enumerated()).map { (index: $0.offset, shortcut: $0.element) }
    }

    private var maxShortcutCount: Int {
        max(0, WindowAction.gestureActions.count - 1)
    }

    private var hasPendingShortcut: Bool {
        cmdShortcuts.contains { $0.isPending }
    }

    private var canAddShortcut: Bool {
        cmdShortcuts.count < maxShortcutCount && !hasPendingShortcut
    }

    private func cmdShortcutRow(index: Int, shortcut: CmdShortcut) -> some View {
        let isShadowedByHigherPriorityShortcut = isShadowed(index: index)

        return HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(modifierConverter.toSymbol(windowSwitcherKeybind.modifierFlags))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                KeyCaptureButton(
                    keyCode: keyBinding(for: shortcut.id),
                    emptyLabel: "Not set",
                    forceEmptyLabel: shortcut.isPending,
                    treatKeyCodeZeroAsEmpty: false,
                    autoStartCapture: autoCaptureShortcutID == shortcut.id,
                    onCaptureFinished: { assigned in
                        handleCaptureFinished(for: shortcut.id, assigned: assigned)
                    }
                )
            }
            .frame(minWidth: 80, alignment: .leading)

            Picker("", selection: actionBinding(for: shortcut.id)) {
                ForEach(WindowAction.gestureActions, id: \.self) { windowAction in
                    HStack(spacing: 6) {
                        Image(systemName: windowAction.iconName)
                        Text(windowAction.localizedName)
                    }
                    .tag(windowAction)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .disabled(shortcut.isPending)

            if isShadowedByHigherPriorityShortcut {
                Text("Duplicate shortcut. Action disabled.")
                    .font(.caption2)
                    .foregroundColor(.red)
            }

            Spacer(minLength: 0)

            ControlGroup {
                Button("-") {
                    removeShortcut(shortcut.id)
                }
                Button("+") {
                    addShortcut(after: shortcut.id)
                }
                .disabled(!canAddShortcut)
            }
            .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            if isShadowedByHigherPriorityShortcut {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isShadowedByHigherPriorityShortcut {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red.opacity(0.28), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func keyBinding(for id: UUID) -> Binding<UInt16> {
        Binding(
            get: {
                cmdShortcuts.first(where: { $0.id == id })?.keyCode ?? 0
            },
            set: { newValue in
                guard let rowIndex = cmdShortcuts.firstIndex(where: { $0.id == id }) else { return }
                cmdShortcuts[rowIndex].keyCode = newValue
                cmdShortcuts[rowIndex].isPending = false
            }
        )
    }

    private func actionBinding(for id: UUID) -> Binding<WindowAction> {
        Binding(
            get: {
                cmdShortcuts.first(where: { $0.id == id })?.action ?? .none
            },
            set: { newValue in
                guard let rowIndex = cmdShortcuts.firstIndex(where: { $0.id == id }) else { return }
                cmdShortcuts[rowIndex].action = newValue
            }
        )
    }

    private func isShadowed(index: Int) -> Bool {
        guard cmdShortcuts.indices.contains(index) else { return false }
        let candidate = cmdShortcuts[index]
        guard !candidate.isPending, candidate.action != .none else { return false }

        for higherPriorityIndex in 0 ..< index {
            let existing = cmdShortcuts[higherPriorityIndex]
            if !existing.isPending, existing.keyCode == candidate.keyCode, existing.action != .none {
                return true
            }
        }

        return false
    }

    private func removeShortcut(_ id: UUID) {
        cmdShortcuts.removeAll { $0.id == id }
        if autoCaptureShortcutID == id {
            autoCaptureShortcutID = nil
        }
    }

    private func addShortcut(after id: UUID?) {
        guard canAddShortcut else { return }
        let insertionIndex = if let id {
            min((cmdShortcuts.firstIndex(where: { $0.id == id }) ?? (cmdShortcuts.count - 1)) + 1, cmdShortcuts.count)
        } else {
            0
        }
        let pending = CmdShortcut(keyCode: 0, action: .none, isPending: true)
        cmdShortcuts.insert(pending, at: insertionIndex)
        autoCaptureShortcutID = pending.id
    }

    private func handleCaptureFinished(for id: UUID, assigned: Bool) {
        defer {
            if autoCaptureShortcutID == id {
                autoCaptureShortcutID = nil
            }
        }

        guard !assigned else { return }
        guard let rowIndex = cmdShortcuts.firstIndex(where: { $0.id == id }) else { return }
        if cmdShortcuts[rowIndex].isPending {
            cmdShortcuts.remove(at: rowIndex)
        }
    }

    private func removeUnassignedRowsIfNeeded() {
        let cleaned = cmdShortcuts.filter { !$0.isPending }
        if cleaned.count != cmdShortcuts.count {
            cmdShortcuts = cleaned
        }
        if let autoCaptureShortcutID, !cleaned.contains(where: { $0.id == autoCaptureShortcutID }) {
            self.autoCaptureShortcutID = nil
        }
    }
}

struct PreviewPostActionBehaviorSection: View {
    @Default(.movingResizingPostActionBehavior) private var movingResizingBehavior
    @Default(.hidingPostActionBehavior) private var hidingBehavior
    @Default(.unhidingPostActionBehavior) private var unhidingBehavior
    @Default(.closingPostActionBehavior) private var closingBehavior
    @Default(.newWindowPostActionBehavior) private var newWindowBehavior
    @Default(.moveResizeBringToForeground) private var moveResizeBringToForeground

    var body: some View {
        SettingsGroup(header: "Keep previews open after action") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Select action types that should keep previews open. Unchecked actions close previews after running. Some actions may still change focus based on app/macOS behavior.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    postActionBehaviorRow(
                        category: .closing,
                        icon: "xmark.circle",
                        selection: $closingBehavior
                    )
                    .settingsSearchTarget("gestures.postActionClosing")

                    postActionBehaviorRow(
                        category: .hiding,
                        icon: "eye.slash",
                        selection: $hidingBehavior
                    )
                    .settingsSearchTarget("gestures.postActionHiding")

                    postActionBehaviorRow(
                        category: .unhiding,
                        icon: "eye",
                        selection: $unhidingBehavior
                    )
                    .settingsSearchTarget("gestures.postActionUnhiding")

                    postActionBehaviorRow(
                        category: .newWindow,
                        icon: "plus.rectangle.on.rectangle",
                        selection: $newWindowBehavior
                    )
                    .settingsSearchTarget("gestures.postActionNewWindow")

                    VStack(alignment: .leading, spacing: 8) {
                        postActionBehaviorRow(
                            category: .movingAndResizing,
                            icon: "arrow.up.left.and.arrow.down.right",
                            selection: $movingResizingBehavior
                        )
                        .settingsSearchTarget("gestures.postActionMovingResizing")

                        Toggle("Bring moved/resized window to the front", isOn: $moveResizeBringToForeground)
                            .settingsSearchTarget("gestures.moveResizeForeground")
                            .padding(.leading, 32)
                    }
                }
            }
        }
    }

    private func postActionBehaviorRow(
        category: WindowAction.PostActionCategory,
        icon: String,
        selection: Binding<Bool>
    ) -> some View {
        Toggle(isOn: selection) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                Text(category.localizedName)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .toggleStyle(.checkbox)
    }
}
