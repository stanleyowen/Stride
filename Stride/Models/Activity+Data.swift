import Foundation
import StrideCore
import CoreLocation

extension RoutePoint {
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// Current versions of fetched / derived data. Bump to trigger a refresh.
enum DataVersion {
    static let health = 2
    static let derived = 2   // 2: reworded feed headlines
}

extension Activity {
    var sport: Sport { Sport(rawValue: sportRaw) ?? .workout }

    var route: [RoutePoint] { DecodeCache.decode([RoutePoint].self, data: routeData, key: "r\(healthID)") ?? [] }
    var heartRates: [HRPoint] { DecodeCache.decode([HRPoint].self, data: hrData, key: "h\(healthID)") ?? [] }
    var efforts: [BestEffort] { DecodeCache.decode([BestEffort].self, data: effortsData, key: "e\(healthID)") ?? [] }
    var series: [String: [TimedValue]] {
        DecodeCache.decode([String: [TimedValue]].self, data: seriesData, key: "s\(healthID)") ?? [:]
    }
    var laps: [TimeRange] { DecodeCache.decode([TimeRange].self, data: lapsData, key: "l\(healthID)") ?? [] }
    var pauses: [TimeRange] { DecodeCache.decode([TimeRange].self, data: pausesData, key: "p\(healthID)") ?? [] }

    var hasRoute: Bool { routeData != nil }

    /// Moving time when known, otherwise elapsed.
    var activeTime: TimeInterval { movingTime > 0 ? movingTime : duration }
    /// Average moving speed in m/s.
    var avgSpeed: Double { activeTime > 0 ? distance / activeTime : 0 }

    var analysisInput: AnalysisInput {
        AnalysisInput(points: route, heartRate: heartRates, series: series, start: start.timeIntervalSince1970,
                      duration: duration, laps: laps, pauses: pauses)
    }

    func apply(_ d: DerivedMetrics) {
        effortsData = try? JSONEncoder().encode(d.efforts)
        movingTime = d.movingTime
        relativeEffort = d.relativeEffort
        avgCadence = d.avgCadence
        avgPower = d.avgPower
        insight = d.insight
        if elevationGain == 0 { elevationGain = d.elevationGain }
        if distance == 0 { distance = d.distance }
        derivedVersion = DataVersion.derived
    }

    func recomputeDerived(profile: HeartZones) {
        apply(Derive.compute(sport: sport, input: analysisInput, rpe: rpe, zones: profile))
    }

    static func autoName(sport: Sport, start: Date) -> String {
        let hour = Calendar.current.component(.hour, from: start)
        let part = switch hour {
        case 5..<12: "Morning"
        case 12..<17: "Afternoon"
        case 17..<21: "Evening"
        default: "Night"
        }
        return "\(part) \(sport.label)"
    }
}

/// Plain, Sendable bundle of an activity's raw data, for off-main analysis.
struct AnalysisInput: Sendable {
    var points: [RoutePoint]
    var heartRate: [HRPoint]
    var series: [String: [TimedValue]]
    var start: TimeInterval
    var duration: TimeInterval
    var laps: [TimeRange]
    var pauses: [TimeRange]

    func analysis() -> ActivityAnalysis {
        ActivityAnalysis(points: points, heartRate: heartRate, series: series, start: start,
                         duration: duration, laps: laps, pauses: pauses)
    }
}

struct DerivedMetrics: Sendable {
    var efforts: [BestEffort]
    var movingTime: TimeInterval
    var relativeEffort: Double
    var avgCadence: Double?
    var avgPower: Double?
    var elevationGain: Double
    var distance: Double
    var insight: String?
}

enum Derive {
    static func compute(sport: Sport, input: AnalysisInput, rpe: Int?, zones: HeartZones) -> DerivedMetrics {
        let a = input.analysis()
        let moving = a.movingTime(threshold: sport.movingThreshold)
        let hr = a.hr
        let load: Double
        if hr.count > 5 {
            load = TrainingLoad.trimp(hr, maxHR: zones.maxHR, restHR: zones.restHR)
        } else {
            // No heart rate: estimate from perceived effort (or a moderate default).
            let minutes = (moving > 0 ? moving : input.duration) / 60
            load = minutes * (rpe.map { Double($0) / 10 * 2.2 } ?? 1.0)
        }
        let overall = a.overall
        return DerivedMetrics(
            efforts: RouteMath.bestEfforts(input.points, targets: sport.effortTargets),
            movingTime: moving,
            relativeEffort: load.rounded(),
            avgCadence: overall.avgCadence,
            avgPower: overall.avgPower,
            elevationGain: overall.elevationGain,
            distance: a.totalDistance,
            insight: headline(a, sport: sport)
        )
    }

    /// One-line takeaway shown on feed cards.
    static func headline(_ a: ActivityAnalysis, sport: Sport) -> String? {
        if let h = a.halves {
            if h.second < h.first * 0.98 { return "Negative split" }
            if h.second > h.first * 1.08 { return "Faded in the second half" }
        }
        if let cv = a.paceVariability(unit: 1000), cv < 0.03 { return "Very even pacing" }
        if let d = a.decoupling(), d < 5 { return "Strong aerobic endurance" }
        return nil
    }
}

// MARK: - Decoding cache (routes are decoded once, not on every render)

private final class Box: NSObject {
    let value: Any
    init(_ value: Any) { self.value = value }
}

enum DecodeCache {
    private static let cache = NSCache<NSString, Box>()

    static func decode<T: Decodable>(_ type: T.Type, data: Data?, key: String) -> T? {
        guard let data else { return nil }
        let k = "\(key)-\(data.count)" as NSString
        if let hit = cache.object(forKey: k)?.value as? T { return hit }
        guard let value = try? JSONDecoder().decode(T.self, from: data) else { return nil }
        cache.setObject(Box(value), forKey: k)
        return value
    }

    static func remember<T>(_ key: String, _ make: () -> T?) -> T? {
        let k = key as NSString
        if let hit = cache.object(forKey: k)?.value as? T { return hit }
        guard let v = make() else { return nil }
        cache.setObject(Box(v), forKey: k)
        return v
    }
}

extension Activity {
    /// Cached "same route" fingerprint.
    var signature: RouteSignature? {
        guard routeData != nil else { return nil }
        return DecodeCache.remember("sig\(healthID)") { RouteSignature(points: route, distance: distance) }
    }

    /// Previous activities of the same sport along (roughly) the same route.
    func similar(in peers: [Activity]) -> [Activity] {
        guard let sig = signature else { return [] }
        return peers.filter { other in
            other.healthID != healthID && other.sportRaw == sportRaw && distance > 0 &&
            abs(other.distance - distance) / distance <= 0.1 &&
            (other.signature.map { sig.matches($0) } ?? false)
        }
    }
}
