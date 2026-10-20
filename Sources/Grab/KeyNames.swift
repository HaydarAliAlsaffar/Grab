import Carbon.HIToolbox
import Foundation

/// Readable names for key codes and Carbon modifier masks.
enum KeyNames {
    private static let special: [Int: String] = [
        kVK_Return: "Return", kVK_Tab: "Tab", kVK_Space: "Space", kVK_Delete: "Delete",
        kVK_Escape: "Esc", kVK_ForwardDelete: "Fwd Delete", kVK_Home: "Home", kVK_End: "End",
        kVK_PageUp: "Page Up", kVK_PageDown: "Page Down", kVK_LeftArrow: "Left", kVK_RightArrow: "Right",
        kVK_DownArrow: "Down", kVK_UpArrow: "Up", kVK_Help: "Help", kVK_ANSI_KeypadEnter: "Enter",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// Modifier symbols for a Carbon mask, in the usual macOS order.
    static func symbols(forModifiers mask: Int) -> String {
        var text = ""
        if mask & controlKey != 0 { text += "\u{2303}" }
        if mask & optionKey != 0 { text += "\u{2325}" }
        if mask & shiftKey != 0 { text += "\u{21E7}" }
        if mask & cmdKey != 0 { text += "\u{2318}" }
        return text
    }

    /// The symbols plus the key name, for example "⌃⌥⌘D".
    static func display(code: Int, modifiers: Int) -> String {
        symbols(forModifiers: modifiers) + name(for: code)
    }

    static func name(for code: Int) -> String {
        if let name = special[code] { return name }
        if let letter = layoutCharacter(for: code) { return letter }
        return "Key \(code)"
    }

    /// The character the key types with no modifiers on the current layout, uppercased.
    private static func layoutCharacter(for code: Int) -> String? {
        guard code >= 0, code <= Int(UInt16.max),
              let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)

        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        // The layout bytes belong to `data`, which belongs to `source`. Keep both alive.
        let status = withExtendedLifetime((source, data)) {
            UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                           &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0, length <= chars.count else { return nil }
        let text = String(utf16CodeUnits: chars, count: length).uppercased()
        // Skip control characters and blanks.
        guard text.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace && $0.value >= 0x20 && $0.value != 0x7F })
        else { return nil }
        return text
    }
}
