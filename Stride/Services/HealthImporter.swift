import Foundation
import HealthKit
import SwiftData
import Observation
import StrideCore

/// UI-facing import state. Heavy work happens in `HealthFetcher` off the main thread.
@MainActor
@Observable
final class HealthImporter {
    private let fetcher = HealthFetcher()
    private var observing = false

    var isImporting = false
    var progress = 0.0
    var status = ""
    var errorMessage: String?
    var lastImportCount = 0

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    static var wasAuthorized: Bool { UserDefaults.standard.bool(forKey: Keys.healthAuthorized) }

    func importNew(into context: ModelContext, quiet: Bool = false) async {
        guard !isImporting else { return }
        guard Self.isAvailable else {
            errorMessage = "Health data isn't available on this device. Try Load demo data in the You tab."
            return
        }
        isImporting = true
        errorMessage = nil
        progress = 0
        defer { isImporting = false }

        do {
            if !quiet { status = "Requesting access…" }
            try await fetcher.requestAuthorization()
            UserDefaults.standard.set(true, forKey: Keys.healthAuthorized)
            startObserving(context.container)

            await refreshProfile()

            if !quiet { status = "Finding workouts…" }
            let workouts = try await fetcher.workouts()
            let existing = Dictionary(((try? context.fetch(FetchDescriptor<Activity>())) ?? []).map { ($0.healthID, $0) },
                                      uniquingKeysWith: { a, _ in a })
            let fresh = workouts.filter { existing[$0.uuid] == nil }
            let stale = workouts.compactMap { w in existing[w.uuid].flatMap { $0.dataVersion < DataVersion.health ? (w, $0) : nil } }
            let total = fresh.count + stale.count

            guard total > 0 else {
                if !quiet { status = "Up to date — \(existing.count) activities." }
                return
            }

            let zones = Profile.zones
            let gear = (try? context.fetch(FetchDescriptor<Gear>())) ?? []
            var inserted: [Activity] = []
            var done = 0

            for w in fresh {
                status = "Importing \(done + 1) of \(total)…"
                let p = await fetcher.payload(for: w, zones: zones)
                let a = makeActivity(p)
                a.gear = gear.first { !$0.retired && $0.defaultSportRaw == a.sportRaw }
                context.insert(a)
                inserted.append(a)
                done += 1
                progress = Double(done) / Double(total)
                if done % 20 == 0 { try context.save() }
            }
            for (w, a) in stale {
                status = "Updating \(done + 1) of \(total)…"
                let p = await fetcher.payload(for: w, zones: zones)
                enrich(a, with: p)
                done += 1
                progress = Double(done) / Double(total)
            }
            try context.save()

            Maintenance.matchSegments(for: inserted, in: context)
            lastImportCount = fresh.count
            status = fresh.isEmpty ? "Updated \(stale.count) activities with new detail."
                                   : "Imported \(fresh.count) new workout\(fresh.count == 1 ? "" : "s")."
        } catch {
            errorMessage = error.localizedDescription
            status = ""
        }
    }

    private func makeActivity(_ p: WorkoutPayload) -> Activity {
        let a = Activity(healthID: p.uuid, sportRaw: p.sport.rawValue, name: Activity.autoName(sport: p.sport, start: p.start),
                         start: p.start, duration: p.duration, distance: p.distance, energy: p.energy,
                         elevationGain: p.elevationAscended ?? 0)
        a.avgHR = p.avgHR
        a.maxHR = p.maxHR
        a.routeData = p.route.isEmpty ? nil : try? JSONEncoder().encode(p.route)
        a.hrData = p.heartRate.isEmpty ? nil : try? JSONEncoder().encode(p.heartRate)
        enrich(a, with: p)
        return a
    }

    private func enrich(_ a: Activity, with p: WorkoutPayload) {
        a.seriesData = p.series.isEmpty ? nil : try? JSONEncoder().encode(p.series)
        a.lapsData = p.laps.isEmpty ? nil : try? JSONEncoder().encode(p.laps)
        a.pausesData = p.pauses.isEmpty ? nil : try? JSONEncoder().encode(p.pauses)
        a.temperature = p.temperature
        a.humidity = p.humidity
        a.deviceName = p.deviceName
        if a.hrData == nil, !p.heartRate.isEmpty { a.hrData = try? JSONEncoder().encode(p.heartRate) }
        if let e = p.elevationAscended { a.elevationGain = e }
        a.apply(p.derived)
        if a.rpe != nil { a.recomputeDerived(profile: Profile.zones) }
        a.dataVersion = DataVersion.health
    }

    /// Pull resting HR / VO₂max / birth year. Fills profile values the user hasn't set.
    func refreshProfile() async {
        let m = await fetcher.profileMetrics()
        if !m.restingHR.isEmpty { HealthHistory.restingHR = m.restingHR }
        if !m.vo2Max.isEmpty { HealthHistory.vo2Max = m.vo2Max }
        let d = UserDefaults.standard
        if d.integer(forKey: Keys.birthYear) == 0, let y = m.birthYear { d.set(y, forKey: Keys.birthYear) }
        if d.double(forKey: Keys.restHR) == 0 {
            let recent = m.restingHR.suffix(30).map(\.v)
            if !recent.isEmpty { d.set((recent.reduce(0, +) / Double(recent.count)).rounded(), forKey: Keys.restHR) }
        }
    }

    /// New workouts appear automatically (also while the app is in the background).
    func startObserving(_ container: ModelContainer) {
        guard !observing, Self.wasAuthorized,
              UserDefaults.standard.object(forKey: Keys.autoImport) as? Bool ?? true else { return }
        observing = true
        let query = HKObserverQuery(sampleType: .workoutType(), predicate: nil) { [weak self] _, completion, error in
            guard error == nil else { completion(); return }
            Task { @MainActor in
                await self?.importNew(into: container.mainContext, quiet: true)
                completion()
            }
        }
        fetcher.store.execute(query)
        fetcher.store.enableBackgroundDelivery(for: .workoutType(), frequency: .immediate) { _, _ in }
    }
}
