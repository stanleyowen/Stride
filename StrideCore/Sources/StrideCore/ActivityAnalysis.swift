import Foundation

public enum XAxis: String, CaseIterable, Sendable, Identifiable {
    case distance, time
    public var id: String { rawValue }
}

public enum LaneKind: String, CaseIterable, Sendable, Identifiable {
    case pace, gap, heartRate, elevation, cadence, power
    public var id: String { rawValue }
}

/// x is raw: meters along the route, or seconds since start.
public struct LanePoint: Identifiable, Hashable, Sendable {
    public let id: Int
    public let x: Double
    public let y: Double
    public let t: TimeInterval
    public let grade: Double
}

public struct RangeStats: Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var distance: Double
    public var gapDistance: Double
    public var avgHR: Double?
    public var maxHR: Double?
    public var elevationGain: Double
    public var elevationLoss: Double
    public var elevationDelta: Double
    public var avgCadence: Double?
    public var avgPower: Double?

    public var duration: TimeInterval { end - start }
    public var speed: Double { duration > 0 ? distance / duration : 0 }
    public var gapSpeed: Double { duration > 0 ? gapDistance / duration : 0 }
}

public struct SplitStats: Identifiable, Hashable, Sendable {
    public let id: Int
    public let label: String
    public let startIndex: Int
    public let endIndex: Int
    public let isPartial: Bool
    public let stats: RangeStats
}

/// Everything the analysis screens need, computed once per activity.
public struct ActivityAnalysis: Sendable {
    public static let cadenceKey = "cadence"
    public static let powerKey = "power"
    public static let strideKey = "stride"
    public static let verticalOscillationKey = "verticalOscillation"
    public static let groundContactKey = "groundContact"

    public let points: [RoutePoint]
    public let cum: [Double]
    public let speed: [Double]       // smoothed m/s per point
    public let grade: [Double]       // fraction per point
    public let gapCum: [Double]      // grade-adjusted cumulative distance
    public let hr: [TimedValue]
    public let series: [String: [TimedValue]]
    public let t0: TimeInterval
    public let tEnd: TimeInterval
    public let laps: [TimeRange]
    public let pauses: [TimeRange]

    public var hasRoute: Bool { points.count > 1 }
    public var totalDistance: Double { cum.last ?? 0 }
    public var elapsed: TimeInterval { tEnd - t0 }

    public init(points: [RoutePoint], heartRate: [HRPoint], series: [String: [TimedValue]] = [:],
                start: TimeInterval, duration: TimeInterval,
                laps: [TimeRange] = [], pauses: [TimeRange] = []) {
        self.points = points
        self.hr = heartRate.map { TimedValue(t: $0.t, v: $0.bpm) }
        self.series = series
        self.laps = laps.sorted { $0.start < $1.start }
        self.pauses = pauses
        let cum = RouteMath.cumulative(points)
        self.cum = cum
        self.t0 = points.count > 1 ? points[0].t : start
        self.tEnd = points.count > 1 ? points[points.count - 1].t : start + duration

        let speed = Self.smoothedSpeed(points, cum)
        let grade = Self.grades(points, cum)
        self.speed = speed
        self.grade = grade
        var gc = [Double](repeating: 0, count: points.count)
        for i in points.indices.dropFirst() {
            gc[i] = gc[i - 1] + (cum[i] - cum[i - 1]) * Self.gapFactor((grade[i - 1] + grade[i]) / 2)
        }
        self.gapCum = gc
    }

    // MARK: Grade-adjusted pace (Minetti et al. 2002)

    /// Energy cost of running (J/kg/m) at a given grade (fraction).
    public static func minettiCost(_ g: Double) -> Double {
        let i = min(max(g, -0.45), 0.45)
        return 155.4 * pow(i, 5) - 30.4 * pow(i, 4) - 43.3 * pow(i, 3) + 46.3 * i * i + 19.5 * i + 3.6
    }

    /// Multiply actual speed by this to get the equivalent flat speed.
    public static func gapFactor(_ g: Double) -> Double { minettiCost(g) / 3.6 }

