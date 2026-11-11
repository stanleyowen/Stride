import Foundation

/// Coarse fingerprint of a route for "same route" detection.
public struct RouteSignature: Hashable, Sendable {
    public let startLat, startLon, endLat, endLon: Double
    public let distance: Double
    public let cells: Set<Int64>

    public init?(points: [RoutePoint], distance: Double? = nil) {
        guard let s = points.first, let e = points.last, points.count > 1 else { return nil }
        startLat = s.lat; startLon = s.lon; endLat = e.lat; endLon = e.lon
        self.distance = distance ?? RouteMath.totalDistance(points)
        cells = Set(points.map { Self.cell($0.lat, $0.lon) })
    }

    /// ~55 m grid cell id.
    static func cell(_ lat: Double, _ lon: Double) -> Int64 {
        let a = Int64((lat * 2000).rounded(.down)), b = Int64((lon * 2000).rounded(.down))
        return (a << 32) ^ (b & 0xFFFF_FFFF)
    }

    private static func dilated(_ cells: Set<Int64>) -> Set<Int64> {
        var out = Set<Int64>()
        for c in cells {
            let a = c >> 32, b = Int64(Int32(truncatingIfNeeded: c))
            for da in -1...1 { for db in -1...1 { out.insert(((a + Int64(da)) << 32) ^ ((b + Int64(db)) & 0xFFFF_FFFF)) } }
        }
        return out
    }

    /// Fraction of each route lying near the other (minimum of both directions).
    public func overlap(with other: RouteSignature) -> Double {
        guard !cells.isEmpty, !other.cells.isEmpty else { return 0 }
        let ab = Double(cells.intersection(Self.dilated(other.cells)).count) / Double(cells.count)
        let ba = Double(other.cells.intersection(Self.dilated(cells)).count) / Double(other.cells.count)
        return min(ab, ba)
    }

    public func matches(_ other: RouteSignature) -> Bool {
        guard distance > 0, abs(distance - other.distance) / distance <= 0.1 else { return false }
        guard Geo.distance(startLat, startLon, other.startLat, other.startLon) <= 200,
              Geo.distance(endLat, endLon, other.endLat, other.endLon) <= 200 else { return false }
        return overlap(with: other) >= 0.7
    }
}

public struct SegmentMatch: Hashable, Sendable {
    public let startIndex: Int
    public let endIndex: Int
    public let duration: TimeInterval
}

public enum SegmentMatcher {
    /// Fastest pass through `segment` inside `route`, or nil if the route never covers it.
    public static func match(segment: [RoutePoint], in route: [RoutePoint],
                             endpointTolerance tol: Double = 25, corridor: Double = 40) -> SegmentMatch? {
        guard segment.count > 1, route.count > 1, let s = segment.first, let e = segment.last else { return nil }
        let segDist = RouteMath.totalDistance(segment)
        guard segDist > 0 else { return nil }
        let cum = RouteMath.cumulative(route)
        let checks = stride(from: 0, to: segment.count, by: max(1, segment.count / 20)).map { segment[$0] } + [e]
        let dStart = route.map { Geo.distance($0, s) }

        var best: SegmentMatch?
        var i = 0
        while i < route.count {
            guard dStart[i] <= tol else { i += 1; continue }
            // Closest point within this run of "near start" points.
            var bi = i, j = i
            while j < route.count && dStart[j] <= tol { if dStart[j] < dStart[bi] { bi = j }; j += 1 }

            var k = bi + 1
            var endIdx: Int?
            while k < route.count {
                let along = cum[k] - cum[bi]
                if along > segDist * 1.3 { break }
                if along >= segDist * 0.8, Geo.distance(route[k], e) <= tol {
                    var bk = k, m = k
                    while m < route.count && Geo.distance(route[m], e) <= tol {
                        if Geo.distance(route[m], e) < Geo.distance(route[bk], e) { bk = m }
                        m += 1
                    }
                    endIdx = bk
                    break
                }
                k += 1
            }

            if let f = endIdx, f > bi {
                let slice = route[bi...f]
                let covered = checks.allSatisfy { c in slice.contains { Geo.distance($0, c) <= corridor } }
                let dur = route[f].t - route[bi].t
                if covered, dur > 0, dur < (best?.duration ?? .infinity) {
                    best = SegmentMatch(startIndex: bi, endIndex: f, duration: dur)
                }
            }
            i = j
        }
        return best
    }
}
