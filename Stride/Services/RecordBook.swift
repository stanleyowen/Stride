import Foundation
import SwiftData
import Observation
import StrideCore

struct EffortKey: Hashable {
    let sport: Sport
    let distance: Double
}

/// All best efforts across activities, ranked fastest-first per sport + distance.
struct RecordBook {
    struct Entry: Identifiable {
        let activity: Activity
        let effort: BestEffort
        var id: PersistentIdentifier { activity.persistentModelID }
    }

    private var table: [String: [Entry]] = [:]
    private var prCounts: [PersistentIdentifier: Int] = [:]

    init(_ activities: [Activity]) {
        for a in activities {
            for e in a.efforts { table[Self.key(a.sport, e.distance), default: []].append(Entry(activity: a, effort: e)) }
        }
        for k in table.keys {
            table[k]!.sort { $0.effort.duration < $1.effort.duration }
            if let top = table[k]!.first { prCounts[top.id, default: 0] += 1 }
        }
    }

    private static func key(_ s: Sport, _ d: Double) -> String { "\(s.rawValue)-\(Int(d))" }

    func entries(_ sport: Sport, _ distance: Double) -> [Entry] { table[Self.key(sport, distance)] ?? [] }

    func rank(of activity: Activity, distance: Double) -> Int? {
        entries(activity.sport, distance).firstIndex { $0.id == activity.persistentModelID }.map { $0 + 1 }
    }

    /// Rank among efforts in the same calendar year.
    func yearRank(of activity: Activity, distance: Double) -> Int? {
        let cal = Calendar.current
        return entries(activity.sport, distance)
            .filter { cal.isDate($0.activity.start, equalTo: activity.start, toGranularity: .year) }
            .firstIndex { $0.id == activity.persistentModelID }.map { $0 + 1 }
    }

    func prCount(_ activity: Activity) -> Int { prCounts[activity.persistentModelID] ?? 0 }
}

/// Caches RecordBooks so screens don't rebuild them on every render.
/// Storage is not observed: reading it from a view body must never trigger re-renders.
@MainActor
@Observable
final class RecordStore {
    @ObservationIgnored private var cache: [String: RecordBook] = [:]

    func book(_ activities: [Activity]) -> RecordBook {
        let k = "\(activities.count)-\(activities.reduce(0) { $0 + ($1.effortsData?.count ?? 0) })-\(activities.first?.sportRaw ?? "")-\(activities.last?.sportRaw ?? "")"
        if let hit = cache[k] { return hit }
        if cache.count > 16 { cache.removeAll() }
        let b = RecordBook(activities)
        cache[k] = b
        return b
    }
}
