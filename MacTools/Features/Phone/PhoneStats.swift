import Foundation

/// One measurement of what Mickael's phone is doing, as the phone itself reported it.
///
/// Every field here was measured on the phone and arrived through `kited`. Nothing in this file
/// computes a load or a temperature, because nothing on this Mac can: the counters behind these
/// numbers are refused to anything but the phone, and the phone owns the subtraction that turns
/// them into rates. What this side does is name them and decide what to show.
///
/// Every field is optional and none is required to build a sample. The phone sends what its
/// hardware exposes, an older build sends less than a newer one, and a screen that refused to
/// render because one sensor was missing would be a screen that goes blank on the day a sensor
/// starts failing — which is the day it matters most.
struct PhoneStats {
    /// When `kited` received it. The phone's own clock never enters into this: staleness is
    /// measured against the Mac's clock, so two clocks that disagree cannot fake freshness.
    let receivedAt: Date

    /// Share of the phone's total processing capacity in use, from 0 to 1.
    ///
    /// Weighted by the phone, across clusters and by the frequency actually held. On a
    /// big.LITTLE chip a plain average of the cores would be meaningless: four small cores flat
    /// out and one big core flat out are nothing like the same amount of machine.
    let cpuLoad: Double?

    let clusters: [Cluster]
    let memory: Memory?
    let thermal: Thermal?
    let battery: Battery?

    /// How long the phone had been awake, excluding deep sleep.
    let uptime: TimeInterval?

    struct Cluster {
        let cores: Int
        let maxKhz: Int
        let averageKhz: Int?
        let currentKhz: Int?
        /// Share of the window these cores were not idle, from 0 to 1.
        let busy: Double
    }

    struct Memory {
        let totalKb: Int
        let availableKb: Int
        let swapTotalKb: Int
        let swapFreeKb: Int

        var availableShare: Double { totalKb > 0 ? Double(availableKb) / Double(totalKb) : 1 }
        var swapFreeShare: Double { swapTotalKb > 0 ? Double(swapFreeKb) / Double(swapTotalKb) : 1 }
    }

    struct Thermal {
        /// Android's throttling level: 0 is none, and anything above means the platform is
        /// already holding the phone back.
        let status: Int?
        /// How close to throttling, from 0 to 1. Absent on hardware that does not implement it.
        let headroom: Double?
    }

    struct Battery {
        let level: Int?
        let celsius: Double?
        let charging: Bool?
    }
}

// MARK: - What counts as a problem

extension PhoneStats {
    /// The reasons this phone is not in a normal state, in the words that go on screen.
    ///
    /// This drives the menu bar icon, and the ordering is deliberate: heat first because it is
    /// the one actively costing performance, memory second because it is the one that creeps up
    /// over weeks of uptime and never announces itself. The CPU load is not in here on purpose —
    /// a phone working hard is a phone doing its job, and an alert that fires whenever something
    /// runs is an alert nobody reads.
    var warnings: [String] {
        var found: [String] = []
        // Two, not one. Android calls level 1 "light throttling where UX is not impacted", and it
        // says so literally: this phone sits at 1 the whole time it is on a charger. Warning on
        // it meant the icon was orange most of the day, which trains the eye to ignore it. Level
        // 2 is "moderate", the first one worth a glance.
        if let status = thermal?.status, status >= 2 {
            found.append("le téléphone est bridé par la chaleur")
        }
        if let headroom = thermal?.headroom, headroom >= 0.9 {
            found.append("il est au bord du bridage thermique")
        }
        // No warning on how full the swap is, and that is a correction rather than an omission.
        // This phone's swap is zram: compressed pages held in RAM, which Android fills on purpose
        // to keep more applications warm. Measured on 21/08/2026, it went from 2.7 GB free to
        // 80 MB free within half an hour of a reboot while the phone was doing nothing wrong, so
        // a warning on the fill level would be lit almost permanently.
        //
        // What actually distinguished a sick phone from a healthy one that evening was the rate
        // of reading back out of it: 206 pages a second while the load sat at 20%, against 6 a
        // second afterwards at 5%. That rate lives in /proc/vmstat, which is refused to an app,
        // so this side cannot see it. Better a missing warning than one that cries wolf.
        if let memory, memory.availableShare < 0.10 {
            found.append("il ne reste presque plus de mémoire")
        }
        return found
    }
}

// MARK: - Decoding

extension PhoneStats {
    /// Reads one line of `kited`'s store.
    ///
    /// Hand-written rather than `Codable` because the store is deliberately schemaless at the
    /// daemon: the phone adds a field and the daemon carries it without being taught, so the
    /// only place that has to know a field's name is the one that displays it. A `Codable`
    /// struct here would put a second schema in the way of that.
    static func decode(line: Data) -> PhoneStats? {
        guard
            let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let at = root["at"] as? Double,
            let sample = root["sample"] as? [String: Any]
        else { return nil }

        let clusters = (sample["clusters"] as? [[String: Any]] ?? []).compactMap { raw -> Cluster? in
            guard
                let busy = raw["busy"] as? Double,
                let maxKhz = raw["max_khz"] as? Int
            else { return nil }
            let cores = (raw["cpus"] as? [Int])?.count ?? 1
            return Cluster(
                cores: cores,
                maxKhz: maxKhz,
                averageKhz: raw["avg_khz"] as? Int,
                currentKhz: raw["cur_khz"] as? Int,
                busy: busy
            )
        }
        // Coldest first, so a caller can name them by position without the phone having decided
        // which one is "the big one".
        .sorted { $0.maxKhz < $1.maxKhz }

        var memory: Memory?
        if let raw = sample["mem"] as? [String: Any],
           let total = raw["total_kb"] as? Int,
           let available = raw["available_kb"] as? Int {
            memory = Memory(
                totalKb: total,
                availableKb: available,
                swapTotalKb: raw["swap_total_kb"] as? Int ?? 0,
                swapFreeKb: raw["swap_free_kb"] as? Int ?? 0
            )
        }

        var thermal: Thermal?
        if let raw = sample["thermal"] as? [String: Any] {
            thermal = Thermal(status: raw["status"] as? Int, headroom: raw["headroom"] as? Double)
        }

        var battery: Battery?
        if let raw = sample["battery"] as? [String: Any] {
            battery = Battery(
                level: raw["level"] as? Int,
                celsius: raw["temp_c"] as? Double,
                charging: raw["charging"] as? Bool
            )
        }

        let uptimeMs = sample["uptime_ms"] as? Double

        return PhoneStats(
            receivedAt: Date(timeIntervalSince1970: at / 1000),
            cpuLoad: sample["cpu_load"] as? Double,
            clusters: clusters,
            memory: memory,
            thermal: thermal,
            battery: battery,
            uptime: uptimeMs.map { $0 / 1000 }
        )
    }
}
