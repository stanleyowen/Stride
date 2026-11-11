import SwiftUI
import SwiftData
import Charts
import StrideCore

enum TrendMetric: String, CaseIterable, Identifiable {
    case distance = "Distance", time = "Time", elevation = "Elevation", count = "Activities"
    case pace = "Average pace", heartRate = "Average heart rate", load = "Training load", vo2 = "VO₂ max", restingHR = "Resting heart rate"
    var id: String { rawValue }

    var isRate: Bool { [.pace, .heartRate, .vo2, .restingHR].contains(self) }

    func value(_ acts: [Activity], in iv: DateInterval, sport: Sport?) -> Double? {
        switch self {
        case .distance: return Fmt.distanceValue(acts.reduce(0) { $0 + $1.distance })
        case .time: return acts.reduce(0) { $0 + $1.activeTime } / 3600
        case .elevation: return Fmt.elevationValue(acts.reduce(0) { $0 + $1.elevationGain })
        case .count: return Double(acts.count)
        case .load: return acts.reduce(0) { $0 + $1.relativeEffort }
        case .pace:
            let moving = acts.filter { $0.distance > 0 }
            let d = moving.reduce(0) { $0 + $1.distance }, t = moving.reduce(0) { $0 + $1.activeTime }
            guard d > 0, t > 0 else { return nil }
            return (sport ?? .run).usesPace ? Fmt.paceValue(d / t) : Fmt.speedValue(d / t)
        case .heartRate:
            let hr = acts.compactMap { a in a.avgHR.map { ($0, a.activeTime) } }
            let w = hr.reduce(0) { $0 + $1.1 }
            return w > 0 ? hr.reduce(0) { $0 + $1.0 * $1.1 } / w : nil
        case .vo2, .restingHR:
            let s = (self == .vo2 ? HealthHistory.vo2Max : HealthHistory.restingHR)
                .filter { iv.contains(Date(timeIntervalSince1970: $0.t)) }
            return s.isEmpty ? nil : s.reduce(0) { $0 + $1.v } / Double(s.count)
        }
    }

    func format(_ v: Double, sport: Sport?) -> String {
        switch self {
        case .distance: String(format: "%.1f %@", v, Fmt.distanceLabel)
        case .time: Fmt.hoursMinutes(v * 3600)
        case .elevation: String(format: "%.0f %@", v, Fmt.elevationLabel)
        case .count, .load: String(format: "%.0f", v)
        case .pace: (sport ?? .run).usesPace ? Fmt.minutes(v) + " " + Fmt.paceLabel : String(format: "%.1f %@", v, Fmt.speedLabel)
        case .heartRate, .restingHR: String(format: "%.0f bpm", v)
        case .vo2: String(format: "%.1f", v)
        }
    }
}

struct TrendsCard: View {
    let activities: [Activity]
    @State private var sport: Sport?
    @State private var metric: TrendMetric = .distance
    @State private var monthly = false
    @State private var selected: Date?

    private struct Bucket: Identifiable {
        let id: Date
        let iv: DateInterval
        let activities: [Activity]
        let value: Double?
        var average: Double?
    }

