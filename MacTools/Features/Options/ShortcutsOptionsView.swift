import SwiftUI

struct ShortcutsOptionsView: View {
    @ObservedObject var shortcutsService: ShortcutsService
    @ObservedObject var store: ShortcutStore

    var body: some View {
        OptionsPage(title: "Raccourcis et scripts") {
            MyShortcutsSection(store: store)
            Divider()
            SystemShortcutsSection(shortcutsService: shortcutsService)
        }
    }
}

/// Mickael's own shortcuts: what fires, what it runs, and what happened last time.
private struct MyShortcutsSection: View {
    @ObservedObject var store: ShortcutStore

    var body: some View {
        Text("Mes raccourcis")
            .font(.headline)

        if let loadError = store.loadError {
            Text(loadError)
                .font(.caption)
                .foregroundStyle(.red)
        }

        if store.shortcuts.isEmpty {
            Text("Aucun raccourci. Demande a Claude d'en ajouter un.")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(store.shortcuts) { shortcut in
                    row(shortcut)
                }
            }
        }

        Text("Config : \(ShortcutStore.configURL.path)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    private func row(_ shortcut: UserShortcut) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(shortcut.combo)
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.name)
                Text(shortcut.action.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                status(shortcut)
            }

            Spacer()

            Button("Tester") { store.trigger(id: shortcut.id) }
            Button {
                try? store.remove(id: shortcut.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func status(_ shortcut: UserShortcut) -> some View {
        if let error = store.registrationErrors[shortcut.id] {
            Text("Non enregistre : \(error)")
                .font(.caption)
                .foregroundStyle(.red)
        } else if !shortcut.enabled {
            Text("Desactive")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let result = store.lastResults[shortcut.id] {
            Text(summary(of: result))
                .font(.caption)
                .foregroundStyle(result.succeeded ? Color.secondary : Color.red)
                .lineLimit(2)
        }
    }

    private func summary(of result: ActionResult) -> String {
        let time = timeFormatter.string(from: result.date)
        if result.succeeded {
            return "Derniere execution \(time), OK"
        }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Derniere execution \(time), code \(result.exitCode) : \(output)"
    }
}

/// Read-only inventory of what macOS and other apps already reserve.
private struct SystemShortcutsSection: View {
    @ObservedObject var shortcutsService: ShortcutsService
    @State private var showDisabled = false
    @State private var search = ""

    var body: some View {
        HStack {
            Text("Deja pris sur le Mac")
                .font(.headline)
            Text("\(shortcutsService.enabledCount) actifs sur \(shortcutsService.shortcuts.count)")
                .foregroundStyle(.secondary)
            Spacer()
            Toggle("Afficher les desactives", isOn: $showDisabled)
                .toggleStyle(.checkbox)
            Button("Actualiser") { shortcutsService.reload() }
        }

        TextField("Rechercher", text: $search)
            .textFieldStyle(.roundedBorder)

        if visibleGroups.isEmpty {
            Text("Aucun raccourci trouve")
                .foregroundStyle(.secondary)
        } else {
            List {
                ForEach(visibleGroups, id: \.category) { group in
                    Section(group.category) {
                        ForEach(group.shortcuts) { shortcut in
                            HStack {
                                Text(shortcut.name)
                                Spacer()
                                Text(shortcut.combo)
                                    .font(.system(.body, design: .monospaced))
                                if !shortcut.isEnabled {
                                    Text("desactive")
                                        .font(.caption)
                                }
                            }
                            .foregroundStyle(shortcut.isEnabled ? .primary : .secondary)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private struct Group {
        let category: String
        let shortcuts: [SystemShortcut]
    }

    private var visibleGroups: [Group] {
        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = shortcutsService.shortcuts.filter { shortcut in
            guard showDisabled || shortcut.isEnabled else { return false }
            guard !needle.isEmpty else { return true }
            return shortcut.name.lowercased().contains(needle)
                || shortcut.combo.lowercased().contains(needle)
                || shortcut.category.lowercased().contains(needle)
        }

        return Dictionary(grouping: filtered, by: \.category)
            .map { Group(category: $0.key, shortcuts: $0.value) }
            .sorted { $0.category < $1.category }
    }
}
