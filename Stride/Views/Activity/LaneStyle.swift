import SwiftUI
import StrideCore

/// Presentation rules for each analysis lane.
enum LaneStyle {
    static let order: [LaneKind] = [.pace, .heartRate, .elevation, .cadence, .power]

    static func name(_ k: LaneKind, _ s: Sport) -> String {
        switch k {
        case .pace: s.usesPace ? "Pace" : "Speed"
        case .gap: "Grade-adjusted pace"
        case .heartRate: "Heart Rate"
        case .elevation: "Elevation"
        case .cadence: "Cadence"
        case .power: "Power"
        }
    }

    static func color(_ k: LaneKind, _ s: Sport) -> Color {
        switch k {
        case .pace: s.color
        case .gap: DS.Lane.gap
        case .heartRate: DS.Lane.heartRate
        case .elevation: DS.Lane.elevation
        case .cadence: DS.Lane.cadence
        case .power: DS.Lane.power
        }
    }

    static func reversed(_ k: LaneKind, _ s: Sport) -> Bool { (k == .pace || k == .gap) && s.usesPace }

    static func format(_ k: LaneKind, _ s: Sport, _ y: Double) -> String {
        switch k {
        case .pace, .gap: s.usesPace ? Fmt.minutes(y) + " " + Fmt.paceLabel : String(format: "%.1f %@", y, Fmt.speedLabel)
        case .heartRate: String(format: "%.0f bpm", y)
        case .elevation: String(format: "%.0f %@", y, Fmt.elevationLabel)
        case .cadence: String(format: "%.0f %@", y, Fmt.cadenceUnit(s))
        case .power: String(format: "%.0f W", y)
        }
    }

    static func axisLabel(_ k: LaneKind, _ s: Sport, _ y: Double) -> String {
        reversed(k, s) ? Fmt.minutes(y) : String(format: "%.0f", y)
    }
}

extension Array where Element == DisplayPoint {
    /// Nearest point by x (points are sorted by x).
    func nearest(_ x: Double) -> DisplayPoint? {
        guard !isEmpty else { return nil }
        var lo = 0, hi = count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if self[mid].x < x { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0, abs(self[lo - 1].x - x) < abs(self[lo].x - x) { return self[lo - 1] }
        return self[lo]
    }
}
