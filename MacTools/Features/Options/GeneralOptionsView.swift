import SwiftUI
import ServiceManagement

struct GeneralOptionsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var errorMessage: String?

    var body: some View {
        OptionsPage(title: "General") {
            Toggle("Lancer au demarrage", isOn: Binding(
                get: { launchAtLogin },
                set: { setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            errorMessage = nil
        } catch {
            errorMessage = "Echec : \(error.localizedDescription)"
        }
        // Reflect what the system actually did, not what was asked.
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
