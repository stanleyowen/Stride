import SwiftUI
import Observation
import CoreLocation
import StrideCore

enum DetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview", analysis = "Analysis", splits = "Splits", efforts = "Efforts"
    var id: String { rawValue }
}

/// A chart-ready point in display units.
struct DisplayPoint: Identifiable, Hashable {
    let id: Int
    let x: Double
    let y: Double
    let t: TimeInterval
}

struct Insight: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let tint: Color
}

/// Shared state for the activity screen: analysis results + cross-tab selection (scrub, range, highlight).
@MainActor
@Observable
final class ActivityViewModel {
    let activity: Activity
    let sport: Sport

    private(set) var analysis: ActivityAnalysis?
    private(set) var compareAnalysis: ActivityAnalysis?
    private(set) var lanes: [LaneKind: [DisplayPoint]] = [:]
    private(set) var compareLanes: [LaneKind: [DisplayPoint]] = [:]
    private(set) var gradeStops: [Gradient.Stop] = []
    private(set) var splits: [SplitStats] = []
    private(set) var laps: [SplitStats] = []
    private(set) var insights: [Insight] = []
    private(set) var similar: [Activity] = []
    private(set) var isLoading = true

    var tab: DetailTab = .overview
    var axis: XAxis = .distance { didSet { if oldValue != axis { rebuildLanes(); scrubX = nil; rangeX = nil } } }
    var compare: Activity? { didSet { loadCompare() } }

    // Selection, in display-x units (km/mi or minutes).
    var scrubX: Double?
    var rangeX: ClosedRange<Double>?
    var highlight: (range: ClosedRange<Int>, label: String)?
    var zoom: Double = 1
    var scrollX: Double = 0

    init(activity: Activity) {
        self.activity = activity
        self.sport = activity.sport
        #if DEBUG
        if let t = UserDefaults.standard.string(forKey: "detailTab"), let tab = DetailTab.allCases.first(where: { $0.rawValue.lowercased() == t }) {
            self.tab = tab
        }
        #endif
    }

    var effectiveAxis: XAxis { analysis?.effectiveAxis(axis) ?? .time }
    var xLabel: String { effectiveAxis == .distance ? Fmt.distanceLabel : "min" }
    var splitUnit: Double { sport == .ride ? 5 * Fmt.distanceUnit : Fmt.distanceUnit }

    var xDomain: ClosedRange<Double> {
        guard let a = analysis else { return 0...1 }
        let hi = effectiveAxis == .distance ? Fmt.distanceValue(a.totalDistance) : a.elapsed / 60
        return 0...max(hi, 0.01)
    }

    func displayX(raw: Double) -> Double { effectiveAxis == .distance ? Fmt.distanceValue(raw) : raw / 60 }
    func rawX(display: Double) -> Double { effectiveAxis == .distance ? display * Fmt.distanceUnit : display * 60 }

    func time(atDisplayX x: Double) -> TimeInterval? {
        analysis?.time(forX: rawX(display: x), axis: effectiveAxis)
    }

    func displayX(time t: TimeInterval) -> Double {
        guard let a = analysis else { return 0 }
        return displayX(raw: a.x(forTime: t, axis: effectiveAxis))
    }

    var scrubTime: TimeInterval? { scrubX.flatMap { time(atDisplayX: $0) } }

    var markerCoordinate: CLLocationCoordinate2D? {
        guard let t = scrubTime, let a = analysis, a.hasRoute else { return nil }
        return a.points[min(a.index(atTime: t), a.points.count - 1)].coordinate
    }

    var rangeTimes: (TimeInterval, TimeInterval)? {
        guard let r = rangeX, let a = time(atDisplayX: r.lowerBound), let b = time(atDisplayX: r.upperBound), b > a else { return nil }
        return (a, b)
    }

    var rangeStats: RangeStats? { rangeTimes.flatMap { analysis?.stats(from: $0.0, to: $0.1) } }

    /// Route indices to draw highlighted on the map.
    var mapHighlight: ClosedRange<Int>? {
        if let rt = rangeTimes, let an = analysis {
            let i = an.index(atTime: rt.0), j = an.index(atTime: rt.1)
            return j > i ? i...j : nil
        }
        return highlight?.range
    }

    var mapHighlightLabel: String? {
        if let s = rangeStats { return "Selection · \(Fmt.distance(s.distance))" }
        return highlight?.label
    }

    var zones: HeartZones { Profile.zones }

    var timeInZones: [TimeInterval] {
        guard let a = analysis, a.hr.count > 1 else { return [] }
        return zones.timeInZones(a.hr)
    }

    // MARK: Loading

    func load(peers: [Activity], book: RecordBook) async {
        let input = activity.analysisInput
        let a = await Task.detached(priority: .userInitiated) { input.analysis() }.value
        analysis = a
        splits = a.splits(unit: splitUnit, labelScale: Fmt.distanceUnit)
        laps = a.lapStats()
        similar = activity.similar(in: peers).sorted { $0.start > $1.start }
        rebuildLanes()
        insights = buildInsights(a, book: book)
        isLoading = false
    }

    private func transform(_ kind: LaneKind, _ y: Double) -> Double {
        switch kind {
        case .pace, .gap: sport.usesPace ? min(Fmt.paceValue(y), Fmt.paceCap(sport)) : Fmt.speedValue(y)
        case .elevation: Fmt.elevationValue(y)
        default: y
        }
    }

    private func display(_ a: ActivityAnalysis, _ kind: LaneKind) -> [DisplayPoint] {
        a.lane(kind, axis: axis).map { DisplayPoint(id: $0.id, x: displayX(raw: $0.x), y: transform(kind, $0.y), t: $0.t) }
    }

