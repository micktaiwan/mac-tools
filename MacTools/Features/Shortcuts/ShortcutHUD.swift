import AppKit
import SwiftUI

/// What to show for the modifiers currently held.
struct HUDContent: Equatable {
    struct Entry: Equatable, Identifiable {
        let id: String
        /// Modifiers still to add, empty when the key alone fires it.
        let remaining: String
        let key: String
        let name: String
    }

    /// A block of rows sharing a title, so the panel can be read in columns.
    struct Section: Equatable, Identifiable {
        let id: String
        let title: String
        let entries: [Entry]
    }

    let held: String
    let sections: [Section]

    var isEmpty: Bool { sections.allSatisfy(\.entries.isEmpty) }

    /// Everything reachable from the modifiers currently held: Mickael's own
    /// shortcuts first, then what macOS and other apps have taken.
    static func make(
        held: Set<UserShortcut.Modifier>,
        mine: [UserShortcut],
        system: [SystemShortcut]
    ) -> HUDContent {
        let mineEntries = mine
            .filter(\.enabled)
            .compactMap { shortcut in
                entry(
                    id: shortcut.id,
                    modifiers: Set(shortcut.modifiers),
                    key: KeyCodeResolver.displayName(for: shortcut.key),
                    name: shortcut.name,
                    held: held
                )
            }

        let systemEntries = system
            .filter(\.isEnabled)
            .compactMap { shortcut in
                entry(
                    id: shortcut.id,
                    modifiers: shortcut.modifiers,
                    key: shortcut.key,
                    name: shortcut.name,
                    held: held
                )
            }

        return HUDContent(
            held: ShortcutFormatter.symbols(for: held),
            sections: [
                Section(id: "mine", title: "Mes raccourcis", entries: sorted(mineEntries)),
                Section(id: "system", title: "Systeme", entries: sorted(systemEntries)),
            ].filter { !$0.entries.isEmpty }
        )
    }

    private static func entry(
        id: String,
        modifiers: Set<UserShortcut.Modifier>,
        key: String,
        name: String,
        held: Set<UserShortcut.Modifier>
    ) -> Entry? {
        guard !key.isEmpty, held.isSubset(of: modifiers) else { return nil }
        return Entry(
            id: id,
            remaining: ShortcutFormatter.symbols(for: modifiers.subtracting(held)),
            key: key,
            name: name
        )
    }

    /// Directly reachable first, then by the modifiers left to add.
    private static func sorted(_ entries: [Entry]) -> [Entry] {
        entries.sorted {
            if $0.remaining.isEmpty != $1.remaining.isEmpty { return $0.remaining.isEmpty }
            if $0.remaining != $1.remaining { return $0.remaining < $1.remaining }
            return $0.key < $1.key
        }
    }
}

/// The floating panel listing what the held modifiers can reach.
///
/// It must never take focus: the user is mid-gesture in another app, and a
/// window becoming key there would break whatever they were doing. Hence a
/// non-activating panel ordered front without ever being made key.
@MainActor
final class ShortcutHUD {
    private let panel: NSPanel
    private let model = HUDModel()
    private var isShown = false

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0

        let hosting = NSHostingView(rootView: ShortcutHUDView(model: model))
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
    }

    func show(_ content: HUDContent) {
        guard !content.isEmpty else {
            hide()
            return
        }

        model.content = content
        panel.layoutIfNeeded()
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 400, height: 200))
        position()

        guard !isShown else { return }
        isShown = true
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        }
    }

    /// Centred low on the active screen: out of the way of what is being read,
    /// and always in the same place so the eye learns where to look.
    private func position() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let x = max(visible.minX + 20, visible.midX - size.width / 2)
        let y = max(visible.minY + 20, visible.minY + (visible.height - size.height) / 4)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

@MainActor
private final class HUDModel: ObservableObject {
    @Published var content = HUDContent(held: "", sections: [])
}

private struct ShortcutHUDView: View {
    @ObservedObject var model: HUDModel

    /// Rows per column before spilling into the next one. The system list runs
    /// to a few dozen entries, a single column would be taller than the screen.
    private let rowsPerColumn = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(model.content.held) + …")
                .font(.system(.title3, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 28) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(column) { row in
                            switch row.kind {
                            case .title(let title):
                                Text(title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                            case .entry(let entry):
                                entryRow(entry)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func entryRow(_ entry: HUDContent.Entry) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                if !entry.remaining.isEmpty {
                    Text(entry.remaining)
                        .foregroundStyle(.secondary)
                }
                Text(entry.key)
            }
            .font(.system(.body, design: .monospaced))
            .frame(minWidth: 62, alignment: .leading)

            Text(entry.name)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Column flow

    private struct Row: Identifiable {
        enum Kind {
            case title(String)
            case entry(HUDContent.Entry)
        }
        let id: String
        let kind: Kind
    }

    private var columns: [[Row]] {
        var rows: [Row] = []
        for section in model.content.sections {
            rows.append(Row(id: "title-\(section.id)", kind: .title(section.title)))
            rows.append(contentsOf: section.entries.map { Row(id: $0.id, kind: .entry($0)) })
        }
        return stride(from: 0, to: rows.count, by: rowsPerColumn).map {
            Array(rows[$0..<min($0 + rowsPerColumn, rows.count)])
        }
    }
}
