import SwiftUI

/// Today's leaves in the popover: who is off, grouped by team.
struct LuccaMenuView: View {
    @ObservedObject var service: LuccaService

    /// Return date, day and month only: the year is never useful here.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()

    var body: some View {
        if !service.isConfigured {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("Lucca non configuré (Options > Congés)")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let error = service.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 2)
                }

                if service.teams.isEmpty {
                    Text(service.lastUpdate == nil ? "Chargement…" : "Personne en congé")
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(service.teams) { team in
                                teamSection(team)
                            }
                        }
                        .padding(.vertical, 2)
                        // Names are meant to be copied out of the popover.
                        .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                }
            }
        }
    }

    private func teamSection(_ team: LuccaTeamLeaves) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(team.department) (\(team.people.count))")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(team.people) { person in
                HStack(spacing: 6) {
                    Text(person.name)
                        .font(.callout)
                        .lineLimit(1)
                    if !person.kind.label.isEmpty {
                        Text(person.kind.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(person.isLastDay ? "dernier jour" : "→ \(Self.dayFormatter.string(from: person.until))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
    }
}
