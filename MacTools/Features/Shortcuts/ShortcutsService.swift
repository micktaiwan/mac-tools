import AppKit
import Foundation

/// Inventory of the keyboard shortcuts already registered on this Mac.
///
/// Two sources, both readable without any permission prompt:
/// - `com.apple.symbolichotkeys`, where macOS stores its own hotkeys;
/// - `NSUserKeyEquivalents` in the global domain, where menu shortcut
///   overrides are stored.
///
/// Human names come from Apple's own tables shipped with the Keyboard
/// settings pane, so nothing here is a hardcoded guess. Ids missing from
/// those tables are listed with their number rather than invented.
@MainActor
final class ShortcutsService: ObservableObject {
    @Published private(set) var shortcuts: [SystemShortcut] = []

    init() {
        reload()
    }

    func reload() {
        shortcuts = Self.readSymbolicHotKeys() + Self.readMenuOverrides()
    }

    var enabledCount: Int { shortcuts.filter(\.isEnabled).count }

    // MARK: - com.apple.symbolichotkeys

    private static func readSymbolicHotKeys() -> [SystemShortcut] {
        let raw = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString,
            "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any] ?? [:]

        let names = AppleShortcutNames()

        return raw.compactMap { key, value -> SystemShortcut? in
            guard let id = Int(key), let entry = value as? [String: Any] else { return nil }

            let isEnabled = (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) == 1)
            let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int]
            let combo = parameters.flatMap { params -> String? in
                guard params.count >= 3 else { return nil }
                return ShortcutFormatter.combo(
                    charCode: params[0],
                    keyCode: params[1],
                    modifiers: params[2]
                )
            }

            let known = names.entry(for: id)
            return SystemShortcut(
                id: "symbolic-\(id)",
                name: known?.name ?? "Raccourci systeme #\(id)",
                category: known?.category ?? "Non identifie",
                combo: combo ?? "Aucune touche",
                isEnabled: isEnabled,
                source: .system
            )
        }
        .sorted { ($0.category, $0.name) < ($1.category, $1.name) }
    }

    // MARK: - NSUserKeyEquivalents

    private static func readMenuOverrides() -> [SystemShortcut] {
        let raw = CFPreferencesCopyAppValue(
            "NSUserKeyEquivalents" as CFString,
            kCFPreferencesAnyApplication
        ) as? [String: String] ?? [:]

        return raw
            .map { menuItem, keyEquivalent in
                SystemShortcut(
                    id: "menu-\(menuItem)",
                    name: menuItem,
                    category: "Elements de menu",
                    combo: ShortcutFormatter.combo(fromKeyEquivalent: keyEquivalent),
                    isEnabled: true,
                    source: .menuOverride
                )
            }
            .sorted { $0.name < $1.name }
    }
}

/// Reads the shortcut name tables that ship with macOS, so the displayed
/// labels are Apple's own wording rather than a guessed list.
private struct AppleShortcutNames {
    struct Entry {
        let name: String
        let category: String
    }

    private static let keyboardSettings =
        "/System/Library/ExtensionKit/Extensions/KeyboardSettings.appex/Contents/Resources"
    private static let localizePrefix = "DO_NOT_LOCALIZE: "

    private let entries: [Int: Entry]
    private let translations: [String: String]

    init() {
        translations = Self.loadTranslations()
        var found: [Int: Entry] = [:]

        // Grouped table: categories, each with its shortcut elements.
        if let groups = Self.loadPlist("\(Self.keyboardSettings)/en.lproj/DefaultShortcutsTable.xml")
            as? [[String: Any]] {
            for group in groups {
                let category = Self.clean(group["name"] as? String)
                for element in group["elements"] as? [[String: Any]] ?? [] {
                    guard let id = element["sybmolichotkey"] as? Int else { continue }
                    found[id] = Entry(name: Self.clean(element["name"] as? String), category: category)
                }
            }
        }

        // Flat table: one entry per space.
        if let spaces = Self.loadPlist("\(Self.keyboardSettings)/DefaultSpacesShortcuts.xml")
            as? [[String: Any]] {
            for element in spaces {
                guard let id = element["sybmolichotkey"] as? Int else { continue }
                found[id] = Entry(name: Self.clean(element["name"] as? String), category: "Mission Control")
            }
        }

        entries = found
    }

    func entry(for id: Int) -> Entry? {
        guard let entry = entries[id] else { return nil }
        return Entry(
            name: translations[entry.name] ?? entry.name,
            category: translations[entry.category] ?? entry.category
        )
    }

    private static func clean(_ raw: String?) -> String {
        guard let raw else { return "" }
        guard raw.hasPrefix(localizePrefix) else { return raw }
        return String(raw.dropFirst(localizePrefix.count))
    }

    private static func loadPlist(_ path: String) -> Any? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil)
    }

    /// The loctable maps the English names above to the user's language.
    private static func loadTranslations() -> [String: String] {
        guard let table = loadPlist("\(keyboardSettings)/DefaultShortcutsTable.loctable")
            as? [String: [String: String]] else { return [:] }

        for language in Locale.preferredLanguages {
            let code = String(language.prefix(2))
            if let match = table[code] { return match }
        }
        return [:]
    }
}
