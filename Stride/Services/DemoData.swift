import Foundation
import SwiftData
import StrideCore

/// Synthetic activities so every feature can be tried without Apple Health data.
/// Includes hills, laps, a pause, cadence/power and repeated routes (for route comparison & segments).
@MainActor
enum DemoData {
    private struct Spec { let sport: Sport; let km: Double; let speed: Double; let route: Int; let hills: Double }

    static func insert(into context: ModelContext) {
        let specs: [Spec] = [
            .init(sport: .run, km: 5.1, speed: 3.05, route: 0, hills: 12), .init(sport: .ride, km: 32, speed: 7.6, route: 1, hills: 40),
            .init(sport: .run, km: 10.2, speed: 2.9, route: 2, hills: 20), .init(sport: .walk, km: 3.4, speed: 1.4, route: 3, hills: 6),
            .init(sport: .run, km: 5.1, speed: 3.15, route: 0, hills: 12), .init(sport: .hike, km: 8.2, speed: 1.15, route: 4, hills: 120),
            .init(sport: .run, km: 7.6, speed: 3.1, route: 5, hills: 25), .init(sport: .ride, km: 32, speed: 7.9, route: 1, hills: 40),
            .init(sport: .run, km: 5.1, speed: 3.25, route: 0, hills: 12), .init(sport: .run, km: 21.2, speed: 2.8, route: 6, hills: 30),
            .init(sport: .run, km: 6.2, speed: 3.2, route: 7, hills: 15), .init(sport: .ride, km: 48, speed: 7.8, route: 8, hills: 60),
            .init(sport: .run, km: 5.1, speed: 3.35, route: 0, hills: 12), .init(sport: .run, km: 10.2, speed: 3.0, route: 2, hills: 20),
            .init(sport: .walk, km: 4.0, speed: 1.5, route: 9, hills: 8), .init(sport: .run, km: 3.2, speed: 3.6, route: 10, hills: 5),
        ]
        let zones = Profile.zones
        let gear = (try? context.fetch(FetchDescriptor<Gear>())) ?? []
        var made: [Activity] = []

        for (i, s) in specs.enumerated() {
            let start = Calendar.current.date(byAdding: .day, value: -i * 3 - 1, to: .now)!
                .addingTimeInterval(Double(-3600 * (i % 5)))
            let g = generate(s, start: start.timeIntervalSince1970, seed: Double(i), pause: i % 4 == 1)
            let a = Activity(healthID: UUID(), sportRaw: s.sport.rawValue, name: Activity.autoName(sport: s.sport, start: start),
                             start: start, duration: g.route.last!.t - g.route.first!.t,
                             distance: RouteMath.totalDistance(g.route), energy: s.km * (s.sport == .ride ? 28 : 62),
                             elevationGain: RouteMath.elevationGain(g.route))
            a.routeData = try? JSONEncoder().encode(g.route)
            a.hrData = try? JSONEncoder().encode(g.hr)
            a.seriesData = try? JSONEncoder().encode(g.series)
            a.lapsData = g.laps.isEmpty ? nil : try? JSONEncoder().encode(g.laps)
            a.pausesData = g.pauses.isEmpty ? nil : try? JSONEncoder().encode(g.pauses)
            a.avgHR = g.hr.map(\.bpm).reduce(0, +) / Double(g.hr.count)
            a.maxHR = g.hr.map(\.bpm).max()
            a.temperature = 18 + Double(i % 7) * 2
            a.humidity = 55 + Double(i % 5) * 6
            a.deviceName = "Apple Watch (demo)"
            a.rpe = [4, 6, 7, 3, 5, 8, 6][i % 7]
            a.gear = gear.first { !$0.retired && $0.defaultSportRaw == a.sportRaw }
            a.recomputeDerived(profile: zones)
            a.dataVersion = DataVersion.health
            context.insert(a)
            made.append(a)
        }
        try? context.save()
        Maintenance.matchSegments(for: made, in: context)
    }

