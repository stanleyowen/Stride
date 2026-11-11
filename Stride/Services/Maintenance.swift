import Foundation
import SwiftData
import StrideCore

@MainActor
enum Maintenance {
    /// Compute derived metrics for activities from older versions or demo data.
    static func backfill(_ context: ModelContext) {
        let v = DataVersion.derived
        let pending = FetchDescriptor<Activity>(predicate: #Predicate { $0.derivedVersion < v })
        let items = (try? context.fetch(pending)) ?? []
        guard !items.isEmpty else { return }
        let zones = Profile.zones
        items.forEach { $0.recomputeDerived(profile: zones) }
        try? context.save()
    }

    /// Heart-rate profile changed → refresh Relative Effort everywhere.
    static func recomputeLoads(_ context: ModelContext) {
        let zones = Profile.zones
        for a in (try? context.fetch(FetchDescriptor<Activity>())) ?? [] {
            let hr = a.heartRates.map { TimedValue(t: $0.t, v: $0.bpm) }
            if hr.count > 5 {
                a.relativeEffort = TrainingLoad.trimp(hr, maxHR: zones.maxHR, restHR: zones.restHR).rounded()
            } else {
                a.relativeEffort = ((a.activeTime / 60) * (a.rpe.map { Double($0) / 10 * 2.2 } ?? 1.0)).rounded()
            }
        }
        try? context.save()
    }

    // MARK: Segments

    static func matchSegments(for activities: [Activity], in context: ModelContext) {
        guard !activities.isEmpty else { return }
        let segments = (try? context.fetch(FetchDescriptor<Segment>())) ?? []
        for s in segments { match(s, against: activities, context) }
        try? context.save()
    }

    /// Find this segment in every activity of the same sport.
    static func matchAll(_ segment: Segment, in context: ModelContext) {
        let sport = segment.sportRaw
        let acts = (try? context.fetch(FetchDescriptor<Activity>(predicate: #Predicate { $0.sportRaw == sport }))) ?? []
        match(segment, against: acts, context)
        try? context.save()
    }

    private static func match(_ segment: Segment, against activities: [Activity], _ context: ModelContext) {
        let pts = segment.points
        guard pts.count > 1, let first = pts.first else { return }
        for a in activities where a.sportRaw == segment.sportRaw && a.hasRoute {
            guard !a.segmentEfforts.contains(where: { $0.segment?.uid == segment.uid }) else { continue }
            let route = a.route
            // Cheap reject: activity never comes near the segment start.
            guard route.contains(where: { Geo.distance($0, first) < 60 }) else { continue }
            if let m = SegmentMatcher.match(segment: pts, in: route) {
                let e = SegmentEffort(duration: m.duration, startDate: Date(timeIntervalSince1970: route[m.startIndex].t),
                                      startIndex: m.startIndex, endIndex: m.endIndex)
                context.insert(e)
                e.segment = segment
                e.activity = a
            }
        }
    }
}

extension Segment {
    var points: [RoutePoint] {
        DecodeCache.decode([RoutePoint].self, data: pointsData, key: "seg\(uid)") ?? []
    }
    var sport: Sport { Sport(rawValue: sportRaw) ?? .workout }
    var ranked: [SegmentEffort] { efforts.sorted { $0.duration < $1.duration } }
}
