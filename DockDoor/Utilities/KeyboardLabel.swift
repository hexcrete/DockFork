import AppKit
import Carbon

enum KeyboardLabel {
    static func localizedKey(for keyCode: UInt16) -> String {
        switch keyCode {
        case 48: return String(localized: "Tab")
        case 36: return String(localized: "Return")
        case 51: return String(localized: "Delete")
        case 53: return String(localized: "Escape")
        case 49: return String(localized: "Space")
        case 76: return String(localized: "Enter")
        case 56: return String(localized: "Left Shift ⇧", comment: "Physical keyboard modifier key")
        case 60: return String(localized: "Right Shift ⇧", comment: "Physical keyboard modifier key")
        case 59: return String(localized: "Left Control ⌃", comment: "Physical keyboard modifier key")
        case 62: return String(localized: "Right Control ⌃", comment: "Physical keyboard modifier key")
        case 58: return String(localized: "Left Option ⌥", comment: "Physical keyboard modifier key")
        case 61: return String(localized: "Right Option ⌥", comment: "Physical keyboard modifier key")
        case 55: return String(localized: "Left Command ⌘", comment: "Physical keyboard modifier key")
        case 54: return String(localized: "Right Command ⌘", comment: "Physical keyboard modifier key")
        case 57: return "⇪"
        case 63: return "Fn"
        default: break
        }

        if let result = translatedKey(for: keyCode) {
            return result.uppercased()
        }
        // As a last resort, return the key code itself
        return String(keyCode)
    }

    static func menuKeyEquivalent(for keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_Tab: return "\t"
        case kVK_Return: return "\r"
        case kVK_ANSI_KeypadEnter: return "\u{3}"
        case kVK_Delete: return "\u{8}"
        case kVK_ForwardDelete: return String(UnicodeScalar(NSDeleteFunctionKey)!)
        case kVK_Escape: return "\u{1b}"
        case kVK_Space: return " "
        case kVK_LeftArrow: return String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        case kVK_RightArrow: return String(UnicodeScalar(NSRightArrowFunctionKey)!)
        case kVK_UpArrow: return String(UnicodeScalar(NSUpArrowFunctionKey)!)
        case kVK_DownArrow: return String(UnicodeScalar(NSDownArrowFunctionKey)!)
        case kVK_Home: return String(UnicodeScalar(NSHomeFunctionKey)!)
        case kVK_End: return String(UnicodeScalar(NSEndFunctionKey)!)
        case kVK_PageUp: return String(UnicodeScalar(NSPageUpFunctionKey)!)
        case kVK_PageDown: return String(UnicodeScalar(NSPageDownFunctionKey)!)
        case kVK_Help: return String(UnicodeScalar(NSHelpFunctionKey)!)
        case kVK_F1: return String(UnicodeScalar(NSF1FunctionKey)!)
        case kVK_F2: return String(UnicodeScalar(NSF2FunctionKey)!)
        case kVK_F3: return String(UnicodeScalar(NSF3FunctionKey)!)
        case kVK_F4: return String(UnicodeScalar(NSF4FunctionKey)!)
        case kVK_F5: return String(UnicodeScalar(NSF5FunctionKey)!)
        case kVK_F6: return String(UnicodeScalar(NSF6FunctionKey)!)
        case kVK_F7: return String(UnicodeScalar(NSF7FunctionKey)!)
        case kVK_F8: return String(UnicodeScalar(NSF8FunctionKey)!)
        case kVK_F9: return String(UnicodeScalar(NSF9FunctionKey)!)
        case kVK_F10: return String(UnicodeScalar(NSF10FunctionKey)!)
        case kVK_F11: return String(UnicodeScalar(NSF11FunctionKey)!)
        case kVK_F12: return String(UnicodeScalar(NSF12FunctionKey)!)
        case kVK_F13: return String(UnicodeScalar(NSF13FunctionKey)!)
        case kVK_F14: return String(UnicodeScalar(NSF14FunctionKey)!)
        case kVK_F15: return String(UnicodeScalar(NSF15FunctionKey)!)
        case kVK_F16: return String(UnicodeScalar(NSF16FunctionKey)!)
        case kVK_F17: return String(UnicodeScalar(NSF17FunctionKey)!)
        case kVK_F18: return String(UnicodeScalar(NSF18FunctionKey)!)
        case kVK_F19: return String(UnicodeScalar(NSF19FunctionKey)!)
        case kVK_F20: return String(UnicodeScalar(NSF20FunctionKey)!)
        default:
            guard let translated = translatedKey(for: keyCode),
                  translated.count == 1,
                  translated.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else { return nil }
            return translated.lowercased()
        }
    }

    private static func translatedKey(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let data = unsafeBitCast(ptr, to: CFData.self)
        return translate(from: data, keyCode: keyCode)
    }

    private static func translate(from data: CFData, keyCode: UInt16) -> String? {
        guard let bytes = CFDataGetBytePtr(data) else { return nil }

        var output: String?
        bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            var deadKeyState: UInt32 = 0
            let maxLen = 8
            var chars = [UniChar](repeating: 0, count: maxLen)
            var length = 0

            let err = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0, // no modifiers; we want the base display character for the key
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                maxLen,
                &length,
                &chars
            )

            if err == noErr, length > 0 {
                let str = String(utf16CodeUnits: chars, count: length)
                output = str
            }
        }
        return output
    }
}
