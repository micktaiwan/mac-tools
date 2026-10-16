import SwiftUI

/// The apps that played sound lately. Clicking one brings it to the front.
struct SoundMenuView: View {
    @ObservedObject var service: SoundActivityService

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        if !service.isSupported {
            Text("Nécessite macOS 14.2")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        } else if service.apps.isEmpty {
            Text("Aucun son depuis le lancement")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(service.apps) { app in
                    SoundAppRow(app: app, relative: Self.relative) { service.focus(app) }
                }
            }
        }
    }
}

private struct SoundAppRow: View {
    let app: RecentSoundApp
    let relative: RelativeDateTimeFormatter
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(app.name)
                    .font(.callout)
                    .lineLimit(1)
                Spacer()
                if app.isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("en cours")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Text(relative.localizedString(for: app.lastHeard, relativeTo: Date()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
            .background(isHovered ? Color.primary.opacity(0.08) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var icon: NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
