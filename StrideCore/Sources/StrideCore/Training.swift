import Foundation

/// Heart-rate zones from heart-rate reserve (Karvonen).
public struct HeartZones: Sendable {
    public let maxHR: Double
    public let restHR: Double
    /// Lower bound of zones 2…5 as a fraction of heart-rate reserve.
    public static let fractions: [Double] = [0.6, 0.7, 0.8, 0.9]
    public static let names = ["Recovery", "Endurance", "Tempo", "Threshold", "Anaerobic"]

    public init(maxHR: Double, restHR: Double) {
        self.maxHR = max(maxHR, restHR + 20)
        self.restHR = restHR
    }

    private func bpm(_ fraction: Double) -> Double { restHR + fraction * (maxHR - restHR) }

    /// 0-based zone index (0…4).
    public func zone(for hr: Double) -> Int {
        Self.fractions.lastIndex { hr >= bpm($0) }.map { $0 + 1 } ?? 0
    }

    public func range(of zone: Int) -> ClosedRange<Double> {
        let lo = zone == 0 ? restHR : bpm(Self.fractions[zone - 1])
        let hi = zone == 4 ? maxHR : bpm(Self.fractions[zone])
        return lo...hi
    }

    public func timeInZones(_ hr: [TimedValue], maxGap: TimeInterval = 300) -> [TimeInterval] {
        var out = [TimeInterval](repeating: 0, count: 5)
        for (a, b) in zip(hr, hr.dropFirst()) {
            out[zone(for: a.v)] += min(max(b.t - a.t, 0), maxGap)
        }
        return out
    }
}

public enum TrainingLoad {
    /// Banister TRIMP — the basis for "Relative Effort".
    public static func trimp(_ hr: [TimedValue], maxHR: Double, restHR: Double, maxGap: TimeInterval = 300) -> Double {
        let reserve = max(maxHR - restHR, 1)
        var total = 0.0
        for (a, b) in zip(hr, hr.dropFirst()) {
            let minutes = min(max(b.t - a.t, 0), maxGap) / 60
            let r = min(max((a.v - restHR) / reserve, 0), 1)
            total += minutes * r * 0.64 * exp(1.92 * r)
        }
        return total
    }

    public struct Day: Identifiable, Hashable, Sendable {
        public let id: Date
        public let load: Double
        public let fitness: Double   // CTL, 42-day
        public let fatigue: Double   // ATL, 7-day
        public var form: Double { fitness - fatigue }   // TSB
    }

    /// Exponentially weighted fitness/fatigue, one entry per calendar day.
    public static func fitness(loads: [Date: Double], through end: Date, calendar: Calendar = .current) -> [Day] {
        let byDay = Dictionary(loads.map { (calendar.startOfDay(for: $0.key), $0.value) }, uniquingKeysWith: +)
        guard let first = byDay.keys.min() else { return [] }
        let kc = 1 - exp(-1.0 / 42), ka = 1 - exp(-1.0 / 7)
        var day = first, ctl = 0.0, atl = 0.0
        let last = calendar.startOfDay(for: end)
        var out: [Day] = []
        while day <= last {
            let l = byDay[day] ?? 0
            ctl += (l - ctl) * kc
            atl += (l - atl) * ka
            out.append(Day(id: day, load: l, fitness: ctl, fatigue: atl))
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return out
    }
}
