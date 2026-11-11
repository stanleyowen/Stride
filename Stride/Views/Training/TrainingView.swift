import SwiftUI
import SwiftData
import Charts
import StrideCore

struct TrainingView: View {
    @Query(sort: \Activity.start) private var all: [Activity]
    @Query(sort: \Goal.createdAt) private var goals: [Goal]
    @Environment(\.modelContext) private var context
    @State private var addingGoal = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if all.isEmpty {
                        EmptyState(icon: "waveform.path.ecg", title: "No training data",
                                   message: "Import activities to see your fitness, fatigue and training load.")
                    } else {
                        FitnessCard(activities: all)
                        WeeklyLoadCard(activities: all)
                        TrainingCalendarCard(activities: all)
                        TrendsCard(activities: all)
                    }
                    goalsCard
                }
                .padding()
            }
            .background(DS.canvas)
            .navigationTitle("Training")
            .strideDestinations()
            .sheet(isPresented: $addingGoal) { GoalEditor().presentationDetents([.medium, .large]) }
        }
    }

    private var goalsCard: some View {
        Card(title: "Goals", icon: "target", tint: .green) {
            if goals.isEmpty {
                Text("Set weekly, monthly or yearly targets and track your progress.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(goals) { g in
                GoalRow(goal: g, activities: all)
                    .contextMenu { Button("Delete", role: .destructive) { context.delete(g) } }
            }
            Button { addingGoal = true } label: { Label("Add goal", systemImage: "plus.circle.fill") }
                .font(.subheadline.weight(.semibold))
        }
    }
}

// MARK: - Fitness & Freshness

struct FitnessCard: View {
    let activities: [Activity]
    @State private var days = 90
    @State private var scrub: Date?
    @State private var pinned: Date?

    var body: some View {
        let cal = Calendar.current
        let loads = Dictionary(activities.map { (cal.startOfDay(for: $0.start), $0.relativeEffort) }, uniquingKeysWith: +)
        let series = TrainingLoad.fitness(loads: loads, through: .now)
        let from = cal.date(byAdding: .day, value: -days, to: cal.startOfDay(for: .now))!
        let shown = series.filter { $0.id >= from }
        let focus = (scrub ?? pinned).flatMap { d in shown.first { cal.isDate($0.id, inSameDayAs: d) } } ?? shown.last
        let dayActs = focus.map { f in activities.filter { cal.isDate($0.start, inSameDayAs: f.id) } } ?? []

        Card(title: "Fitness & Freshness", subtitle: "Drag or tap a day", icon: "chart.line.uptrend.xyaxis", tint: .blue) {
            Picker("Range", selection: $days) {
                Text("90 days").tag(90); Text("6 months").tag(182); Text("1 year").tag(365)
            }
            .pickerStyle(.segmented)

            if let f = focus {
                let status = Self.formStatus(f.form)
                HStack(spacing: 0) {
                    StatTile(label: "Fitness", value: "\(Int(f.fitness.rounded()))", tint: .blue)
                    StatTile(label: "Fatigue", value: "\(Int(f.fatigue.rounded()))", tint: .pink)
                    StatTile(label: "Form", value: String(format: "%+.0f", f.form), tint: status.1)
                }
                HStack {
                    Text(f.id.formatted(date: .abbreviated, time: .omitted)).font(.caption.weight(.semibold))
                    Text("· \(status.0)").font(.caption).foregroundStyle(status.1)
                    Spacer()
                    if f.load > 0 { Text("Training load \(Int(f.load))").font(.caption).foregroundStyle(.secondary) }
                }
            }

            Chart {
                ForEach(shown) { d in
                    LineMark(x: .value("Day", d.id, unit: .day), y: .value("Value", d.fitness), series: .value("S", "Fitness"))
                        .foregroundStyle(.blue).interpolationMethod(.monotone)
                    LineMark(x: .value("Day", d.id, unit: .day), y: .value("Value", d.fatigue), series: .value("S", "Fatigue"))
                        .foregroundStyle(.pink.opacity(0.8)).interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    if d.load > 0 {
                        BarMark(x: .value("Day", d.id, unit: .day), y: .value("Load", d.load / 3))
                            .foregroundStyle(Color.gray.opacity(0.25))
                    }
                }
                if let f = focus {
                    RuleMark(x: .value("Focus", f.id, unit: .day)).foregroundStyle(Color.primary.opacity(0.3))
                }
            }
            .chartXSelection(value: $scrub)
            .chartForegroundStyleScale(["Fitness": Color.blue, "Fatigue": Color.pink])
            .chartLegend(.hidden)
            .frame(height: 170)
            .accessibilityChartDescriptor(SeriesChartDescriptor(title: "Fitness", xTitle: "Day", yTitle: "Fitness",
                                                                points: shown.enumerated().map { (Double($0.offset), $0.element.fitness) }))

            let formLo = min(-45, (shown.map(\.form).min() ?? 0) - 5)
            let formHi = max(30, (shown.map(\.form).max() ?? 0) + 5)
            Text("Form").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Chart {
                // Bands stop at the visible range; marks outside the domain aren't clipped.
                RectangleMark(yStart: .value("a", 5), yEnd: .value("b", formHi)).foregroundStyle(Color.blue.opacity(0.08))
                RectangleMark(yStart: .value("a", -10), yEnd: .value("b", 5)).foregroundStyle(Color.gray.opacity(0.08))
                RectangleMark(yStart: .value("a", -30), yEnd: .value("b", -10)).foregroundStyle(Color.green.opacity(0.10))
                RectangleMark(yStart: .value("a", formLo), yEnd: .value("b", -30)).foregroundStyle(Color.red.opacity(0.08))
                ForEach(shown) { d in
                    LineMark(x: .value("Day", d.id, unit: .day), y: .value("Form", d.form))
                        .foregroundStyle(Color.primary.opacity(0.7)).interpolationMethod(.monotone)
                }
                if let f = focus {
                    RuleMark(x: .value("Focus", f.id, unit: .day)).foregroundStyle(Color.primary.opacity(0.3))
                    PointMark(x: .value("Day", f.id, unit: .day), y: .value("Form", f.form)).foregroundStyle(Self.formStatus(f.form).1)
                }
            }
            .chartYScale(domain: formLo...formHi)
            .chartPlotStyle { $0.clipped() }
            .chartXAxis(.hidden)
            .chartXSelection(value: $scrub)
            .frame(height: 90)
            HStack(spacing: 10) {
                legend("Fresh", .blue); legend("Neutral", .gray); legend("Optimal", .green); legend("Fatigued", .red)
            }

            if !dayActs.isEmpty {
                Divider()
                ForEach(dayActs) { a in
                    NavigationLink(value: a) { CompactActivityRow(activity: a) }.buttonStyle(.plain)
                }
            }
        }
        .onChange(of: scrub) { _, v in if let v { pinned = v } }
        .sensoryFeedback(.selection, trigger: scrub.map { Calendar.current.startOfDay(for: $0) })
    }