    private struct Generated {
        var route: [RoutePoint] = [], hr: [HRPoint] = [], series: [String: [TimedValue]] = [:]
        var laps: [TimeRange] = [], pauses: [TimeRange] = []
    }

    private static func generate(_ s: Spec, start: TimeInterval, seed: Double, pause: Bool) -> Generated {
        let n = max(400, Int(s.km * 100))
        let radius = s.km * 1000 / (2 * .pi)
        let r = Double(s.route)
        let center = (lat: 25.0136 + (r.truncatingRemainder(dividingBy: 4)) * 0.012,
                      lon: 121.5410 + (r / 4).rounded(.down) * 0.012)
        let mLat = 111_000.0, mLon = 111_000.0 * cos(center.lat * .pi / 180)
        var g = Generated()
        var t = start
        var cadence: [TimedValue] = [], power: [TimedValue] = []
        var lapStart = start, nextLap = 1000.0, dist = 0.0
        let pauseAt = n / 2

        for i in 0...n {
            let a = Double(i) / Double(n) * 2 * .pi
            let wobble = 1 + 0.15 * sin(a * 3 + r)
            let alt = 20 + s.hills * (0.5 + 0.5 * sin(a * 2 + r)) + 3 * sin(a * 9)
            let p = RoutePoint(lat: center.lat + radius * wobble * sin(a) / mLat,
                               lon: center.lon + radius * wobble * cos(a) / mLon, alt: alt, t: t)
            if let prev = g.route.last {
                let d = Geo.distance(prev, p)
                let grade = d > 0 ? (alt - prev.alt) / d : 0
                // Faster on the flat, slower uphill, slight negative split, small per-run variation.
                let fatigue = 1 + 0.04 * (Double(i) / Double(n) - 0.5)
                let v = s.speed * (1 - min(max(grade, -0.1), 0.15) * 3) * fatigue * (1 + 0.05 * sin(a * 11 + seed))
                t += d / max(v, 0.4)
                dist += d
            }
            if pause && i == pauseAt {
                let ps = t
                g.route.append(RoutePoint(lat: p.lat, lon: p.lon, alt: p.alt, t: t))
                t += 75
                g.pauses.append(TimeRange(start: ps, end: t))
            }
            g.route.append(RoutePoint(lat: p.lat, lon: p.lon, alt: p.alt, t: t))

            if s.sport == .run && dist >= nextLap {
                g.laps.append(TimeRange(start: lapStart, end: t))
                lapStart = t; nextLap += 1000
            }
            if i % 4 == 0 {
                let f = Double(i) / Double(n)
                let base = s.sport == .ride ? 128.0 : 125
                g.hr.append(HRPoint(t: t, bpm: base + 45 * min(1, f * 5) + 10 * f + 6 * sin(a * 5 + seed)))
                switch s.sport {
                case .run:
                    cadence.append(TimedValue(t: t, v: 168 + 6 * sin(a * 7) + s.speed * 2))
                    power.append(TimedValue(t: t, v: 240 + 25 * sin(a * 2 + r) + 10 * sin(a * 13)))
                case .ride:
                    cadence.append(TimedValue(t: t, v: 86 + 5 * sin(a * 6)))
                    power.append(TimedValue(t: t, v: 190 + 50 * sin(a * 2 + r) + 20 * sin(a * 17)))
                case .walk, .hike:
                    cadence.append(TimedValue(t: t, v: 108 + 6 * sin(a * 5)))
                default: break
                }
            }
        }
        if s.sport == .run, let last = g.route.last, last.t - lapStart > 30 {
            g.laps.append(TimeRange(start: lapStart, end: last.t))
        }
        if !cadence.isEmpty { g.series[ActivityAnalysis.cadenceKey] = cadence }
        if !power.isEmpty { g.series[ActivityAnalysis.powerKey] = power }
        return g
    }
}
