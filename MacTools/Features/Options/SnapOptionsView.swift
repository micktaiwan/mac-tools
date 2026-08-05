import SwiftUI

struct SnapOptionsView: View {
    @ObservedObject var snapService: SnapService

    /// Paragraphs get an explicit width instead of `fixedSize(vertical:)`.
    ///
    /// `fixedSize` asks the text for its ideal height at the proposed width,
    /// but inside this page the proposed width is unbounded during the sizing
    /// pass, so the text asks for an infinite line and the whole split view
    /// collapses to nothing — sidebar included. A bounded width keeps the
    /// wrapping honest.
    private static let textWidth: CGFloat = 460

    var body: some View {
        OptionsPage(title: "Fenetres") {
            // Always tappable, even without the permission: ticking it is what
            // triggers the system request. A checkbox you cannot tick, next to
            // a permission you have to go and find yourself, is a dead end.
            Toggle("Aligner les fenetres deposees sur un bord", isOn: $snapService.isEnabled)
                .toggleStyle(.checkbox)

            Text("Attrapez une fenetre par sa barre de titre et poussez le curseur contre un bord de l'ecran : un apercu montre la zone visee, la fenetre s'y place quand vous relachez.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: Self.textWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(SnapZone.allCases, id: \.self) { zone in
                    Text("• Bord \(edgeName(for: zone)) : \(zone.label.lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().frame(width: Self.textWidth)

            permissionSection

            Divider().frame(width: Self.textWidth)

            VStack(alignment: .leading, spacing: 4) {
                Text("Sensibilite du bord : \(Int(snapService.edgeThreshold)) px")
                    .font(.caption)
                Slider(value: $snapService.edgeThreshold, in: 2...30, step: 1)
                    .frame(width: 280)
                Text("Distance au bord a laquelle la zone se declenche.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        if snapService.hasPermission {
            Label("Autorisation d'accessibilite accordee", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else if snapService.isEnabled {
            VStack(alignment: .leading, spacing: 6) {
                Label("En attente de l'autorisation d'accessibilite", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("macOS a du afficher une alerte : autorisez MacTools et l'alignement demarre tout seul.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: Self.textWidth, alignment: .leading)
                HStack {
                    Button("Redemander") { snapService.requestPermission() }
                    Button("Ouvrir les Reglages Systeme") { AccessibilityPermission.openSystemSettings() }
                }
            }
        } else {
            Text("Deplacer les fenetres d'autres applications demande l'autorisation d'accessibilite de macOS. Elle vous sera demandee a l'activation.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: Self.textWidth, alignment: .leading)
        }
    }

    private func edgeName(for zone: SnapZone) -> String {
        switch zone {
        case .fullScreen: return "haut"
        case .leftHalf: return "gauche"
        case .rightHalf: return "droit"
        }
    }
}