    private func legend(_ t: String, _ c: Color) -> some View {
        Label(t, systemImage: "square.fill").font(.caption2).foregroundStyle(c)
    }

    static func formStatus(_ form: Double) -> (String, Color) {
        switch form {
        case 5...: ("Fresh — ready to race", .blue)
        case -10..<5: ("Neutral — maintaining", .gray)
        case -30 ..< -10: ("Optimal training", .green)
        default: ("High fatigue — consider rest", .red)
        }
    }
}

// MARK: - Weekly load

struct WeeklyLoadCard: View {
    let activities: [Activity]
    @State private var selected: Date?

    private struct Week: Identifiable {
        let id: Date
        let load: Double
        let range: ClosedRange<Double>?
    }

    var body: some View {
        let cal = Calendar.current
        let current = cal.dateInterval(of: .weekOfYear, for: .now)!.start
        let weeks: [Week] = (0..<8).reversed().map { i in
            let s = cal.date(byAdding: .weekOfYear, value: -i, to: current)!
            let e = cal.date(byAdding: .weekOfYear, value: 1, to: s)!
            return Week(id: s, load: activities.filter { $0.start >= s && $0.start < e }.reduce(0) { $0 + $1.relativeEffort },
                        range: WeeklyLoad.range(activities, before: s))
        }
        let sel = weeks.first { $0.id == selected } ?? weeks.last!

        Card(title: "Weekly Training Load", subtitle: "Tap a week", icon: "heart.fill", tint: .red) {
            Chart(weeks) { w in
                if let r = w.range {
                    RectangleMark(x: .value("Week", w.id, unit: .weekOfYear), yStart: .value("Lo", r.lowerBound),
                                  yEnd: .value("Hi", r.upperBound), width: .ratio(0.9))
                        .foregroundStyle(Color.green.opacity(0.15))
                }
                BarMark(x: .value("Week", w.id, unit: .weekOfYear), y: .value("Load", w.load), width: .ratio(0.5))
                    .foregroundStyle(w.id == sel.id ? AnyShapeStyle(Color.red.gradient) : AnyShapeStyle(Color.red.opacity(0.35)))
                    .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .onChartTap { proxy, p in
                if let d = proxy.value(atX: p.x, as: Date.self) {
                    selected = Calendar.current.dateInterval(of: .weekOfYear, for: d)?.start
                }
            }
            .sensoryFeedback(.selection, trigger: selected)
            .frame(height: 150)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Week of \(sel.id.formatted(.dateTime.month(.abbreviated).day()))").font(.subheadline.weight(.semibold))
                    if let r = sel.range {
                        let st = WeeklyLoad.status(sel.load, r)
                        Text(st.0).font(.caption).foregroundStyle(st.1)
                    } else {
                        Text("Not enough history for a usual range yet").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(sel.load))").font(.title3.bold()).monospacedDigit().contentTransition(.numericText())
                    if let r = sel.range { Text("Usual range \(Int(r.lowerBound))–\(Int(r.upperBound))").font(.caption2).foregroundStyle(.secondary) }
                }
            }
        }
    }
}

