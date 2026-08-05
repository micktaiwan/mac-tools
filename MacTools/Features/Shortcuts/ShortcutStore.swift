import Foundation
import SwiftUI

/// Source of truth for Mickael's own shortcuts.
///
/// The JSON file is authoritative and watched: editing it from anywhere (Claude,
/// an editor, the IPC socket) re-registers the hotkeys within a second, no
/// restart. That is what makes "Claude, add this shortcut" work end to end.
@MainActor
final class ShortcutStore: ObservableObject {
    @Published private(set) var shortcuts: [UserShortcut] = []
    @Published private(set) var lastResults: [String: ActionResult] = [:]
    @Published private(set) var registrationErrors: [String: String] = [:]
    @Published private(set) var loadError: String?

    static let directory = FileManager.default
        .homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/MacTools")
    static let configURL = directory.appending(path: "shortcuts.json")
    static let socketURL = directory.appending(path: "ipc.sock")

    private var watchSource: DispatchSourceFileSystemObject?
    private var isSavingLocally = false

    init() {
        createDirectoryIfNeeded()
        HotKeyCenter.shared.setTriggerHandler { [weak self] id in
            self?.trigger(id: id)
        }
        reload()
        startWatching()
    }

    deinit {
        watchSource?.cancel()
    }

    // MARK: - Reading and writing

    func reload() {
        guard FileManager.default.fileExists(atPath: Self.configURL.path) else {
            shortcuts = []
            loadError = nil
            applyRegistrations()
            return
        }

        do {
            let data = try Data(contentsOf: Self.configURL)
            let file = try JSONDecoder().decode(ConfigFile.self, from: data)
            shortcuts = file.shortcuts
            loadError = nil
        } catch {
            // Keep the shortcuts already registered rather than dropping them
            // because of a half-written file.
            loadError = "Config illisible : \(error.localizedDescription)"
        }
        applyRegistrations()
    }

    func save() throws {
        createDirectoryIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(ConfigFile(shortcuts: shortcuts))
        isSavingLocally = true
        try data.write(to: Self.configURL, options: .atomic)
        // The watcher will fire on our own write; ignore that one round trip.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isSavingLocally = false
        }
    }

    // MARK: - Mutations

    func add(_ shortcut: UserShortcut) throws {
        guard !shortcuts.contains(where: { $0.id == shortcut.id }) else {
            throw StoreError.duplicateID(shortcut.id)
        }
        guard KeyCodeResolver.keyCode(for: shortcut.key) != nil else {
            throw StoreError.unknownKey(shortcut.key)
        }
        if let clash = shortcuts.first(where: { $0.combo == shortcut.combo && $0.enabled }) {
            throw StoreError.comboTaken(shortcut.combo, clash.name)
        }
        shortcuts.append(shortcut)
        try save()
        applyRegistrations()
    }

    func remove(id: String) throws {
        guard shortcuts.contains(where: { $0.id == id }) else {
            throw StoreError.notFound(id)
        }
        shortcuts.removeAll { $0.id == id }
        lastResults[id] = nil
        try save()
        applyRegistrations()
    }

    func setEnabled(_ enabled: Bool, id: String) throws {
        guard let index = shortcuts.firstIndex(where: { $0.id == id }) else {
            throw StoreError.notFound(id)
        }
        shortcuts[index].enabled = enabled
        try save()
        applyRegistrations()
    }

    // MARK: - Running

    func trigger(id: String) {
        guard let shortcut = shortcuts.first(where: { $0.id == id }) else { return }
        Task {
            let result = await ActionRunner.run(shortcut.action)
            lastResults[id] = result
        }
    }

    /// Runs the action and waits for it, for the IPC "run" command.
    func run(id: String) async throws -> ActionResult {
        guard let shortcut = shortcuts.first(where: { $0.id == id }) else {
            throw StoreError.notFound(id)
        }
        let result = await ActionRunner.run(shortcut.action)
        lastResults[id] = result
        return result
    }

    // MARK: - Hotkey registration

    private func applyRegistrations() {
        let failures = HotKeyCenter.shared.register(shortcuts)
        registrationErrors = failures.mapValues(\.description)
    }

    // MARK: - File watching

    private func createDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
    }

    private func startWatching() {
        watchSource?.cancel()

        // Watch the directory: atomic writes replace the file, so a descriptor
        // on the file itself would go stale after the first edit.
        let descriptor = open(Self.directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self, !self.isSavingLocally else { return }
            self.reload()
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watchSource = source
    }

    // MARK: - Types

    private struct ConfigFile: Codable {
        var shortcuts: [UserShortcut]
    }

    enum StoreError: LocalizedError {
        case duplicateID(String)
        case unknownKey(String)
        case comboTaken(String, String)
        case notFound(String)

        var errorDescription: String? {
            switch self {
            case .duplicateID(let id): return "un raccourci porte deja l'id \(id)"
            case .unknownKey(let key): return "touche inconnue : \(key)"
            case .comboTaken(let combo, let name): return "\(combo) est deja utilise par \(name)"
            case .notFound(let id): return "aucun raccourci avec l'id \(id)"
            }
        }
    }
}
