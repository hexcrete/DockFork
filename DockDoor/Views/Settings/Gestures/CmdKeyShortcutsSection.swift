import Defaults
import SwiftUI

struct CmdKeyShortcutsSection: View {
    @Default(.cmdShortcuts) var cmdShortcuts
    @State private var autoCaptureShortcutID: UUID?

    var body: some View {
        SettingsGroup(header: "Window Preview Keyboard Shortcuts") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cmd+key shortcuts for quick actions on the selected window preview. These work in both the window switcher and Cmd+Tab enhancement mode.")
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
                Text("⌘")
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
