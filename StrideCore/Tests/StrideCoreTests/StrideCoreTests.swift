import XCTest
@testable import StrideCore

/// Straight line heading east, `count` points spaced `step` m, speed by index.
private func line(count: Int, step: Double = 10, lat: Double = 25, startLon: Double = 121,
                  alt: (Int) -> Double = { _ in 0 }, speed: (Int) -> Double) -> [RoutePoint] {
    let mPerDeg = 111_195.0 * cos(lat * .pi / 180)
    var pts: [RoutePoint] = []
    var t = 0.0
    for i in 0..<count {
        pts.append(RoutePoint(lat: lat, lon: startLon + Double(i) * step / mPerDeg, alt: alt(i), t: t))
        t += step / speed(i)
    }
    return pts
}

final class RouteMathTests: XCTestCase {
    func testBestEffortsMatchKnownTimes() {
        let pts = line(count: 3001) { $0 < 1500 ? 4 : 2 }       // 15 km @ 4 m/s, then 15 km @ 2 m/s
        let efforts = RouteMath.bestEfforts(pts, targets: [1000, 5000, 20000])
        XCTAssertEqual(efforts[0].duration, 250, accuracy: 1)
        XCTAssertEqual(efforts[1].duration, 1250, accuracy: 3)
        XCTAssertEqual(efforts[2].duration, 15000 / 4 + 5000 / 2, accuracy: 10)
    }

    func testSplits() {
        let pts = line(count: 551) { _ in 4 }                    // 5.5 km
        let a = ActivityAnalysis(points: pts, heartRate: [], start: 0, duration: pts.last!.t)
        let splits = a.splits(unit: 1000, labelScale: 1000)
        XCTAssertEqual(splits.count, 6)
        XCTAssertEqual(splits[0].stats.duration, 250, accuracy: 1)
        XCTAssertTrue(splits[5].isPartial)
        XCTAssertEqual(splits[5].label, "5.5")
    }

    func testElevationHysteresisIgnoresNoise() {
        let noisy = (0..<200).map { Double($0 % 2) }             // ±1 m jitter
        XCTAssertEqual(RouteMath.elevationChange(noisy).gain, 0)
        XCTAssertEqual(RouteMath.elevationChange([0, 10, 5, 20]).gain, 25)
    }
}

final class AnalysisTests: XCTestCase {
    func testMinettiFactor() {
        XCTAssertEqual(ActivityAnalysis.gapFactor(0), 1, accuracy: 1e-9)
        XCTAssertEqual(ActivityAnalysis.gapFactor(0.1), 5.968 / 3.6, accuracy: 0.01)
    }

    func testGAPOnConstantGrade() {
        // 5 % climb at 3 m/s
        let pts = line(count: 400, alt: { Double($0) * 10 * 0.05 }) { _ in 3 }
        let a = ActivityAnalysis(points: pts, heartRate: [], start: 0, duration: pts.last!.t)
        XCTAssertEqual(a.overall.gapSpeed, 3 * ActivityAnalysis.gapFactor(0.05), accuracy: 0.05)
    }

    func testDecouplingAndDrift() {
        let pts = line(count: 1201) { _ in 3 }                    // 4000 s
        let end = pts.last!.t
        let hr = stride(from: 0.0, through: end, by: 10).map { HRPoint(t: $0, bpm: $0 < end / 2 ? 140 : 147) }
        let a = ActivityAnalysis(points: pts, heartRate: hr, start: 0, duration: end)
        XCTAssertEqual(a.decoupling()!, (1 - 140.0 / 147) * 100, accuracy: 0.3)
        XCTAssertEqual(a.hrDrift()!, 5, accuracy: 0.3)
    }

    func testNegativeSplitAndMovingTime() {
        let pts = line(count: 401) { $0 < 200 ? 3 : 4 }
        let a = ActivityAnalysis(points: pts, heartRate: [], start: 0, duration: pts.last!.t)
        let h = a.halves!
        XCTAssertLessThan(h.second, h.first)
        let paused = ActivityAnalysis(points: pts, heartRate: [], start: 0, duration: pts.last!.t,
                                      pauses: [TimeRange(start: 100, end: 160)])
        XCTAssertEqual(paused.movingTime(threshold: 0.5), pts.last!.t - 60, accuracy: 0.01)
    }
}