// MARK: - Calendar

struct TrainingCalendarCard: View {
    let activities: [Activity]
    @State private var month = Calendar.current.dateInterval(of: .month, for: .now)!.start
    @State private var selectedDay: Date?

    var body: some View {
        let cal = Calendar.current
        let monthIv = cal.dateInterval(of: .month, for: month)!
        let firstWeek = cal.dateInterval(of: .weekOfYear, for: monthIv.start)!.start
        let weeks = (0..<6).map { cal.date(byAdding: .weekOfYear, value: $0, to: firstWeek)! }.filter { $0 < monthIv.end }
        let dayActs = selectedDay.map { d in activities.filter { cal.isDate($0.start, inSameDayAs: d) } } ?? []
        let symbols = cal.veryShortWeekdaySymbols
        let offset = cal.firstWeekday - 1

        Card {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(monthIv.end > .now)
            }
            .buttonStyle(.borderless)

            Grid(horizontalSpacing: 2, verticalSpacing: 6) {
                GridRow {
                    ForEach(0..<7, id: \.self) { i in
                        Text(symbols[(i + offset) % 7]).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(Fmt.distanceLabel).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(weeks, id: \.self) { w in
                    let weekActs = activities.filter { $0.start >= w && $0.start < cal.date(byAdding: .day, value: 7, to: w)! }
                    GridRow {
                        ForEach(0..<7, id: \.self) { i in
                            let day = cal.date(byAdding: .day, value: i, to: w)!
                            dayCell(day, inMonth: monthIv.contains(day), acts: weekActs.filter { cal.isDate($0.start, inSameDayAs: day) })
                        }
                        Text(String(format: "%.0f", Fmt.distanceValue(weekActs.reduce(0) { $0 + $1.distance })))
                            .font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }

            if let d = selectedDay {
                Divider()
                Text(d.formatted(date: .complete, time: .omitted)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if dayActs.isEmpty {
                    Text("Rest day").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(dayActs) { a in
                    NavigationLink(value: a) { CompactActivityRow(activity: a) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func dayCell(_ day: Date, inMonth: Bool, acts: [Activity]) -> some View {
        let cal = Calendar.current
        let isSel = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
        return Button {
            withAnimation(.snappy) { selectedDay = isSel ? nil : day }
        } label: {
            VStack(spacing: 2) {
                Text("\(cal.component(.day, from: day))")
                    .font(.caption2.weight(cal.isDateInToday(day) ? .bold : .regular))
                    .foregroundStyle(inMonth ? .primary : .tertiary)
                ZStack {
                    ForEach(Array(acts.prefix(3).enumerated()), id: \.offset) { i, a in
                        Circle().fill(a.sport.color)
                            .frame(width: 8 + min(a.relativeEffort / 25, 12), height: 8 + min(a.relativeEffort / 25, 12))
                            .offset(x: CGFloat(i) * 4)
                    }
                }
                .frame(height: 20)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isSel ? DS.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(acts.count) activities")
    }

    private func shift(_ n: Int) {
        withAnimation { month = Calendar.current.date(byAdding: .month, value: n, to: month)!; selectedDay = nil }
    }
}
