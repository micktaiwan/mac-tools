import AppKit

/// What the phone shows in the menu bar: the processor load, then the battery.
///
/// **Why the processor is there at all.** Not because it is the most useful thing to know about a
/// phone — it is not, and the warnings under it matter far more — but because a number that moves
/// is its own proof of life. A health dot sitting on green looks identical whether the phone is
/// fine or whether nothing has arrived since Tuesday. A percentage that changes every twenty
/// seconds cannot fake that.
///
/// **Why the battery is next to it.** It is the one figure worth reading rather than glancing at,
/// and the phone is often not in reach when the answer matters. It carries its own glyph because
/// two bare percentages side by side would be a puzzle: which one is which has to be obvious
/// without remembering an order.
///
/// So the load proves the chain is alive, the battery is the thing actually worth knowing, and
/// the icon says whether something is wrong.
enum PhoneMenuBarLabel {

    /// What the phone means to the eye: normal, worth a look, or not talking.
    enum State {
        case normal
        case warning
        case stale
    }

    static func state(for stats: PhoneStats?, isStale: Bool) -> State {
        guard !isStale, let stats else { return .stale }
        return stats.warnings.isEmpty ? .normal : .warning
    }

    static func symbolName(for state: State) -> String {
        switch state {
        case .stale: return "iphone.slash"
        case .warning, .normal: return "iphone"
        }
    }

    /// The icon, tinted orange when something is wrong.
    ///
    /// The warning lives here rather than on the figure beside it, and that separation is the
    /// whole point: the figure means processor load and nothing else, so colouring it for a hot
    /// phone made the colour contradict the number it was painted on. A reader saw an alarming
    /// 6% and had no way to learn that the alarm was about heat.
    static func symbolImage(for state: State) -> NSImage? {
        let name = symbolName(for: state)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: "Téléphone") else {
            return nil
        }
        guard state == .warning else {
            image.isTemplate = true
            return image
        }
        // A palette colour only survives on a non-template image; a template one is repainted by
        // the menu bar to match the rest of it, which is exactly what we want the other cases to
        // do and exactly what would erase this.
        let tinted = image.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
        )
        tinted?.isTemplate = false
        return tinted ?? image
    }

    /// The processor share, or a dash when there is nothing recent.
    ///
    /// Never the last figure that arrived. Leaving a stale percentage up is worse than showing
    /// nothing: it reads as a live measurement and no glyph says it stopped.
    static func title(for stats: PhoneStats?, isStale: Bool) -> String {
        guard !isStale, let load = stats?.cpuLoad else { return "—" }
        return "\(Int((load * 100).rounded())) %"
    }

    /// The whole label, load and battery together.
    ///
    /// The two halves are coloured independently, because they mean unrelated things: a hot phone
    /// and a flat phone are different problems and either can happen without the other.
    static func attributedTitle(for stats: PhoneStats?, isStale: Bool) -> NSAttributedString {
        let font = NSFont.menuBarFont(ofSize: 0)
        let composed = NSMutableAttributedString()

        let load = title(for: stats, isStale: isStale)
        composed.append(NSAttributedString(
            string: load,
            attributes: [.font: font, .foregroundColor: loadColor(for: stats, isStale: isStale)]
        ))

        // Dropped entirely when stale rather than shown as a dash of its own: one dash already
        // says the phone is not talking, and two would suggest two separate failures.
        if !isStale, let battery = stats?.battery, let level = battery.level {
            composed.append(NSAttributedString(string: "  ", attributes: [.font: font]))
            let colour = batteryColor(level: level, charging: battery.charging == true)
            if let glyph = batteryGlyph(level: level, charging: battery.charging == true, font: font, colour: colour) {
                composed.append(glyph)
                composed.append(NSAttributedString(string: " ", attributes: [.font: font]))
            }
            composed.append(NSAttributedString(
                string: "\(level) %",
                attributes: [.font: font, .foregroundColor: colour]
            ))
        }

        return composed
    }

    // MARK: - Colours

    /// The load's colour comes from the load, and from nothing else.
    ///
    /// Green is not decoration: a phone doing almost nothing should read as such at a glance,
    /// without anyone having to know what a normal figure looks like. The thresholds are wide on
    /// purpose, because a phone briefly at 60% is a phone opening an app, not a problem.
    private static func loadColor(for stats: PhoneStats?, isStale: Bool) -> NSColor {
        guard !isStale, let load = stats?.cpuLoad else { return .tertiaryLabelColor }
        switch load {
        case ..<0.5: return .systemGreen
        case ..<0.85: return .systemOrange
        default: return .systemRed
        }
    }

    /// Charging is never a warning, however low the level: a phone at 4% on a charger is a phone
    /// being dealt with, and colouring it red would train the eye to ignore the colour.
    private static func batteryColor(level: Int, charging: Bool) -> NSColor {
        if charging { return .labelColor }
        if level <= 10 { return .systemRed }
        if level <= 20 { return .systemOrange }
        return .labelColor
    }

    // MARK: - The glyph

    /// The battery symbol at the nearest quarter, with a bolt when it is charging.
    ///
    /// The five-step names are the ones that have existed since SF Symbols 1, not the `percent`
    /// spellings that arrived later: the app deploys back to macOS 13 and a symbol that fails to
    /// resolve renders as nothing at all rather than as an error anyone would notice. The caller
    /// falls back to a bare percentage if this returns nil, so a missing glyph costs clarity and
    /// never the reading itself.
    private static func batteryGlyph(level: Int, charging: Bool, font: NSFont, colour: NSColor) -> NSAttributedString? {
        let name = charging ? "battery.100.bolt" : bucket(level: level)
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: "batterie")?
            .withSymbolConfiguration(configuration) else { return nil }
        image.isTemplate = true

        let attachment = NSTextAttachment()
        attachment.image = image
        // Centred on the cap height so it sits with the digits instead of hanging off the line's
        // bottom, which is where an attachment lands by default.
        let size = image.size
        attachment.bounds = CGRect(
            x: 0,
            y: (font.capHeight - size.height) / 2,
            width: size.width,
            height: size.height
        )

        let glyph = NSMutableAttributedString(attachment: attachment)
        glyph.addAttribute(.foregroundColor, value: colour, range: NSRange(location: 0, length: glyph.length))
        return glyph
    }

    private static func bucket(level: Int) -> String {
        switch level {
        case ...12: return "battery.0"
        case ...37: return "battery.25"
        case ...62: return "battery.50"
        case ...87: return "battery.75"
        default: return "battery.100"
        }
    }
}
