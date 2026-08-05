import Foundation

/// A shortcut Mickael owns: a key combo plus the action it fires.
/// Persisted as JSON so Claude can add one over IPC without touching the UI.
struct UserShortcut: Codable, Identifiable, Equatable {
    enum Modifier: String, Codable, CaseIterable {
        case command, shift, option, control

        var symbol: String {
            switch self {
            case .control: return "⌃"
            case .option: return "⌥"
            case .shift: return "⇧"
            case .command: return "⌘"
            }
        }
    }

    struct Action: Codable, Equatable {
        enum Kind: String, Codable {
            case shell
        }

        var type: Kind
        var command: String

        init(type: Kind = .shell, command: String) {
            self.type = type
            self.command = command
        }
    }

    var id: String
    var name: String
    /// A single character ("l") or a named key ("f5", "space"). Characters are
    /// resolved against the current keyboard layout, so "l" means the key that
    /// types an L on an AZERTY board too.
    var key: String
    var modifiers: [Modifier]
    var action: Action
    var enabled: Bool

    init(
        id: String,
        name: String,
        key: String,
        modifiers: [Modifier],
        action: Action,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.key = key
        self.modifiers = modifiers
        self.action = action
        self.enabled = enabled
    }

    /// Modifiers in Apple's display order, then the key.
    var combo: String {
        let order: [Modifier] = [.control, .option, .shift, .command]
        let symbols = order.filter(modifiers.contains).map(\.symbol).joined()
        return symbols + KeyCodeResolver.displayName(for: key)
    }
}

/// What happened the last time an action ran.
struct ActionResult: Equatable {
    let date: Date
    let exitCode: Int32
    let output: String

    var succeeded: Bool { exitCode == 0 }
}
