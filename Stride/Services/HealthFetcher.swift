import Foundation
import HealthKit
import StrideCore
import CoreLocation

/// Everything we import for one workout, as plain values (built off the main thread).
struct WorkoutPayload: Sendable {
    var uuid: UUID
    var sport: Sport
    var start: Date
    var duration: TimeInterval
    var distance: Double
    var energy: Double
    var avgHR: Double?
    var maxHR: Double?
    var elevationAscended: Double?
    var route: [RoutePoint]
    var heartRate: [HRPoint]
    var series: [String: [TimedValue]]
    var laps: [TimeRange]
    var pauses: [TimeRange]
    var temperature: Double?
    var humidity: Double?
    var deviceName: String?
    var derived: DerivedMetrics

    var input: AnalysisInput {
        AnalysisInput(points: route, heartRate: heartRate, series: series, start: start.timeIntervalSince1970,
                      duration: duration, laps: laps, pauses: pauses)
    }
}

struct ProfileMetrics: Sendable {
    var restingHR: [TimedValue]
    var vo2Max: [TimedValue]
    var birthYear: Int?
}

/// HealthKit access. Not main-actor isolated, so queries and processing run in the background.
final class HealthFetcher: @unchecked Sendable {
    let store = HKHealthStore()

    var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute(),
                                    HKCharacteristicType(.dateOfBirth)]
        let q: [HKQuantityTypeIdentifier] = [
            .heartRate, .activeEnergyBurned, .distanceWalkingRunning, .distanceCycling, .distanceSwimming,
            .restingHeartRate, .vo2Max, .bodyMass, .stepCount,
            .runningPower, .runningStrideLength, .runningVerticalOscillation, .runningGroundContactTime,
            .cyclingPower, .cyclingCadence,
        ]
        q.forEach { s.insert(HKQuantityType($0)) }
        return s
    }

    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    func workouts() async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(
                sampleType: .workoutType(), predicate: nil, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: (samples as? [HKWorkout]) ?? []) }
            }
            store.execute(query)
        }
    }

    func payload(for w: HKWorkout, zones: HeartZones) async -> WorkoutPayload {
        let sport = Sport(w.workoutActivityType)
        async let routeTask = route(for: w)
        async let hrTask = heartRate(for: w)
        async let seriesTask = extraSeries(for: w, sport: sport)
        let (route, hr, series) = await (routeTask, hrTask, seriesTask)

        let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        let distance = distanceTypes
            .compactMap { w.statistics(for: HKQuantityType($0))?.sumQuantity()?.doubleValue(for: .meter()) }
            .first ?? 0
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hrStats = w.statistics(for: HKQuantityType(.heartRate))
        let (laps, pauses) = events(w)

        var p = WorkoutPayload(
            uuid: w.uuid, sport: sport, start: w.startDate, duration: w.duration, distance: distance,
            energy: w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0,
            avgHR: hrStats?.averageQuantity()?.doubleValue(for: bpm),
            maxHR: hrStats?.maximumQuantity()?.doubleValue(for: bpm),
            elevationAscended: (w.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()),
            route: route, heartRate: hr, series: series, laps: laps, pauses: pauses,
            temperature: (w.metadata?[HKMetadataKeyWeatherTemperature] as? HKQuantity)?.doubleValue(for: .degreeCelsius()),
            humidity: (w.metadata?[HKMetadataKeyWeatherHumidity] as? HKQuantity).map { $0.doubleValue(for: .percent()) * 100 },
            deviceName: w.device?.name ?? w.sourceRevision.source.name,
            derived: DerivedMetrics(efforts: [], movingTime: 0, relativeEffort: 0, elevationGain: 0, distance: 0)
        )
        p.derived = Derive.compute(sport: sport, input: p.input, rpe: nil, zones: zones)
        return p
    }

    // MARK: Events → laps & pauses

    private func events(_ w: HKWorkout) -> ([TimeRange], [TimeRange]) {
        let events = (w.workoutEvents ?? []).sorted { $0.dateInterval.start < $1.dateInterval.start }
        var laps = events.filter { $0.type == .lap }.map {
            TimeRange(start: $0.dateInterval.start.timeIntervalSince1970, end: $0.dateInterval.end.timeIntervalSince1970)
        }
        if laps.isEmpty {
            laps = events.filter { $0.type == .segment }.map {
                TimeRange(start: $0.dateInterval.start.timeIntervalSince1970, end: $0.dateInterval.end.timeIntervalSince1970)
            }
        }
        var pauses: [TimeRange] = []
        var pausedAt: Date?
        for e in events {
            switch e.type {
            case .pause, .motionPaused: if pausedAt == nil { pausedAt = e.dateInterval.start }
            case .resume, .motionResumed:
                if let p = pausedAt {
                    pauses.append(TimeRange(start: p.timeIntervalSince1970, end: e.dateInterval.start.timeIntervalSince1970))
                    pausedAt = nil
                }
            default: break
            }
        }
        if let p = pausedAt { pauses.append(TimeRange(start: p.timeIntervalSince1970, end: w.endDate.timeIntervalSince1970)) }
        return (laps, pauses)
    }

    // MARK: Samples

    private func samples(_ type: HKQuantityType, predicate: NSPredicate) async -> [HKQuantitySample] {
        await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, s, _ in cont.resume(returning: (s as? [HKQuantitySample]) ?? []) }
            store.execute(query)
        }
    }

    private func downsample<T>(_ arr: [T], max: Int = 600) -> [T] {
        let step = Swift.max(1, arr.count / max)
        return step == 1 ? arr : stride(from: 0, to: arr.count, by: step).map { arr[$0] }
    }

    private func heartRate(for w: HKWorkout) async -> [HRPoint] {
        let s = await samples(HKQuantityType(.heartRate),
                              predicate: HKQuery.predicateForSamples(withStart: w.startDate, end: w.endDate))
        let unit = HKUnit.count().unitDivided(by: .minute())
        return downsample(s.map { HRPoint(t: $0.startDate.timeIntervalSince1970, bpm: $0.quantity.doubleValue(for: unit)) })
    }

    private func extraSeries(for w: HKWorkout, sport: Sport) async -> [String: [TimedValue]] {
        let time = HKQuery.predicateForSamples(withStart: w.startDate, end: w.endDate)
        // Only samples from the device that recorded the workout (avoids iPhone + Watch double counting).
        let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [
            time, HKQuery.predicateForObjects(from: w.sourceRevision.source),
        ])
        func fetch(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit) async -> [TimedValue] {
            downsample(await samples(HKQuantityType(id), predicate: pred)
                .map { TimedValue(t: $0.startDate.timeIntervalSince1970, v: $0.quantity.doubleValue(for: unit)) })
        }

        var out: [String: [TimedValue]] = [:]
        switch sport {
        case .run, .walk, .hike:
            let steps = await samples(HKQuantityType(.stepCount), predicate: pred)
            let cadence = steps.compactMap { s -> TimedValue? in
                let minutes = s.endDate.timeIntervalSince(s.startDate) / 60
                guard minutes > 0.05 else { return nil }
                let spm = s.quantity.doubleValue(for: .count()) / minutes
                return spm > 40 && spm < 260 ? TimedValue(t: s.startDate.timeIntervalSince1970, v: spm) : nil
            }
            out[ActivityAnalysis.cadenceKey] = downsample(cadence)
            out[ActivityAnalysis.powerKey] = await fetch(.runningPower, .watt())
            out[ActivityAnalysis.strideKey] = await fetch(.runningStrideLength, .meter())
            out[ActivityAnalysis.verticalOscillationKey] = await fetch(.runningVerticalOscillation, .meterUnit(with: .centi))
            out[ActivityAnalysis.groundContactKey] = await fetch(.runningGroundContactTime, .secondUnit(with: .milli))
        case .ride:
            out[ActivityAnalysis.cadenceKey] = await fetch(.cyclingCadence, .count().unitDivided(by: .minute()))
            out[ActivityAnalysis.powerKey] = await fetch(.cyclingPower, .watt())
        default: break
        }
        return out.filter { $0.value.count > 1 }
    }

    private func route(for w: HKWorkout) async -> [RoutePoint] {
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: w),
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                cont.resume(returning: (s as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(query)
        }
        var points: [RoutePoint] = []
        for r in routes {
            let locations: [CLLocation] = await withCheckedContinuation { cont in
                var all: [CLLocation] = []
                var finished = false
                let q = HKWorkoutRouteQuery(route: r) { _, batch, done, error in
                    if let batch { all += batch }
                    if (done || error != nil) && !finished { finished = true; cont.resume(returning: all) }
                }
                store.execute(q)
            }
            points += locations
                .filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 50 }
                .map { RoutePoint(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude, alt: $0.altitude,
                                  t: $0.timestamp.timeIntervalSince1970) }
        }
        return points.sorted { $0.t < $1.t }
    }

    // MARK: Profile metrics

    func profileMetrics() async -> ProfileMetrics {
        let yearAgo = Calendar.current.date(byAdding: .year, value: -2, to: .now)!
        let pred = HKQuery.predicateForSamples(withStart: yearAgo, end: .now)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let vo2Unit = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
        async let rhr = samples(HKQuantityType(.restingHeartRate), predicate: pred)
        async let vo2 = samples(HKQuantityType(.vo2Max), predicate: pred)
        let birth = try? store.dateOfBirthComponents().year
        return ProfileMetrics(
            restingHR: await rhr.map { TimedValue(t: $0.startDate.timeIntervalSince1970, v: $0.quantity.doubleValue(for: bpm)) },
            vo2Max: await vo2.map { TimedValue(t: $0.startDate.timeIntervalSince1970, v: $0.quantity.doubleValue(for: vo2Unit)) },
            birthYear: birth
        )
    }
}
