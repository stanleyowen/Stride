import Foundation

public enum RouteMath {
    /// Cumulative distance per point, ignoring GPS jumps (> 40 m/s).
    public static func cumulative(_ pts: [RoutePoint]) -> [Double] {
        guard !pts.isEmpty else { return [] }
        var cum = [0.0]
        cum.reserveCapacity(pts.count)
        for i in 1..<pts.count {
            var d = Geo.distance(pts[i - 1], pts[i])
            let dt = pts[i].t - pts[i - 1].t
            if dt <= 0 || d / dt > 40 { d = 0 }
            cum.append(cum[i - 1] + d)
        }
        return cum
    }

    public static func totalDistance(_ pts: [RoutePoint]) -> Double { cumulative(pts).last ?? 0 }

    /// Elevation gain/loss with a 3 m hysteresis so GPS noise doesn't inflate it.
    public static func elevationChange<C: Collection>(_ alts: C) -> (gain: Double, loss: Double) where C.Element == Double {
        guard var ref = alts.first else { return (0, 0) }
        var gain = 0.0, loss = 0.0
        for a in alts {
            if a - ref >= 3 { gain += a - ref; ref = a }
            else if ref - a >= 3 { loss += ref - a; ref = a }
        }
        return (gain, loss)
    }

    public static func elevationGain(_ pts: [RoutePoint]) -> Double { elevationChange(pts.map(\.alt)).gain }

    /// Sliding window: fastest time to cover each target distance. O(n) per target.
    public static func bestEfforts(_ pts: [RoutePoint], targets: [Double]) -> [BestEffort] {
        guard pts.count > 1 else { return [] }
        let cum = cumulative(pts)
        let total = cum[cum.count - 1]
        var out: [BestEffort] = []

        for target in targets where target <= total {
            var best: BestEffort?
            var i = 0
            for j in 1..<pts.count where cum[j] >= target {
                while i + 1 < j && cum[j] - cum[i + 1] >= target { i += 1 }
                let startDist = cum[j] - target
                let seg = cum[i + 1] - cum[i]
                let frac = seg > 0 ? (startDist - cum[i]) / seg : 0
                let tStart = pts[i].t + (pts[i + 1].t - pts[i].t) * frac
                let dur = pts[j].t - tStart
                if dur > 0, dur < (best?.duration ?? .infinity) {
                    best = BestEffort(distance: target, duration: dur, startIndex: i, endIndex: j)
                }
            }
            if let best { out.append(best) }
        }
        return out
    }
}