    private func rebuildLanes() {
        guard let a = analysis else { return }
        var l: [LaneKind: [DisplayPoint]] = [:]
        for kind in LaneKind.allCases {
            if kind == .gap && !sport.usesGAP { continue }
            let pts = display(a, kind)
            if !pts.isEmpty { l[kind] = pts }
        }
        lanes = l
        // Elevation coloured by grade: one gradient stop per ~1/60th of the route.
        let raw = a.lane(.elevation, axis: axis, maxPoints: 60)
        if let lo = raw.first?.x, let hi = raw.last?.x, hi > lo {
            gradeStops = raw.map { Gradient.Stop(color: DS.gradeColor($0.grade), location: ($0.x - lo) / (hi - lo)) }
        } else {
            gradeStops = []
        }
        rebuildCompareLanes()
    }

    private func loadCompare() {
        guard let c = compare else { compareAnalysis = nil; compareLanes = [:]; return }
        let input = c.analysisInput
        Task {
            let a = await Task.detached { input.analysis() }.value
            compareAnalysis = a
            rebuildCompareLanes()
        }
    }

    private func rebuildCompareLanes() {
        guard let c = compareAnalysis else { compareLanes = [:]; return }
        var l: [LaneKind: [DisplayPoint]] = [:]
        for kind in [LaneKind.pace, .heartRate] {
            // Compare aligns on the same axis from each activity's own start.
            let pts = c.lane(kind, axis: axis).map {
                DisplayPoint(id: $0.id, x: effectiveAxis == .distance ? Fmt.distanceValue($0.x) : $0.x / 60,
                             y: transform(kind, $0.y), t: $0.t)
            }
            if !pts.isEmpty { l[kind] = pts }
        }
        compareLanes = l
    }

    /// Jump to the analysis tab with a split selected as the range.
    func focus(on split: SplitStats) {
        rangeX = displayX(time: split.stats.start)...displayX(time: split.stats.end)
        highlight = nil
        tab = .analysis
    }

    // MARK: Insights

    private func buildInsights(_ a: ActivityAnalysis, book: RecordBook) -> [Insight] {
        var out: [Insight] = []

        for e in activity.efforts.reversed() {
            if book.rank(of: activity, distance: e.distance) == 1 {
                out.append(Insight(icon: "trophy.fill", title: "Personal record · \(Sport.effortLabel(e.distance))",
                                   detail: "\(Fmt.duration(e.duration)) — your fastest ever.", tint: DS.pr))
            } else if book.yearRank(of: activity, distance: e.distance) == 1 {
                out.append(Insight(icon: "calendar", title: "Fastest \(Sport.effortLabel(e.distance)) this year",
                                   detail: "\(Fmt.duration(e.duration)) at \(Fmt.speedOrPace(e.speed, sport: sport)).", tint: .orange))
            }
            if out.count >= 2 { break }
        }

        if let h = a.halves {
            let diff = h.second - h.first
            if diff < -h.first * 0.02 {
                out.append(Insight(icon: "arrow.down.right.circle.fill", title: "Negative split",
                                   detail: "Second half was \(Fmt.duration(-diff)) faster than the first. Great pacing.", tint: .green))
            } else if diff > h.first * 0.08 {
                out.append(Insight(icon: "tortoise.fill", title: "Faded in the second half",
                                   detail: "Second half was \(Fmt.duration(diff)) slower. Try starting a little easier.", tint: .orange))
            } else {
                out.append(Insight(icon: "equal.circle.fill", title: "Even halves",
                                   detail: "Halves within \(Fmt.duration(abs(diff))) of each other.", tint: .blue))
            }
        }

        if let cv = a.paceVariability(unit: splitUnit) {
            let pct = cv * 100
            if pct < 3 {
                out.append(Insight(icon: "metronome.fill", title: "Very consistent pacing",
                                   detail: String(format: "Split speeds varied only %.1f%%.", pct), tint: .teal))
            } else if pct > 8 {
                out.append(Insight(icon: "waveform.path", title: "Variable pacing",
                                   detail: String(format: "Split speeds varied %.0f%% — hills, stops or intervals.", pct), tint: .gray))
            }
        }

        if let d = a.decoupling() {
            if d < 5 {
                out.append(Insight(icon: "heart.circle.fill", title: "Strong aerobic endurance",
                                   detail: String(format: "Pace-to-heart-rate decoupling %.1f%% (under 5%% is good).", d), tint: .green))
            } else {
                out.append(Insight(icon: "heart.text.square.fill", title: "Cardiac drift",
                                   detail: String(format: "Decoupling %.1f%% — heart rate rose relative to pace. Heat, fatigue or hydration?", d), tint: .red))
            }
        }

        if !similar.isEmpty {
            let times = similar.map(\.activeTime)
            let avg = times.reduce(0, +) / Double(times.count)
            let diff = activity.activeTime - avg
            let rank = (similar + [activity]).sorted { $0.activeTime < $1.activeTime }.firstIndex { $0.healthID == activity.healthID }! + 1
            out.append(Insight(icon: "arrow.triangle.capsulepath", title: "Route done \(similar.count + 1) times",
                               detail: "\(Fmt.duration(abs(diff))) \(diff <= 0 ? "faster" : "slower") than your average here · #\(rank) of \(similar.count + 1).",
                               tint: .indigo))
        }

        if let temp = activity.temperature, temp >= 27 {
            out.append(Insight(icon: "thermometer.sun.fill", title: "Hot conditions",
                               detail: "\(Fmt.temperature(temp)) — expect higher heart rate at the same pace.", tint: .orange))
        }
        return out
    }
}
