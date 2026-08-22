import SwiftUI

/// The glance: what the phone is doing, in the few lines that fit under a menu bar icon.
///
/// Deliberately read-only and deliberately short. Anything that needs a curve, a history or a
/// comparison belongs in a window that stays open, not in a popover that closes the moment
/// Mickael clicks somewhere else.
struct PhoneMenuView: View {
    @ObservedObject var service: PhoneStatsService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if service.isStale {
                silence
            } else if let stats = service.latest {
                if !stats.warnings.isEmpty { warnings(stats) }
                processor(stats)
                Divider()
                conditions(stats)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
    }

    private var header: some View {
        HStack {
            Image(systemName: "iphone")
                .foregroundStyle(.secondary)
            Text("Téléphone")
                .font(.headline)
            Spacer()
            if let stats = service.latest {
                Text(age(stats.receivedAt))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// What silence looks like. Named as silence rather than dressed up as an error, because the
    /// ordinary causes are a phone in a pocket with no signal and a Mac that was asleep.
    private var silence: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pas de nouvelles")
                .font(.subheadline)
            Text("Le téléphone n'a rien envoyé récemment. Il est peut-être hors de portée, ou kited est arrêté.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func warnings(_ stats: PhoneStats) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(stats.warnings, id: \.self) { warning in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(warning)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func processor(_ stats: PhoneStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let load = stats.cpuLoad {
                HStack {
                    Text("Processeur")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int((load * 100).rounded())) %")
                        .font(.subheadline.monospacedDigit())
                }
                ProgressView(value: min(load, 1))
                    .progressViewStyle(.linear)
            }
            // The clusters, named by position rather than by anything the phone said: it reports
            // core counts and top frequencies, and deciding which of them is "the big one" is
            // this side's job.
            ForEach(Array(stats.clusters.enumerated()), id: \.offset) { index, cluster in
                HStack {
                    Text(clusterName(index: index, of: stats.clusters.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let khz = cluster.averageKhz {
                        Text("\(khz / 1000) MHz")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    Text("\(Int((cluster.busy * 100).rounded())) %")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
        }
    }

    private func conditions(_ stats: PhoneStats) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let memory = stats.memory {
                row("Mémoire libre", "\(memory.availableKb / 1024) Mo")
                if memory.swapTotalKb > 0 {
                    row("Swap libre", "\(memory.swapFreeKb / 1024) Mo sur \(memory.swapTotalKb / 1024 / 1024) Go")
                }
            }
            if let thermal = stats.thermal {
                if let headroom = thermal.headroom {
                    row("Marge thermique", "\(Int(((1 - headroom) * 100).rounded())) %")
                }
                if let status = thermal.status {
                    row("Bridage", status == 0 ? "aucun" : "niveau \(status)")
                }
            }
            if let summary = batterySummary(stats.battery) {
                row("Batterie", summary)
            }
            // Awake time, not time since boot: the phone measures it with a clock that stops
            // during deep sleep, so a phone up for a month reports rather less than a month.
            if let uptime = stats.uptime {
                row("Éveillé depuis", "\(Int(uptime / 86400)) j")
            }
        }
    }

    /// Built outside the view builder: assembling a list of parts is ordinary code, and a `var`
    /// in the middle of a `VStack` is not something `@ViewBuilder` accepts.
    private func batterySummary(_ battery: PhoneStats.Battery?) -> String? {
        guard let battery else { return nil }
        var parts: [String] = []
        if let level = battery.level { parts.append("\(level) %") }
        if let celsius = battery.celsius { parts.append(String(format: "%.1f °C", celsius)) }
        if battery.charging == true { parts.append("en charge") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    private func clusterName(index: Int, of count: Int) -> String {
        if count == 3 {
            return ["Petits cœurs", "Cœurs moyens", "Grand cœur"][index]
        }
        if count == 2 {
            return ["Petits cœurs", "Grands cœurs"][index]
        }
        return "Cœurs \(index + 1)"
    }

    private func age(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "il y a \(max(seconds, 0)) s" }
        return "il y a \(seconds / 60) min"
    }
}
