import SwiftUI
import SwiftData
import StrideCore

struct FeedView: View {
    @Query(sort: \Activity.start, order: .reverse) private var activities: [Activity]
    @Query private var gear: [Gear]
    @Environment(\.modelContext) private var context
    @Environment(HealthImporter.self) private var importer
    @Environment(RecordStore.self) private var records
    @State private var filter: Sport?
    @State private var search = ""
    @State private var renaming: Activity?
    @State private var newName = ""
    @State private var path = NavigationPath()

    private var filtered: [Activity] {
        activities.filter { a in
            (filter == nil || a.sport == filter) &&
            (search.isEmpty || a.name.localizedCaseInsensitiveContains(search) || a.notes.localizedCaseInsensitiveContains(search))
        }
    }

    private var presentSports: [Sport] {
        let set = Set(activities.map(\.sport))
        return Sport.allCases.filter(set.contains)
    }

    private var months: [(month: Date, items: [Activity])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: filtered) { cal.dateInterval(of: .month, for: $0.start)!.start }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if activities.isEmpty {
                    EmptyState(icon: "figure.run", title: "No activities yet",
                               message: "Connect Apple Health to see your workouts, splits, fitness and personal records.",
                               actionTitle: "Import from Apple Health") {
                        Task { await importer.importNew(into: context) }
                    }
                } else {
                    feed
                }
            }
            .navigationTitle("Home")
            .strideDestinations()
            #if DEBUG
            .task {
                // `-openActivity N` pushes the Nth activity (debug screenshots).
                let n = UserDefaults.standard.integer(forKey: "openActivity")
                if n > 0, activities.count >= n, path.isEmpty {
                    try? await Task.sleep(for: .milliseconds(300))
                    path.append(activities[n - 1])
                }
            }
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if importer.isImporting {
                        ProgressView()
                    } else {
                        Button { Task { await importer.importNew(into: context) } } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .accessibilityLabel("Sync with Apple Health")
                    }
                }
            }
            .alert("Rename activity", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") { renaming?.name = newName; renaming = nil }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
        }
    }

    private var feed: some View {
        let book = records.book(activities)
        return List {
            Section {
                WeekSummaryCard(activities: activities) { path.append($0) }.cardRow()
                if importer.isImporting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(importer.status.isEmpty ? "Syncing…" : importer.status).font(.subheadline)
                    }
                    .cardRow()
                }
                if presentSports.count > 1 {
                    SportFilterBar(sports: presentSports, selection: $filter)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.tertiary)
                    Text(search.isEmpty ? "No activities here yet." : "No activities match “\(search)”.")
                        .foregroundStyle(.secondary)
                    Button("Show all activities") { withAnimation(.snappy) { filter = nil; search = "" } }
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .cardRow()
            }

            ForEach(months, id: \.month) { group in
                Section {
                    ForEach(group.items) { activity in
                        Button { path.append(activity) } label: {
                            ActivityCard(activity: activity, prCount: book.prCount(activity))
                        }
                        .buttonStyle(.pressable)
                        .cardRow()
                        .contextMenu { menu(for: activity) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { withAnimation { context.delete(activity) } } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button { newName = activity.name; renaming = activity } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(DS.accent)
                        }
                    }
                } header: {
                    let n = group.items.count
                    HStack {
                        Text(group.month.formatted(.dateTime.month(.wide).year()))
                        Spacer()
                        Text("\(n) activit\(n == 1 ? "y" : "ies") · \(Fmt.distance(group.items.reduce(0) { $0 + $1.distance }, digits: 0))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DS.canvas)
        .searchable(text: $search, prompt: "Search activities and notes")
        .refreshable { await importer.importNew(into: context) }
    }

    @ViewBuilder
    private func menu(for a: Activity) -> some View {
        Button { newName = a.name; renaming = a } label: { Label("Rename", systemImage: "pencil") }
        Menu {
            ForEach(1...10, id: \.self) { v in
                Button { setRPE(a, v) } label: { Text("\(v) · \(RPE.label(v))") }
            }
        } label: { Label("Perceived exertion", systemImage: "gauge.with.dots.needle.67percent") }
        let options = gear.filter { !$0.retired && $0.kindRaw == a.sport.gearKind }
        if !options.isEmpty {
            Menu {
                Button("None") { a.gear = nil }
                ForEach(options) { g in Button(g.name) { a.gear = g } }
            } label: { Label("Gear", systemImage: a.sport == .ride ? "bicycle" : "shoeprints.fill") }
        }
        Divider()
        Button(role: .destructive) { context.delete(a) } label: { Label("Delete", systemImage: "trash") }
    }

    private func setRPE(_ a: Activity, _ v: Int) {
        a.rpe = v
        if a.heartRates.count <= 5 { a.recomputeDerived(profile: Profile.zones) }
    }
}

enum RPE {
    static func label(_ v: Int) -> String {
        switch v {
        case 1...2: "Easy"
        case 3...4: "Moderate"
        case 5...6: "Hard"
        case 7...8: "Very hard"
        default: "Max effort"
        }
    }
    static func color(_ v: Int) -> Color {
        switch v {
        case 1...3: .green
        case 4...6: .yellow
        case 7...8: .orange
        default: .red
        }
    }
}

extension View {
    func cardRow() -> some View {
        listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct SportFilterBar: View {
    let sports: [Sport]
    @Binding var selection: Sport?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, "All", "square.grid.2x2", DS.accent)
                ForEach(sports) { chip($0, $0.label, $0.icon, $0.color) }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ sport: Sport?, _ title: String, _ icon: String, _ color: Color) -> some View {
        let selected = selection == sport
        return Button {
            withAnimation(.snappy) { selection = sport }
        } label: {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(selected ? AnyShapeStyle(color) : AnyShapeStyle(DS.surface), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct WeekSummaryCard: View {
    let activities: [Activity]
    var onOpen: (Activity) -> Void = { _ in }
    @Query private var goals: [Goal]
    @State private var appeared = false

    var body: some View {
        let cal = Calendar.current
        let week = cal.dateInterval(of: .weekOfYear, for: .now)!
        let thisWeek = activities.filter { week.contains($0.start) }
        let km = thisWeek.reduce(0) { $0 + $1.distance }
        let time = thisWeek.reduce(0) { $0 + $1.activeTime }
        let load = thisWeek.reduce(0) { $0 + $1.relativeEffort }
        let range = WeeklyLoad.range(activities, before: week.start)
        let goal = goals.first { $0.periodRaw == GoalPeriod.week.rawValue && $0.metricRaw == GoalMetric.distance.rawValue }
        let target = goal?.target ?? 20_000
        let progress = min(km / max(target, 1), 1)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(DS.accent.opacity(0.18), lineWidth: 10)
                    Circle().trim(from: 0, to: appeared ? progress : 0)
                        .stroke(AngularGradient(colors: [DS.accent.opacity(0.7), DS.accent], center: .center,
                                                startAngle: .zero, endAngle: .degrees(360 * max(progress, 0.01))),
                                style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text(String(format: "%.1f", Fmt.distanceValue(km))).font(.title3.bold()).monospacedDigit()
                            .contentTransition(.numericText())
                        Text("of \(Int(Fmt.distanceValue(target))) \(Fmt.distanceLabel)").font(.caption2).foregroundStyle(.secondary)
                    }
                    if progress >= 1 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3).foregroundStyle(.white, .green)
                            .offset(x: 30, y: -30)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 86, height: 86)
                .animation(.spring(response: 0.9, dampingFraction: 0.8), value: appeared)
                .animation(.easeOut, value: progress)
                .onAppear { appeared = true }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Weekly distance goal, \(Int(progress * 100)) percent complete")

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("This week").font(.headline)
                        Spacer()
                        if streak > 0 {
                            Label("\(streak)-week streak", systemImage: "flame.fill")
                                .font(.caption.bold()).foregroundStyle(DS.accent)
                                .symbolEffect(.bounce, value: appeared)
                        }
                    }
                    Text("\(thisWeek.count) activit\(thisWeek.count == 1 ? "y" : "ies") · \(Fmt.hoursMinutes(time))")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            let day = cal.date(byAdding: .day, value: i, to: week.start)!
                            let dayActs = thisWeek.filter { cal.isDate($0.start, inSameDayAs: day) }
                            Button {
                                if let a = dayActs.first { onOpen(a) }
                            } label: {
                                VStack(spacing: 3) {
                                    ZStack {
                                        Circle()
                                            .fill(dayActs.first.map { $0.sport.color.gradient } ?? Color(.tertiarySystemFill).gradient)
                                        if let a = dayActs.first {
                                            Image(systemName: a.sport.icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                        }
                                    }
                                    .frame(width: 20, height: 20)
                                    .overlay { if cal.isDateInToday(day) { Circle().stroke(Color.primary.opacity(0.6), lineWidth: 1.5).padding(-3) } }
                                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2)
                                        .fontWeight(cal.isDateInToday(day) ? .bold : .regular)
                                        .foregroundStyle(cal.isDateInToday(day) ? .primary : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PressableStyle(scale: 0.85))
                            .disabled(dayActs.isEmpty)
                            .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))), \(dayActs.isEmpty ? "no activity" : dayActs.map(\.name).joined(separator: ", "))")
                        }
                    }
                }
            }
            if let range {
                LoadRangeBar(value: load, range: range).accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }

    private var streak: Int {
        let cal = Calendar.current
        let weeks = Set(activities.compactMap { cal.dateInterval(of: .weekOfYear, for: $0.start)?.start })
        var cursor = cal.dateInterval(of: .weekOfYear, for: .now)!.start
        if !weeks.contains(cursor) { cursor = cal.date(byAdding: .weekOfYear, value: -1, to: cursor)! }
        var count = 0
        while weeks.contains(cursor) {
            count += 1
            cursor = cal.date(byAdding: .weekOfYear, value: -1, to: cursor)!
        }
        return count
    }
}

