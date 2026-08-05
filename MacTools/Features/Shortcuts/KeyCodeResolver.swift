import Carbon.HIToolbox
import Foundation

/// Turns a key written in the config ("l", "f5", "space") into the virtual key
/// code Carbon expects. Characters go through the *current keyboard layout*, so
/// on the French layout "a" resolves to the key that actually types an A.
enum KeyCodeResolver {
    static func keyCode(for key: String) -> UInt32? {
        let normalized = key.trimmingCharacters(in: .whitespaces).lowercased()
        if let named = namedKeys[normalized] { return named }
        guard normalized.count == 1, let character = normalized.first else { return nil }
        return layoutMap[character]
    }

    /// How the key reads in the UI.
    static func displayName(for key: String) -> String {
        let normalized = key.trimmingCharacters(in: .whitespaces).lowercased()
        if let pretty = namedKeyLabels[normalized] { return pretty }
        return normalized.uppercased()
    }

    static var knownKeyNames: [String] {
        namedKeys.keys.sorted()
    }

    /// character -> virtual key code, built from the layout currently selected.
    private static let layoutMap: [Character: UInt32] = {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return [:] }

        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return [:] }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let keyboardType = UInt32(LMGetKbdType())

        var map: [Character: UInt32] = [:]
        for code in 0..<128 {
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                UInt16(code),
                UInt16(kUCKeyActionDisplay),
                0, // no modifiers: we want the bare key
                keyboardType,
                UInt32(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { continue }
            let produced = String(utf16CodeUnits: characters, count: length).lowercased()
            guard let character = produced.first, map[character] == nil else { continue }
            map[character] = UInt32(code)
        }
        return map
    }()

    private static let namedKeys: [String: UInt32] = [
        "space": UInt32(kVK_Space),
        "return": UInt32(kVK_Return),
        "enter": UInt32(kVK_ANSI_KeypadEnter),
        "tab": UInt32(kVK_Tab),
        "escape": UInt32(kVK_Escape),
        "esc": UInt32(kVK_Escape),
        "delete": UInt32(kVK_Delete),
        "forwarddelete": UInt32(kVK_ForwardDelete),
        "help": UInt32(kVK_Help),
        "home": UInt32(kVK_Home),
        "end": UInt32(kVK_End),
        "pageup": UInt32(kVK_PageUp),
        "pagedown": UInt32(kVK_PageDown),
        "left": UInt32(kVK_LeftArrow),
        "right": UInt32(kVK_RightArrow),
        "up": UInt32(kVK_UpArrow),
        "down": UInt32(kVK_DownArrow),
        "f1": UInt32(kVK_F1), "f2": UInt32(kVK_F2), "f3": UInt32(kVK_F3),
        "f4": UInt32(kVK_F4), "f5": UInt32(kVK_F5), "f6": UInt32(kVK_F6),
        "f7": UInt32(kVK_F7), "f8": UInt32(kVK_F8), "f9": UInt32(kVK_F9),
        "f10": UInt32(kVK_F10), "f11": UInt32(kVK_F11), "f12": UInt32(kVK_F12),
        "f13": UInt32(kVK_F13), "f14": UInt32(kVK_F14), "f15": UInt32(kVK_F15),
        "f16": UInt32(kVK_F16), "f17": UInt32(kVK_F17), "f18": UInt32(kVK_F18),
        "f19": UInt32(kVK_F19), "f20": UInt32(kVK_F20),
    ]

    private static let namedKeyLabels: [String: String] = [
        "space": "Espace", "return": "↩", "enter": "⌤", "tab": "⇥",
        "escape": "⎋", "esc": "⎋", "delete": "⌫", "forwarddelete": "⌦",
        "help": "Aide", "home": "Debut", "end": "Fin",
        "pageup": "Page haut", "pagedown": "Page bas",
        "left": "←", "right": "→", "up": "↑", "down": "↓",
    ]
}
