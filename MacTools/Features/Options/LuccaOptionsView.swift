import SwiftUI

struct LuccaOptionsView: View {
    @ObservedObject var luccaService: LuccaService

    @State private var instanceURL: String = LuccaCredentials.instanceURL
    @State private var apiKey: String = LuccaCredentials.apiKey
    @State private var saved = false

    /// Explicit width: an options page proposes an unbounded width during
    /// layout, and a paragraph that sizes itself blanks the whole window.
    private let textWidth: CGFloat = 460

    var body: some View {
        OptionsPage(title: "Congés") {
            Text("Congés de l'équipe, lus dans Lucca (module Timmi Absences) et affichés dans le menu.")
                .foregroundStyle(.secondary)
                .frame(width: textWidth, alignment: .leading)

            Text("Connexion")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Instance") {
                    TextField("https://moncompte.ilucca.net", text: $instanceURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
                LabeledContent("Clé API") {
                    SecureField("clé API Lucca", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 320)
                }
            }
            .frame(width: textWidth, alignment: .leading)

            HStack(spacing: 10) {
                Button("Enregistrer et rafraîchir") {
                    LuccaCredentials.instanceURL = instanceURL
                    LuccaCredentials.apiKey = apiKey
                    luccaService.configurationChanged()
                    saved = true
                }
                if saved {
                    Text("Enregistré")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text("La clé est gardée dans le trousseau macOS, jamais dans les préférences. Au premier lancement elle est reprise du fichier ~/projects/perso/lucca/.env s'il existe.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: textWidth, alignment: .leading)

            Divider()

            Text("État")
                .font(.headline)

            Text(statusLine)
                .foregroundStyle(.secondary)
                .frame(width: textWidth, alignment: .leading)

            if let error = luccaService.errorMessage {
                Text(error)
                    .foregroundStyle(.orange)
                    .frame(width: textWidth, alignment: .leading)
            }
        }
    }

    private var statusLine: String {
        guard luccaService.isConfigured else { return "Non configuré." }
        guard let updated = luccaService.lastUpdate else {
            return luccaService.isLoading ? "Chargement…" : "Aucune donnée pour l'instant."
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let count = luccaService.totalPeople
        let people = count == 0 ? "personne en congé" : "\(count) personne(s) en congé"
        return "Mis à jour à \(formatter.string(from: updated)) — \(people)."
    }
}
