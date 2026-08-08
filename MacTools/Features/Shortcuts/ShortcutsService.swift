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

        let names = AppleShortcutTable()

        let stored = raw.compactMap { key, value -> SystemShortcut? in
            guard let id = Int(key), let entry = value as? [String: Any] else { return nil }

            let isEnabled = (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) == 1)
            let parameters = (entry["value"] as? [String: Any])?["parameters"] as? [Int]
            let parsed = parameters.flatMap { params -> (Set<UserShortcut.Modifier>, String)? in
                guard params.count >= 3 else { return nil }
                return ShortcutFormatter.parse(
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
                modifiers: parsed?.0 ?? [],
                key: parsed?.1 ?? "",
                isEnabled: isEnabled,
                source: .system
            )
        }

        // Anything Apple ships that the preferences never mention is still at
        // its factory binding, and still firing.
        let storedIDs = Set(raw.keys.compactMap(Int.init))
        let untouched = names.ids
            .filter { !storedIDs.contains($0) }
            .compactMap { id -> SystemShortcut? in
                guard let known = names.entry(for: id) else { return nil }
                let parsed = ShortcutFormatter.parse(
                    charCode: known.charCode,
                    keyCode: known.keyCode,
                    modifiers: known.modifiers
                )
                return SystemShortcut(
                    id: "symbolic-\(id)",
                    name: known.name,
                    category: known.category,
                    modifiers: parsed?.modifiers ?? [],
                    key: parsed?.key ?? "",
                    isEnabled: true,
                    source: .system
                )
            }

        return (stored + untouched)
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
                let parsed = ShortcutFormatter.parse(keyEquivalent: keyEquivalent)
                return SystemShortcut(
                    id: "menu-\(menuItem)",
                    name: menuItem,
                    category: "Elements de menu",
                    modifiers: parsed.modifiers,
                    key: parsed.key,
                    isEnabled: true,
                    source: .menuOverride
                )
            }
            .sorted { $0.name < $1.name }
    }
}

/// Reads the shortcut tables that ship with macOS, so both the labels and the
/// factory bindings are Apple's own rather than a guessed list.
///
/// The defaults matter as much as the names: `com.apple.symbolichotkeys` only
/// holds the entries that have been touched at some point, so a shortcut left
/// exactly as it shipped is absent from the preferences while being perfectly
/// active. Reading it here is the only way to inventory those.
struct AppleShortcutTable {
    struct Entry {
        let name: String
        let category: String
        let keyCode: Int
        let charCode: Int
        let modifiers: Int
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
                    found[id] = Self.entry(from: element, category: category)
                }
            }
        }

        // Flat table: one entry per space.
        if let spaces = Self.loadPlist("\(Self.keyboardSettings)/DefaultSpacesShortcuts.xml")
            as? [[String: Any]] {
            for element in spaces {
                guard let id = element["sybmolichotkey"] as? Int else { continue }
                found[id] = Self.entry(from: element, category: "Mission Control")
            }
        }

        entries = found
    }

    var ids: [Int] { Array(entries.keys) }

    func entry(for id: Int) -> Entry? {
        guard let entry = entries[id] else { return nil }
        return Entry(
            name: translations[entry.name] ?? entry.name,
            category: translations[entry.category] ?? entry.category,
            keyCode: entry.keyCode,
            charCode: entry.charCode,
            modifiers: entry.modifiers
        )
    }

    private static func entry(from element: [String: Any], category: String) -> Entry {
        Entry(
            name: clean(element["name"] as? String),
            category: category,
            keyCode: element["key"] as? Int ?? ShortcutFormatter.noValue,
            charCode: element["charKey"] as? Int ?? ShortcutFormatter.noValue,
            modifiers: element["modifier"] as? Int ?? 0
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