/// Weekly Relative Effort vs. the typical range from the previous 3 weeks.
enum WeeklyLoad {
    static func range(_ activities: [Activity], before weekStart: Date) -> ClosedRange<Double>? {
        let cal = Calendar.current
        let totals = (1...3).map { i -> Double in
            let s = cal.date(byAdding: .weekOfYear, value: -i, to: weekStart)!
            let e = cal.date(byAdding: .weekOfYear, value: 1, to: s)!
            return activities.filter { $0.start >= s && $0.start < e }.reduce(0) { $0 + $1.relativeEffort }
        }
        let avg = totals.reduce(0, +) / 3
        guard avg > 0 else { return nil }
        return (avg * 0.8)...(avg * 1.25)
    }

    static func status(_ value: Double, _ range: ClosedRange<Double>) -> (String, Color) {
        if value < range.lowerBound { return ("Below your usual load — recovery week", .blue) }
        if value > range.upperBound { return ("Above your usual load — watch fatigue", .orange) }
        return ("Within your usual load — steady", .green)
    }
}

struct LoadRangeBar: View {
    let value: Double
    let range: ClosedRange<Double>

    var body: some View {
        let maxV = max(range.upperBound * 1.5, value * 1.1, 1)
        let (text, color) = WeeklyLoad.status(value, range)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Relative Effort \(Int(value))", systemImage: "heart.fill").font(.caption.weight(.semibold)).foregroundStyle(.red)
                Spacer()
                Text("Usual range \(Int(range.lowerBound))–\(Int(range.upperBound))").font(.caption2).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.inset).frame(height: 8)
                    Capsule().fill(Color.green.opacity(0.35))
                        .frame(width: w * (range.upperBound - range.lowerBound) / maxV, height: 8)
                        .offset(x: w * range.lowerBound / maxV)
                    Circle().fill(color).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                        .offset(x: min(w * value / maxV, w) - 7)
                }
            }
            .frame(height: 14)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct ActivityCard: View {
    let activity: Activity
    var prCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SportIcon(sport: activity.sport, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.name).font(.headline).lineLimit(1)
                    Text(activity.start.formatted(.dateTime.weekday(.wide).day().month().hour().minute()))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if prCount > 0 {
                    MetricPill(icon: "trophy.fill", text: "\(prCount) record\(prCount == 1 ? "" : "s")", tint: Color(red: 0.8, green: 0.6, blue: 0))
                }
            }

            HStack(alignment: .top, spacing: 0) {
                for3Stats
            }

            if activity.hasRoute {
                RouteThumbnail(points: activity.route, color: activity.sport.color)
                    .padding(16)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(colors: [activity.sport.color.opacity(0.12), DS.inset.opacity(0.5)], startPoint: .top, endPoint: .bottom),
                        in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))
            }

            HStack(spacing: 6) {
                if activity.relativeEffort > 0 {
                    MetricPill(icon: "heart.fill", text: "Effort \(Int(activity.relativeEffort))", tint: .red)
                }
                if let rpe = activity.rpe {
                    MetricPill(icon: "gauge.with.dots.needle.50percent", text: "Exertion \(rpe)/10", tint: RPE.color(rpe))
                }
                if let insight = activity.insight {
                    MetricPill(icon: "sparkles", text: insight, tint: .purple)
                }
            }
            .lineLimit(1)
        }
        .padding(16)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DS.Radius.card))
    }

    @ViewBuilder private var for3Stats: some View {
        let a = activity
        if a.distance > 0 { StatTile(label: "Distance", value: Fmt.distanceNumber(a.distance), unit: Fmt.distanceLabel) }
        if a.distance > 0 && a.sport != .swim {
            StatTile(label: a.sport.usesPace ? "Pace" : "Speed",
                     value: Fmt.speedOrPaceNumber(a.avgSpeed, sport: a.sport), unit: Fmt.speedOrPaceUnit(a.sport))
        }
        StatTile(label: "Time", value: Fmt.duration(a.activeTime))
        if a.sport == .hike || a.sport == .ride, a.elevationGain >= 10 {
            StatTile(label: "Elevation", value: String(format: "%.0f", Fmt.elevationValue(a.elevationGain)), unit: Fmt.elevationLabel)
        } else if a.distance == 0, let hr = a.avgHR {
            StatTile(label: "Heart rate", value: String(format: "%.0f", hr), unit: "bpm")
        }
    }
}
