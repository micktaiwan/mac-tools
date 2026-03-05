import SwiftUI

struct GmailMenuView: View {
    @ObservedObject var service: GmailService
    @State private var hoveredId: String?

    var body: some View {
        if !service.isAvailable {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("gws CLI non disponible")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
        } else if service.unreadMessages.isEmpty {
            Text("Aucun email non lu")
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        } else {
            ForEach(service.unreadMessages) { message in
                messageRow(message)
            }
        }
    }

    private func messageRow(_ message: GmailMessage) -> some View {
        HStack(spacing: 6) {
            Button {
                openInGmail(message)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(message.from)
                            .font(.system(.body, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(formatDate(message.date))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Text(message.subject)
                        .font(.callout)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

            Button {
                withAnimation { service.removeAndTrash(id: message.id) }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .background(hoveredId == message.id ? Color.white.opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onHover { hovering in
            hoveredId = hovering ? message.id : nil
        }
    }

    private func formatDate(_ date: Date) -> String {
        let now = Date()
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 60 { return "\(minutes)min" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        return "\(days)j"
    }

    private func openInGmail(_ message: GmailMessage) {
        if let url = URL(string: "https://mail.google.com/mail/u/0/#inbox/\(message.id)") {
            NSWorkspace.shared.open(url)
        }
    }
}
