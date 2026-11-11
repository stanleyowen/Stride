import SwiftUI
import SwiftData
import Charts
import StrideCore

/// An attempt at something timed: a best-effort distance or a segment.
struct Attempt: Identifiable {
    let id: PersistentIdentifier
    let activity: Activity
    let date: Date
    let duration: TimeInterval
    let distance: Double
}

/// Shared history UI: PR card, interactive chart (all / best per month), top 10.
struct AttemptHistory: View {
    let attempts: [Attempt]        // any order
    let sport: Sport
    @State private var selectedID: PersistentIdentifier?
    @State private var monthly = false

    var body: some View {
        let ranked = attempts.sorted { $0.duration < $1.duration }
        let chrono = attempts.sorted { $0.date < $1.date }
        let progression = prProgression(chrono)
        let perMonth = bestPerMonth(chrono)
        let shown = monthly ? perMonth : chrono
        let selected = ranked.first { $0.id == selectedID } ?? ranked.first
        let color = sport.color

        VStack(spacing: 16) {
            if let pr = ranked.first {
                Card {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Personal Record", systemImage: "trophy.fill").font(.subheadline.weight(.semibold)).foregroundStyle(DS.pr)
                            Text(Fmt.duration(pr.duration)).font(.heroValue).monospacedDigit()
                            Text("\(Fmt.speedOrPace(pr.distance / pr.duration, sport: sport)) · \(pr.date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("\(ranked.count)").font(.title2.bold())
                            Text(ranked.count == 1 ? "attempt" : "attempts").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if chrono.count >= 3 {
                        let last5 = chrono.suffix(5).map(\.duration)
                        let avg = last5.reduce(0, +) / Double(last5.count)
                        Text("Last \(last5.count) average \(Fmt.duration(avg)) · \(Fmt.duration(avg - pr.duration)) off your personal record")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Card(title: "History", subtitle: "Tap a point", icon: "chart.xyaxis.line") {
                Picker("Show", selection: $monthly) { Text("All attempts").tag(false); Text("Best per month").tag(true) }
                    .pickerStyle(.segmented)
                Chart {
                    ForEach(progression) { e in
                        LineMark(x: .value("Date", e.date), y: .value("Time", e.duration / 60), series: .value("S", "PR"))
                            .interpolationMethod(.stepEnd)
                            .foregroundStyle(DS.pr)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    if monthly {
                        ForEach(shown) { e in
                            LineMark(x: .value("Date", e.date), y: .value("Time", e.duration / 60), series: .value("S", "Monthly"))
                                .foregroundStyle(color.opacity(0.6)).interpolationMethod(.monotone)
                        }
                    }
                    ForEach(shown) { e in
                        let isSel = e.id == selected?.id
                        PointMark(x: .value("Date", e.date), y: .value("Time", e.duration / 60))
                            .foregroundStyle(isSel ? color : color.opacity(0.45))
                            .symbolSize(isSel ? 160 : 50)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false, reversed: true))
                .chartYAxis {
                    AxisMarks(position: .leading) { v in
                        AxisGridLine()
                        AxisValueLabel { if let m = v.as(Double.self) { Text(Fmt.duration(m * 60)) } }
                    }
                }
                .onChartTap { proxy, tap in
                    let nearest = shown.min { a, b in dist(proxy, a, tap) < dist(proxy, b, tap) }
                    withAnimation(.snappy) { selectedID = nearest?.id }
                }
                .sensoryFeedback(.selection, trigger: selectedID)
                .frame(height: 220)
                HStack(spacing: 14) {
                    Label("Record progression", systemImage: "line.diagonal").foregroundStyle(DS.pr)
                    Label("Attempt", systemImage: "circle.fill").foregroundStyle(color)
                    Text("Faster is higher").foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            if let s = selected {
                let rank = (ranked.firstIndex { $0.id == s.id } ?? 0) + 1
                Card(title: "Selected Attempt") {
                    NavigationLink(value: s.activity) { attemptRow(s, rank: rank) }.buttonStyle(.plain)
                }
            }

            Card(title: "Top 10") {
                VStack(spacing: 0) {
                    ForEach(Array(ranked.prefix(10).enumerated()), id: \.element.id) { i, e in
                        NavigationLink(value: e.activity) { attemptRow(e, rank: i + 1) }.buttonStyle(.plain)
                        if i < min(ranked.count, 10) - 1 { Divider() }
                    }
                }
            }
        }
    }

    private func attemptRow(_ e: Attempt, rank: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)").font(.caption.bold()).frame(width: 22).foregroundStyle(.secondary)
            MedalView(rank: rank)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.activity.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(e.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Fmt.duration(e.duration)).font(.subheadline.bold()).monospacedDigit()
                Text(Fmt.speedOrPace(e.distance / e.duration, sport: sport)).font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private func prProgression(_ chrono: [Attempt]) -> [Attempt] {
        var best = Double.infinity
        return chrono.filter { e in
            guard e.duration < best else { return false }
            best = e.duration
            return true
        }
    }

    private func bestPerMonth(_ chrono: [Attempt]) -> [Attempt] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: chrono) { cal.dateInterval(of: .month, for: $0.date)!.start }
        return groups.values.compactMap { $0.min { $0.duration < $1.duration } }.sorted { $0.date < $1.date }
    }

    private func dist(_ proxy: ChartProxy, _ e: Attempt, _ tap: CGPoint) -> CGFloat {
        guard let x = proxy.position(forX: e.date), let y = proxy.position(forY: e.duration / 60) else { return .infinity }
        return hypot(x - tap.x, y - tap.y)
    }
}

struct EffortHistoryView: View {
    let key: EffortKey
    @Query(sort: \Activity.start) private var all: [Activity]
    @Environment(RecordStore.self) private var records

    var body: some View {
        let attempts = records.book(all).entries(key.sport, key.distance).map {
            Attempt(id: $0.id, activity: $0.activity, date: $0.activity.start, duration: $0.effort.duration, distance: key.distance)
        }
        ScrollView {
            AttemptHistory(attempts: attempts, sport: key.sport).padding()
        }
        .background(DS.canvas)
        .navigationTitle(Sport.effortLabel(key.distance))
        .navigationBarTitleDisplayMode(.inline)
    }
}
