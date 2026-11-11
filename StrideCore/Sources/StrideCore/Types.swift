import Foundation

/// One GPS sample. Coding keys are kept stable — they're persisted as JSON.
public struct RoutePoint: Codable, Hashable, Sendable {
    public var lat: Double
    public var lon: Double
    public var alt: Double
    public var t: TimeInterval          // seconds since 1970

    public init(lat: Double, lon: Double, alt: Double, t: TimeInterval) {
        self.lat = lat; self.lon = lon; self.alt = alt; self.t = t
    }
}

public struct HRPoint: Codable, Hashable, Sendable {
    public var t: TimeInterval
    public var bpm: Double
    public init(t: TimeInterval, bpm: Double) { self.t = t; self.bpm = bpm }
}

/// Generic time series sample (cadence, power, stride length…).
public struct TimedValue: Codable, Hashable, Sendable {
    public var t: TimeInterval
    public var v: Double
    public init(t: TimeInterval, v: Double) { self.t = t; self.v = v }
}

public struct TimeRange: Codable, Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var duration: TimeInterval { end - start }
    public init(start: TimeInterval, end: TimeInterval) { self.start = start; self.end = end }
}

/// Fastest stretch of a given distance inside one activity.
public struct BestEffort: Codable, Hashable, Sendable {
    public var distance: Double
    public var duration: TimeInterval
    public var startIndex: Int
    public var endIndex: Int
    public var speed: Double { duration > 0 ? distance / duration : 0 }

    public init(distance: Double, duration: TimeInterval, startIndex: Int, endIndex: Int) {
        self.distance = distance; self.duration = duration; self.startIndex = startIndex; self.endIndex = endIndex
    }
}

public enum Geo {
    /// Haversine distance in meters.
    public static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = p2 - p1, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * 6_371_000 * atan2(sqrt(a), sqrt(1 - a))
    }

    public static func distance(_ a: RoutePoint, _ b: RoutePoint) -> Double {
        distance(a.lat, a.lon, b.lat, b.lon)
    }

    /// Keep at most `max` points (evenly strided, always including the last).
    public static func simplify(_ pts: [RoutePoint], max: Int) -> [RoutePoint] {
        guard pts.count > max, max > 1 else { return pts }
        let step = Double(pts.count - 1) / Double(max - 1)
        return (0..<max).map { pts[Int((Double($0) * step).rounded())] }
    }
}
