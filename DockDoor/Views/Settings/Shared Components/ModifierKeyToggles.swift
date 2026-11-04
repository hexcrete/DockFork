import SwiftUI

struct ModifierKeyToggles: View {
    @Binding var modifierFlags: Int
    var compact = false
    var inheritedModifierFlags: Int?
    var includesShift = false

    private var modifiers: [ShortcutModifierKey] {
        ShortcutModifierKey.allCases.filter { includesShift || $0 != .shift }
    }

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(modifiers) { modifier in
                toggle(for: modifier)
            }
        }
    }

    static func toggledModifiers(_ current: Int, mask: Int, allowsEmpty: Bool) -> Int {
        let flags = WindowSwitcherShortcutResolver.normalizedModifiers(current)
        let updated = flags & mask != 0 ? flags & ~mask : flags | mask
        return updated == 0 && !allowsEmpty ? current : updated
    }

    private func toggle(for modifier: ShortcutModifierKey) -> some View {
        let isOn = modifierFlags & modifier.modifierFlags != 0
        let isInherited = modifierFlags == 0 && (inheritedModifierFlags ?? 0) & modifier.modifierFlags != 0
        let name = modifierConverter.toString(modifier.modifierFlags)
        let symbol = modifierConverter.toSymbol(modifier.modifierFlags)

        return Button {
            modifierFlags = Self.toggledModifiers(modifierFlags, mask: modifier.modifierFlags, allowsEmpty: inheritedModifierFlags != nil)
        } label: {
            Text(compact ? symbol : "\(name) \(symbol)")
                .font(.system(size: compact ? 13 : 12, weight: .medium))
                .foregroundColor(isOn ? .white : .primary)
                .frame(minWidth: compact ? 22 : nil)
                .padding(.horizontal, compact ? 4 : 10)
                .padding(.vertical, compact ? 2 : 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isOn ? Color.accentColor : isInherited ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isInherited ? String(localized: "\(name), inherited from the main shortcut") : name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