    private static func smoothedSpeed(_ p: [RoutePoint], _ cum: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: p.count)
        var lo = 0, hi = 0
        for i in p.indices {
            while p[lo].t < p[i].t - 15 { lo += 1 }
            while hi + 1 < p.count && p[hi + 1].t <= p[i].t + 15 { hi += 1 }
            let dt = p[hi].t - p[lo].t
            out[i] = dt > 0 ? (cum[hi] - cum[lo]) / dt : 0
        }
        return out
    }

    /// Grade over a ±25 m window, which smooths GPS altitude noise.
    private static func grades(_ p: [RoutePoint], _ cum: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: p.count)
        var lo = 0, hi = 0
        for i in p.indices {
            while lo < i && cum[i] - cum[lo + 1] >= 25 { lo += 1 }
            if hi < i { hi = i }
            while hi + 1 < p.count && cum[hi] - cum[i] < 25 { hi += 1 }
            let run = cum[hi] - cum[lo]
            out[i] = run > 10 ? min(max((p[hi].alt - p[lo].alt) / run, -0.45), 0.45) : 0
        }
        return out
    }

    // MARK: Lookups

    /// First route index whose time is >= t (clamped).
    public func index(atTime t: TimeInterval) -> Int {
        guard !points.isEmpty else { return 0 }
        var lo = 0, hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if points[mid].t < t { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    private func interpolate(_ arr: [Double], atTime t: TimeInterval) -> Double {
        guard hasRoute else { return 0 }
        let i = index(atTime: t)
        guard i > 0 else { return arr[0] }
        let a = points[i - 1].t, b = points[i].t
        let f = b > a ? min(max((t - a) / (b - a), 0), 1) : 1
        return arr[i - 1] + (arr[i] - arr[i - 1]) * f
    }

    public func distance(atTime t: TimeInterval) -> Double { interpolate(cum, atTime: t) }
    public func gapDistance(atTime t: TimeInterval) -> Double { interpolate(gapCum, atTime: t) }

    public func time(atDistance d: Double) -> TimeInterval {
        guard hasRoute else { return t0 }
        var lo = 0, hi = cum.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cum[mid] < d { lo = mid + 1 } else { hi = mid }
        }
        guard lo > 0 else { return points[0].t }
        let seg = cum[lo] - cum[lo - 1]
        let f = seg > 0 ? min(max((d - cum[lo - 1]) / seg, 0), 1) : 1
        return points[lo - 1].t + (points[lo].t - points[lo - 1].t) * f
    }

    public func effectiveAxis(_ axis: XAxis) -> XAxis { hasRoute ? axis : .time }

    public func x(forTime t: TimeInterval, axis: XAxis) -> Double {
        effectiveAxis(axis) == .distance ? distance(atTime: t) : t - t0
    }

    public func time(forX x: Double, axis: XAxis) -> TimeInterval {
        effectiveAxis(axis) == .distance ? time(atDistance: x) : t0 + x
    }

    // MARK: Range statistics

    private func average(_ s: [TimedValue]?, _ a: TimeInterval, _ b: TimeInterval) -> (avg: Double, max: Double)? {
        guard let s else { return nil }
        let inRange = s.filter { $0.t >= a && $0.t <= b }
        guard !inRange.isEmpty else { return nil }
        return (inRange.reduce(0) { $0 + $1.v } / Double(inRange.count), inRange.map(\.v).max()!)
    }

    public func stats(from t1: TimeInterval, to t2: TimeInterval) -> RangeStats {
        let a = max(min(t1, t2), t0), b = min(max(t1, t2), tEnd)
        var gain = 0.0, loss = 0.0, delta = 0.0
        if hasRoute {
            let ia = index(atTime: a), ib = max(ia, index(atTime: b))
            let alts = points[ia...ib].map(\.alt)
            (gain, loss) = RouteMath.elevationChange(alts)
            delta = (alts.last ?? 0) - (alts.first ?? 0)
        }
        let h = average(hr, a, b)
        return RangeStats(
            start: a, end: b,
            distance: hasRoute ? distance(atTime: b) - distance(atTime: a) : 0,
            gapDistance: hasRoute ? gapDistance(atTime: b) - gapDistance(atTime: a) : 0,
            avgHR: h?.avg, maxHR: h?.max,
            elevationGain: gain, elevationLoss: loss, elevationDelta: delta,
            avgCadence: average(series[Self.cadenceKey], a, b)?.avg,
            avgPower: average(series[Self.powerKey], a, b)?.avg
        )
    }

    public var overall: RangeStats { stats(from: t0, to: tEnd) }

    // MARK: Splits & laps

    /// Splits every `unit` meters; `labelScale` is meters per label unit (1000 for km, 1609.34 for mi).
    public func splits(unit: Double, labelScale: Double) -> [SplitStats] {
        guard hasRoute, unit > 0 else { return [] }
        var out: [SplitStats] = []
        var prevT = t0, prevIdx = 0, mark = unit
        while mark <= totalDistance {
            let t = time(atDistance: mark)
            let idx = index(atTime: t)
            out.append(SplitStats(id: out.count + 1, label: String(format: "%g", (mark / labelScale * 10).rounded() / 10),
                                  startIndex: prevIdx, endIndex: idx, isPartial: false, stats: stats(from: prevT, to: t)))
            prevT = t; prevIdx = idx; mark += unit
        }
        let rest = totalDistance - (mark - unit)
        if rest > unit * 0.1 {
            out.append(SplitStats(id: out.count + 1, label: String(format: "%.1f", totalDistance / labelScale),
                                  startIndex: prevIdx, endIndex: points.count - 1, isPartial: true, stats: stats(from: prevT, to: tEnd)))
        }
        return out
    }

    public func lapStats() -> [SplitStats] {
        guard laps.count > 1 else { return [] }
        return laps.enumerated().map { i, lap in
            SplitStats(id: i + 1, label: "\(i + 1)", startIndex: index(atTime: lap.start), endIndex: index(atTime: lap.end),
                       isPartial: false, stats: stats(from: lap.start, to: lap.end))
        }
    }

    // MARK: Lanes

    public func lane(_ kind: LaneKind, axis: XAxis, maxPoints: Int = 500) -> [LanePoint] {
        let useDistance = effectiveAxis(axis) == .distance
        func routeLane(_ y: (Int) -> Double) -> [LanePoint] {
            guard hasRoute else { return [] }
            let step = max(1, points.count / maxPoints)
            return stride(from: 0, to: points.count, by: step).map { i in
                LanePoint(id: i, x: useDistance ? cum[i] : points[i].t - t0, y: y(i), t: points[i].t, grade: grade[i])
            }
        }
        func seriesLane(_ s: [TimedValue]?) -> [LanePoint] {
            guard let s, s.count > 1 else { return [] }
            let inRange = useDistance ? s.filter { $0.t >= t0 && $0.t <= tEnd } : s
            let step = max(1, inRange.count / maxPoints)
            return stride(from: 0, to: inRange.count, by: step).map { i in
                let p = inRange[i]
                return LanePoint(id: i, x: useDistance ? distance(atTime: p.t) : p.t - t0, y: p.v, t: p.t, grade: 0)
            }
        }
        switch kind {
        case .pace: return routeLane { speed[$0] }
        case .gap: return routeLane { speed[$0] * Self.gapFactor(grade[$0]) }
        case .elevation:
            let alts = points.map(\.alt)
            guard let lo = alts.min(), let hi = alts.max(), hi - lo >= 1 else { return [] }
            return routeLane { points[$0].alt }
        case .heartRate: return seriesLane(hr)
        case .cadence: return seriesLane(series[Self.cadenceKey])
        case .power: return seriesLane(series[Self.powerKey])
        }
    }

    // MARK: Insights

    /// Time for the first and second half by distance.
    public var halves: (first: TimeInterval, second: TimeInterval)? {
        guard hasRoute, totalDistance >= 2000 else { return nil }
        let mid = time(atDistance: totalDistance / 2)
        return (mid - t0, tEnd - mid)
    }

    /// Pa:HR decoupling in percent (first vs second half by time). < 5 % = good aerobic endurance.
    public func decoupling() -> Double? {
        guard hasRoute, hr.count >= 10, elapsed >= 1200 else { return nil }
        let mid = (t0 + tEnd) / 2
        let a = stats(from: t0, to: mid), b = stats(from: mid, to: tEnd)
        guard let h1 = a.avgHR, let h2 = b.avgHR, h1 > 0, h2 > 0, a.speed > 0, b.speed > 0 else { return nil }
        let r1 = a.speed / h1, r2 = b.speed / h2
        return (r1 - r2) / r1 * 100
    }

    /// Change in average HR, second half vs first, in percent.
    public func hrDrift() -> Double? {
        guard hr.count >= 10, elapsed >= 600 else { return nil }
        let mid = (t0 + tEnd) / 2
        guard let h1 = stats(from: t0, to: mid).avgHR, let h2 = stats(from: mid, to: tEnd).avgHR, h1 > 0 else { return nil }
        return (h2 - h1) / h1 * 100
    }

    /// Coefficient of variation of full split speeds (lower = more even pacing).
    public func paceVariability(unit: Double) -> Double? {
        let speeds = splits(unit: unit, labelScale: unit).filter { !$0.isPartial }.map(\.stats.speed)
        guard speeds.count >= 3 else { return nil }
        let mean = speeds.reduce(0, +) / Double(speeds.count)
        guard mean > 0 else { return nil }
        let variance = speeds.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(speeds.count)
        return sqrt(variance) / mean
    }

    /// Moving time from pause events, or (without them) from GPS speed above `threshold` m/s.
    public func movingTime(threshold: Double) -> TimeInterval {
        if !pauses.isEmpty {
            let paused = pauses.reduce(0) { $0 + max(0, min($1.end, tEnd) - max($1.start, t0)) }
            return max(0, elapsed - paused)
        }
        guard hasRoute else { return elapsed }
        var moving = 0.0
        for i in 1..<points.count {
            let dt = points[i].t - points[i - 1].t
            guard dt > 0 else { continue }
            if (cum[i] - cum[i - 1]) / dt >= threshold { moving += dt }
        }
        return min(moving, elapsed)
    }
}