final class TrainingTests: XCTestCase {
    func testTrimp() {
        // HRR fraction 0.5 for 60 minutes.
        let hr = (0...60).map { TimedValue(t: Double($0) * 60, v: 60 + 0.5 * 130) }
        let v = TrainingLoad.trimp(hr, maxHR: 190, restHR: 60)
        XCTAssertEqual(v, 60 * 0.5 * 0.64 * exp(0.96), accuracy: 0.01)
    }

    func testFitnessConverges() {
        let cal = Calendar(identifier: .gregorian)
        let start = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        var loads: [Date: Double] = [:]
        for d in 0..<300 { loads[cal.date(byAdding: .day, value: d, to: start)!] = 100 }
        let days = TrainingLoad.fitness(loads: loads, through: cal.date(byAdding: .day, value: 299, to: start)!, calendar: cal)
        XCTAssertEqual(days.count, 300)
        XCTAssertEqual(days.last!.fitness, 100, accuracy: 1.5)
        XCTAssertEqual(days.last!.fatigue, 100, accuracy: 0.01)
        XCTAssertEqual(days[0].fatigue, 100 * (1 - exp(-1.0 / 7)), accuracy: 1e-6)
    }

    func testZones() {
        let z = HeartZones(maxHR: 190, restHR: 60)
        XCTAssertEqual(z.zone(for: 100), 0)
        XCTAssertEqual(z.zone(for: 60 + 0.65 * 130), 1)
        XCTAssertEqual(z.zone(for: 185), 4)
    }
}

final class MatchingTests: XCTestCase {
    func testSameRouteDetected() {
        let a = line(count: 500) { _ in 3 }
        let b = line(count: 500, lat: 25.00005) { _ in 3.3 }      // ~5 m offset, different pace
        let c = line(count: 500, lat: 25.01) { _ in 3 }           // 1.1 km away
        let sa = RouteSignature(points: a)!
        XCTAssertTrue(sa.matches(RouteSignature(points: b)!))
        XCTAssertFalse(sa.matches(RouteSignature(points: c)!))
    }

    func testSegmentMatch() {
        let route = line(count: 600) { $0 >= 200 && $0 < 300 ? 5 : 3 }
        let segment = Array(route[200...300])                      // 1 km at 5 m/s
        let m = SegmentMatcher.match(segment: segment, in: route)!
        XCTAssertEqual(m.duration, 200, accuracy: 15)

        let elsewhere = line(count: 600, lat: 25.02) { _ in 3 }
        XCTAssertNil(SegmentMatcher.match(segment: segment, in: elsewhere))
    }
}

final class PredictorTests: XCTestCase {
    func testRiegel() {
        XCTAssertEqual(RacePredictor.riegel(time: 1200, from: 5000, to: 10000), 1200 * pow(2, 1.06), accuracy: 0.001)
        let p = RacePredictor.predict(from: [(5000, 1200), (10000, 2700)], targets: [10000])
        XCTAssertEqual(p[0].time, 1200 * pow(2, 1.06), accuracy: 0.01)   // the 5K is the stronger effort
        XCTAssertEqual(p[0].confidence, .high)
        // A close-in-distance effort beats a faster-predicting but far-away one.
        let m = RacePredictor.predict(from: [(1609, 300), (21097.5, 6000)], targets: [42195])
        XCTAssertEqual(m[0].basedOn, 21097.5)
    }

    func testVDOT() {
        // Daniels' tables: VDOT 50 ≈ 19:57 5K.
        XCTAssertEqual(RacePredictor.vdot(distance: 5000, time: 1197), 50, accuracy: 0.5)
        XCTAssertEqual(RacePredictor.time(forVDOT: 50, distance: 5000), 1197, accuracy: 15)
    }

    func testGPX() {
        let pts = line(count: 3) { _ in 3 }
        let xml = GPX.document(name: "A & B", type: "running", points: pts, heartRate: [HRPoint(t: 0, bpm: 120)])
        XCTAssertTrue(xml.contains("<name>A &amp; B</name>"))
        XCTAssertEqual(xml.components(separatedBy: "<trkpt").count - 1, 3)
        XCTAssertTrue(xml.contains("<gpxtpx:hr>120</gpxtpx:hr>"))
    }
}
