import Foundation

public enum RacePredictor {
    public enum Confidence: String, Sendable { case high = "High", medium = "Medium", low = "Low" }

    public struct Prediction: Identifiable, Hashable, Sendable {
        public var id: Double { distance }
        public let distance: Double
        public let time: TimeInterval
        public let confidence: Confidence
        public let basedOn: Double      // source effort distance
    }

    /// Riegel: T2 = T1 × (D2 / D1)^1.06
    public static func riegel(time: TimeInterval, from d1: Double, to d2: Double, exponent: Double = 1.06) -> TimeInterval {
        time * pow(d2 / d1, exponent)
    }

    /// For each target, uses the strongest recent effort (lowest predicted time) among efforts
    /// reasonably close in distance (≤ 2.5×); falls back to all efforts when none are close.
    public static func predict(from efforts: [(distance: Double, duration: TimeInterval)], targets: [Double]) -> [Prediction] {
        let usable = efforts.filter { $0.distance >= 1500 && $0.duration > 0 }
        return targets.compactMap { target in
            let all = usable.map { (time: riegel(time: $0.duration, from: $0.distance, to: target), source: $0.distance) }
            let near = all.filter { max(target / $0.source, $0.source / target) <= 2.5 }
            guard let best = (near.isEmpty ? all : near).min(by: { $0.time < $1.time }) else { return nil }
            let ratio = max(target / best.source, best.source / target)
            let conf: Confidence = ratio <= 2.5 ? .high : ratio <= 6 ? .medium : .low
            return Prediction(distance: target, time: best.time, confidence: conf, basedOn: best.source)
        }
    }

    // MARK: Daniels VDOT

    /// Oxygen cost (ml/kg/min) at velocity v (m/min).
    public static func oxygenCost(velocity v: Double) -> Double { -4.60 + 0.182258 * v + 0.000104 * v * v }

    /// Fraction of VO₂max sustainable for t minutes.
    public static func sustainableFraction(minutes t: Double) -> Double {
        0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
    }

    public static func vdot(distance: Double, time: TimeInterval) -> Double {
        let t = time / 60
        return oxygenCost(velocity: distance / t) / sustainableFraction(minutes: t)
    }

    /// Race time for a given VO₂max / VDOT, by bisection.
    public static func time(forVDOT target: Double, distance: Double) -> TimeInterval {
        var lo = 60.0, hi = 60.0 * 60 * 12
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if vdot(distance: distance, time: mid) > target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }
}

public enum GPX {
    public static func document(name: String, type: String, points: [RoutePoint], heartRate: [HRPoint]) -> String {
        let iso = ISO8601DateFormatter()
        var hrIndex = 0
        func hr(at t: TimeInterval) -> Double? {
            guard !heartRate.isEmpty else { return nil }
            while hrIndex + 1 < heartRate.count && heartRate[hrIndex + 1].t <= t { hrIndex += 1 }
            return abs(heartRate[hrIndex].t - t) < 60 ? heartRate[hrIndex].bpm : nil
        }
        let escaped = name.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Stride" xmlns="http://www.topografix.com/GPX/1/1" \
        xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
        <trk><name>\(escaped)</name><type>\(type)</type><trkseg>

        """
        for p in points {
            out += "<trkpt lat=\"\(p.lat)\" lon=\"\(p.lon)\"><ele>\(String(format: "%.1f", p.alt))</ele>"
            out += "<time>\(iso.string(from: Date(timeIntervalSince1970: p.t)))</time>"
            if let h = hr(at: p.t) {
                out += "<extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>\(Int(h))</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>"
            }
            out += "</trkpt>\n"
        }
        out += "</trkseg></trk></gpx>\n"
        return out
    }
}
