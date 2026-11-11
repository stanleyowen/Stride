import SwiftUI
import SwiftData
import Charts
import StrideCore

struct RecordsView: View {
    @Query(sort: \Activity.start) private var all: [Activity]
    @Environment(RecordStore.self) private var records
    @State private var sport: Sport = .run
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var selectedMonth: Int?
    private let sports: [Sport] = [.run, .ride, .walk, .hike]

    var body: some View {
        let book = records.book(all)
        let acts = all.filter { $0.sport == sport }

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Sport", selection: $sport) {
                        ForEach(sports) { Label($0.label, systemImage: $0.icon).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if acts.isEmpty {
                        EmptyState(icon: "trophy", title: "No \(sport.label.lowercased())s yet",
                                   message: "Import activities with GPS to unlock personal records.")
                    } else {
                        yearCard(acts)
                        if sport == .run { predictorCard(book) }
                        effortsCard(book)
                        recordsCard(acts)
                    }
                }
                .padding()
            }
            .background(DS.canvas)
            .navigationTitle("Records")
            .strideDestinations()
        }
    }

    // MARK: Year in review

    private func yearCard(_ acts: [Activity]) -> some View {
        let cal = Calendar.current
        let years = Array(Set(acts.map { cal.component(.year, from: $0.start) })).sorted(by: >)
        let inYear = acts.filter { cal.component(.year, from: $0.start) == year }
        let byMonth = Dictionary(grouping: inYear) { cal.component(.month, from: $0.start) }
        let busiest = byMonth.max { $0.value.reduce(0) { $0 + $1.distance } < $1.value.reduce(0) { $0 + $1.distance } }
        let longest = inYear.max { $0.distance < $1.distance }

        return Card(title: "\(String(year)) in Review", subtitle: "Tap a month", icon: "calendar", tint: sport.color) {
            if years.count > 1 {
                Picker("Year", selection: $year) { ForEach(years, id: \.self) { Text(String($0)).tag($0) } }
                    .pickerStyle(.segmented)
                    .onChange(of: year) { selectedMonth = nil }
            }
            HStack(spacing: 0) {
                StatTile(label: "Distance", value: String(format: "%.0f", Fmt.distanceValue(inYear.reduce(0) { $0 + $1.distance })), unit: Fmt.distanceLabel)
                let minutes = Int((inYear.reduce(0) { $0 + $1.activeTime } / 60).rounded())
                StatTile(label: "Time", value: String(format: "%d:%02d", minutes / 60, minutes % 60), unit: "h")
                StatTile(label: "Climb", value: String(format: "%.0f", Fmt.elevationValue(inYear.reduce(0) { $0 + $1.elevationGain })), unit: Fmt.elevationLabel)
                StatTile(label: sport.label + "s", value: "\(inYear.count)")
            }
            Chart {
                ForEach(1...12, id: \.self) { m in
                    BarMark(x: .value("Month", cal.shortMonthSymbols[m - 1]),
                            y: .value("Distance", Fmt.distanceValue((byMonth[m] ?? []).reduce(0) { $0 + $1.distance })))
                        .foregroundStyle(m == (selectedMonth ?? busiest?.key) ? AnyShapeStyle(sport.color.gradient) : AnyShapeStyle(sport.color.opacity(0.35)))
                        .cornerRadius(3)
                }
            }
            .chartXAxis { AxisMarks { v in AxisValueLabel { if let s = v.as(String.self) { Text(String(s.prefix(1))) } } } }
            .onChartTap { proxy, p in
                if let name = proxy.value(atX: p.x, as: String.self), let i = cal.shortMonthSymbols.firstIndex(of: name) {
                    withAnimation(.snappy) { selectedMonth = selectedMonth == i + 1 ? nil : i + 1 }
                }
            }
            .sensoryFeedback(.selection, trigger: selectedMonth)
            .frame(height: 110)
            if let m = selectedMonth {
                let items = byMonth[m] ?? []
                HStack {
                    Label("\(cal.monthSymbols[m - 1]) · \(Fmt.distance(items.reduce(0) { $0 + $1.distance }, digits: 0)) · \(items.count) \(sport.label.lowercased())\(items.count == 1 ? "" : "s")",
                          systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Clear") { withAnimation(.snappy) { selectedMonth = nil } }.font(.caption.weight(.semibold))
                }
                .transition(.opacity)
            } else if let busiest {
                Label("Most active: \(cal.monthSymbols[busiest.key - 1]) · \(Fmt.distance(busiest.value.reduce(0) { $0 + $1.distance }, digits: 0))",
                      systemImage: "flame.fill").font(.caption).foregroundStyle(.secondary)
            }
            if let longest {
                NavigationLink(value: longest) {
                    Label("Longest: \(longest.name) · \(Fmt.distance(longest.distance))", systemImage: "arrow.left.and.right")
                        .font(.caption)
                }
            }
        }
        .onAppear { if let first = years.first, !years.contains(year) { year = first } }
    }

    // MARK: Race predictor

    private func predictorCard(_ book: RecordBook) -> some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: .now)!
        let recent = Sport.run.effortTargets.flatMap { d in
            book.entries(.run, d).filter { $0.activity.start >= cutoff }.prefix(1).map { (distance: d, duration: $0.effort.duration) }
        }
        let targets: [Double] = [5000, 10000, 21097.5, 42195]
        let preds = RacePredictor.predict(from: recent, targets: targets)
        let vo2 = HealthHistory.vo2Max.last?.v

        return Card(title: "Race Predictor", subtitle: "From your last 90 days", icon: "flag.checkered", tint: .purple) {
            if preds.isEmpty && vo2 == nil {
                Text("Run at least 1.5 km with GPS in the last 90 days to get predictions.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Race").foregroundStyle(.secondary)
                        Text("Predicted").foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                        if vo2 != nil { Text("From VO₂ max").foregroundStyle(.secondary).gridColumnAlignment(.trailing) }
                        Text("")
                    }
                    .font(.caption.weight(.semibold))
                    ForEach(targets, id: \.self) { t in
                        let p = preds.first { $0.distance == t }
                        GridRow {
                            Text(Sport.effortLabel(t)).font(.subheadline.weight(.semibold))
                            VStack(alignment: .trailing, spacing: 0) {
                                Text(p.map { Fmt.duration($0.time) } ?? "–").font(.subheadline.bold()).monospacedDigit()
                                if let p { Text(Fmt.pace(t / p.time)).font(.caption2).foregroundStyle(.secondary) }
                            }
                            if let vo2 {
                                Text(Fmt.duration(RacePredictor.time(forVDOT: vo2, distance: t))).font(.subheadline).monospacedDigit()
                            }
                            if let p {
                                MetricPill(icon: "checkmark.seal", text: p.confidence.rawValue,
                                           tint: p.confidence == .high ? .green : p.confidence == .medium ? .orange : .gray)
                            } else { Text("") }
                        }
                    }
                }
                Text("Predicted from your strongest recent best effort (Riegel formula)\(vo2 != nil ? "; the VO₂ max column uses Apple Health's estimate (\(String(format: "%.1f", vo2!)))" : ""). Confidence drops the further the race is from the effort it's based on.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Best efforts & records

    private func effortsCard(_ book: RecordBook) -> some View {
        Card(title: "Best Efforts", subtitle: "Tap for history", icon: "stopwatch") {
            VStack(spacing: 0) {
                ForEach(sport.effortTargets, id: \.self) { d in
                    let entries = book.entries(sport, d)
                    Group {
                        if let best = entries.first {
                            NavigationLink(value: EffortKey(sport: sport, distance: d)) {
                                HStack {
                                    Image(systemName: "trophy.fill").foregroundStyle(DS.pr)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(Sport.effortLabel(d)).font(.subheadline.weight(.semibold))
                                        Text("\(best.activity.start.formatted(date: .abbreviated, time: .omitted)) · \(entries.count) attempt\(entries.count == 1 ? "" : "s")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(Fmt.duration(best.effort.duration)).font(.subheadline.bold()).monospacedDigit()
                                        Text(Fmt.speedOrPace(best.effort.speed, sport: sport)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        } else {
                            HStack {
                                Image(systemName: "trophy").foregroundStyle(.tertiary)
                                Text(Sport.effortLabel(d))
                                Spacer()
                                Text("Not yet")
                            }
                            .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 9)
                    if d != sport.effortTargets.last { Divider() }
                }
            }
        }
    }

    private func recordsCard(_ acts: [Activity]) -> some View {
        Card(title: "All-Time Records", icon: "star.fill", tint: .yellow) {
            VStack(spacing: 0) {
                record("Longest distance", "arrow.left.and.right", acts.max { $0.distance < $1.distance }) { Fmt.distance($0.distance) }
                Divider()
                record("Longest time", "clock", acts.max { $0.activeTime < $1.activeTime }) { Fmt.duration($0.activeTime) }
                Divider()
                record("Biggest climb", "mountain.2", acts.filter { $0.elevationGain > 0 }.max { $0.elevationGain < $1.elevationGain }) { Fmt.elevation($0.elevationGain) }
                Divider()
                record(sport.usesPace ? "Fastest average pace" : "Fastest average speed", "bolt",
                       acts.filter { $0.distance >= 1000 }.max { $0.avgSpeed < $1.avgSpeed }) { Fmt.speedOrPace($0.avgSpeed, sport: sport) }
                Divider()
                record("Hardest effort", "heart.fill", acts.max { $0.relativeEffort < $1.relativeEffort }) { "\(Int($0.relativeEffort))" }
            }
        }
    }

    @ViewBuilder
    private func record(_ title: String, _ icon: String, _ activity: Activity?, value: (Activity) -> String) -> some View {
        if let activity {
            NavigationLink(value: activity) {
                HStack {
                    Label(title, systemImage: icon).font(.subheadline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(value(activity)).font(.subheadline.bold()).monospacedDigit()
                        Text(activity.start.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
