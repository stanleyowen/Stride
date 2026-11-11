import Foundation

/// All user-facing number formatting, unit-aware (metric / imperial).
enum Fmt {
    static var imperial: Bool { Profile.imperial }

    // Distance
    static var distanceUnit: Double { imperial ? 1609.344 : 1000 }
    static var distanceLabel: String { imperial ? "mi" : "km" }
    static func distanceValue(_ m: Double) -> Double { m / distanceUnit }
    static func distance(_ m: Double, digits: Int? = nil) -> String {
        let v = distanceValue(m)
        let d = digits ?? (v >= 100 ? 0 : 2)
        return String(format: "%.\(d)f \(distanceLabel)", v)
    }
    static func distanceNumber(_ m: Double) -> String {
        let v = distanceValue(m)
        return String(format: v >= 100 ? "%.0f" : "%.2f", v)
    }

    // Elevation
    static var elevationLabel: String { imperial ? "ft" : "m" }
    static func elevationValue(_ m: Double) -> Double { imperial ? m * 3.28084 : m }
    static func elevation(_ m: Double) -> String { String(format: "%.0f \(elevationLabel)", elevationValue(m)) }

    // Time
    static func duration(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        let (h, m, sec) = (s / 3600, (s % 3600) / 60, s % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
    static func hoursMinutes(_ t: TimeInterval) -> String {
        // "min" rather than "m", which reads as meters next to distances.
        let m = Int((t / 60).rounded())
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }
    /// 1 → "1st", 2 → "2nd", 11 → "11th".
    static func ordinal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
    /// m:ss from a number of minutes.
    static func minutes(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        let sec = Int((value * 60).rounded())
        return String(format: "%d:%02d", sec / 60, sec % 60)
    }

    // Pace & speed
    static var paceLabel: String { "/\(distanceLabel)" }
    static var speedLabel: String { imperial ? "mph" : "km/h" }
    /// Minutes per distance unit.
    static func paceValue(_ ms: Double) -> Double { ms > 0.1 ? distanceUnit / ms / 60 : .infinity }
    static func speedValue(_ ms: Double) -> Double { ms * 3600 / distanceUnit }
    static func pace(_ ms: Double) -> String { ms > 0.1 ? minutes(paceValue(ms)) + " " + paceLabel : "–" }
    static func speed(_ ms: Double) -> String { String(format: "%.1f %@", speedValue(ms), speedLabel) }
    static func speedOrPace(_ ms: Double, sport: Sport) -> String { sport.usesPace ? pace(ms) : speed(ms) }
    /// Value without the unit (for compact tables).
    static func speedOrPaceNumber(_ ms: Double, sport: Sport) -> String {
        sport.usesPace ? (ms > 0.1 ? minutes(paceValue(ms)) : "–") : String(format: "%.1f", speedValue(ms))
    }
    static func speedOrPaceUnit(_ sport: Sport) -> String { sport.usesPace ? paceLabel : speedLabel }
    static func paceCap(_ sport: Sport) -> Double { sport.paceCapMinPerKm * distanceUnit / 1000 }

    // Other
    static func bpm(_ v: Double?) -> String { v.map { String(format: "%.0f bpm", $0) } ?? "–" }
    static func kcal(_ v: Double) -> String { v > 0 ? String(format: "%.0f kcal", v) : "–" }
    static func temperature(_ c: Double) -> String {
        imperial ? String(format: "%.0f°F", c * 9 / 5 + 32) : String(format: "%.0f°C", c)
    }
    static func percentChange(_ now: Double, _ before: Double) -> String? {
        guard before > 0 else { return nil }
        let p = (now - before) / before * 100
        return String(format: "%@%.0f%%", p >= 0 ? "+" : "", p)
    }
    static func signedSeconds(_ s: TimeInterval) -> String {
        (s < 0 ? "−" : "+") + duration(abs(s))
    }
    static func cadenceUnit(_ sport: Sport) -> String { sport == .ride ? "rpm" : "spm" }
}
