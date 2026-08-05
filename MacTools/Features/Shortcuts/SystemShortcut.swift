import AppKit

/// A keyboard shortcut already registered on this Mac, whatever registered it.
struct SystemShortcut: Identifiable {
    enum Source {
        case system          // com.apple.symbolichotkeys
        case menuOverride    // NSUserKeyEquivalents

        var label: String {
            switch self {
            case .system: return "Raccourcis systeme"
            case .menuOverride: return "Raccourcis de menu personnalises"
            }
        }
    }

    let id: String
    let name: String
    let category: String
    let combo: String
    let isEnabled: Bool
    let source: Source
}

enum ShortcutFormatter {
    /// Sentinel used by macOS for "no key" in symbolic hotkey parameters.
    static let noValue = 65535

    /// Builds "⇧⌘4" from a symbolic hotkey triplet (char code, virtual key code, modifier mask).
    static func combo(charCode: Int, keyCode: Int, modifiers: Int) -> String? {
        guard let key = keyName(charCode: charCode, keyCode: keyCode) else { return nil }
        return modifierSymbols(modifiers) + key
    }

    /// Modifier mask uses NSEvent.ModifierFlags raw values. Apple's display
    /// order is control, option, shift, command.
    static func modifierSymbols(_ mask: Int) -> String {
        var out = ""
        if mask & Int(NSEvent.ModifierFlags.function.rawValue) != 0 { out += "fn" }
        if mask & Int(NSEvent.ModifierFlags.control.rawValue) != 0 { out += "⌃" }
        if mask & Int(NSEvent.ModifierFlags.option.rawValue) != 0 { out += "⌥" }
        if mask & Int(NSEvent.ModifierFlags.shift.rawValue) != 0 { out += "⇧" }
        if mask & Int(NSEvent.ModifierFlags.command.rawValue) != 0 { out += "⌘" }
        return out
    }

    private static func keyName(charCode: Int, keyCode: Int) -> String? {
        // The char code follows the current keyboard layout, so prefer it for
        // printable keys; fall back to the virtual key code for the rest.
        if charCode != noValue, charCode > 32, charCode < 127,
           let scalar = Unicode.Scalar(UInt32(charCode)) {
            return String(Character(scalar)).uppercased()
        }
        if keyCode != noValue, let named = virtualKeyNames[keyCode] {
            return named
        }
        if charCode == noValue && keyCode == noValue { return nil }
        return "touche \(keyCode)"
    }

    /// Virtual key codes that have no usable char code (kVK_* constants).
    private static let virtualKeyNames: [Int: String] = [
        36: "↩", 48: "⇥", 49: "Espace", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9",
        103: "F11", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
        111: "F12", 113: "F15", 114: "Aide", 115: "Debut", 116: "Page haut",
        117: "Suppr. avant", 118: "F4", 119: "Fin", 120: "F2", 121: "Page bas",
        122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// Decodes an NSUserKeyEquivalents value such as "@$s" or "\u{f716}".
    static func combo(fromKeyEquivalent raw: String) -> String {
        var modifiers = ""
        var rest = Substring(raw)
        loop: while let first = rest.first {
            switch first {
            case "^": modifiers += "⌃"
            case "~": modifiers += "⌥"
            case "$": modifiers += "⇧"
            case "@": modifiers += "⌘"
            default: break loop
            }
            rest = rest.dropFirst()
        }

        guard let key = rest.first else { return modifiers }
        // Function keys live in the private use area, NSF1FunctionKey = 0xF704.
        if let scalar = key.unicodeScalars.first, (0xF704...0xF71F).contains(scalar.value) {
            return modifiers + "F\(scalar.value - 0xF704 + 1)"
        }
        return modifiers + String(key).uppercased()
    }
}