    var body: some View {
        let cal = Calendar.current
        let comp: Calendar.Component = monthly ? .month : .weekOfYear
        let filtered = activities.filter { sport == nil || $0.sport == sport }
        let current = cal.dateInterval(of: comp, for: .now)!.start
        var buckets: [Bucket] = (0..<12).reversed().map { i in
            let s = cal.date(byAdding: comp, value: -i, to: current)!
            let iv = DateInterval(start: s, end: cal.date(byAdding: comp, value: 1, to: s)!)
            let acts = filtered.filter { iv.contains($0.start) }
            return Bucket(id: s, iv: iv, activities: acts, value: metric.value(acts, in: iv, sport: sport))
        }
        for i in buckets.indices {
            let window = buckets[max(0, i - 3)...i].compactMap(\.value)
            buckets[i].average = window.count >= 2 ? window.reduce(0, +) / Double(window.count) : nil
        }
        let sel = buckets.first { $0.id == selected } ?? buckets.last!
        let prev = buckets.firstIndex { $0.id == sel.id }.flatMap { $0 > 0 ? buckets[$0 - 1] : nil }
        let accent = sport?.color ?? DS.accent
        let reversed = metric == .pace && (sport ?? .run).usesPace

        return Card(title: "Trends", subtitle: "Tap a \(monthly ? "month" : "week")", icon: "chart.bar.xaxis", tint: .indigo) {
            HStack {
                Menu {
                    Picker("Sport", selection: $sport) {
                        Label("All sports", systemImage: "square.grid.2x2").tag(Sport?.none)
                        ForEach(Sport.allCases) { Label($0.label, systemImage: $0.icon).tag(Sport?.some($0)) }
                    }
                } label: {
                    Label(sport?.label ?? "All sports", systemImage: sport?.icon ?? "square.grid.2x2").font(.subheadline.weight(.medium))
                }
                Spacer()
                Picker("Metric", selection: $metric) { ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) } }
            }
            Picker("Period", selection: $monthly) { Text("12 weeks").tag(false); Text("12 months").tag(true) }
                .pickerStyle(.segmented)
                .onChange(of: monthly) { selected = nil }

            Chart {
                ForEach(buckets) { b in
                    if let v = b.value {
                        if metric.isRate {
                            LineMark(x: .value("Period", b.id, unit: comp), y: .value("Value", v), series: .value("S", "Value"))
                                .foregroundStyle(accent).interpolationMethod(.monotone)
                            PointMark(x: .value("Period", b.id, unit: comp), y: .value("Value", v))
                                .foregroundStyle(accent).symbolSize(b.id == sel.id ? 120 : 30)
                        } else {
                            BarMark(x: .value("Period", b.id, unit: comp), y: .value("Value", v))
                                .foregroundStyle(b.id == sel.id ? AnyShapeStyle(accent.gradient) : AnyShapeStyle(accent.opacity(0.3)))
                                .cornerRadius(4)
                        }
                    }
                    if let avg = b.average, !metric.isRate {
                        LineMark(x: .value("Period", b.id, unit: comp), y: .value("Avg", avg), series: .value("S", "Average"))
                            .foregroundStyle(Color.primary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: !metric.isRate, reversed: reversed))
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text(reversed ? Fmt.minutes(d) : String(format: "%.0f", d)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: comp, count: monthly ? 2 : 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: monthly ? .dateTime.month(.abbreviated) : .dateTime.month(.abbreviated).day())
                }
            }
            .onChartTap { proxy, p in
                if let d = proxy.value(atX: p.x, as: Date.self) {
                    withAnimation(.snappy) { selected = Calendar.current.dateInterval(of: comp, for: d)?.start }
                }
            }
            .sensoryFeedback(.selection, trigger: selected)
            .frame(height: 200)
            if !metric.isRate {
                Label("4-\(monthly ? "month" : "week") average", systemImage: "line.diagonal").font(.caption2).foregroundStyle(.secondary)
            }

            Divider()
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monthly ? sel.id.formatted(.dateTime.month(.wide).year())
                                 : "Week of \(sel.id.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(.subheadline.weight(.semibold))
                    Text("\(sel.activities.count) activit\(sel.activities.count == 1 ? "y" : "ies") · \(Fmt.hoursMinutes(sel.activities.reduce(0) { $0 + $1.activeTime }))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(sel.value.map { metric.format($0, sport: sport) } ?? "–").font(.title3.bold()).monospacedDigit()
                    if let v = sel.value, let pv = prev?.value, let ch = Fmt.percentChange(v, pv) {
                        Text("\(ch) from previous \(monthly ? "month" : "week")").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(sel.activities.sorted { $0.start > $1.start }.prefix(6)) { a in
                NavigationLink(value: a) { CompactActivityRow(activity: a) }.buttonStyle(.plain)
            }
        }
    }
}

struct CompactActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 12) {
            SportIcon(sport: activity.sport, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(activity.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(activity.distance > 0 ? Fmt.distance(activity.distance) : Fmt.duration(activity.activeTime))
                    .font(.subheadline.bold()).monospacedDigit()
                Text(activity.relativeEffort > 0 ? "Effort \(Int(activity.relativeEffort))" : Fmt.duration(activity.activeTime))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
