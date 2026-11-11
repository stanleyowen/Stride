import SwiftUI
import SwiftData

enum GoalPeriod: String, CaseIterable, Identifiable {
    case week, month, year
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var component: Calendar.Component {
        switch self { case .week: .weekOfYear; case .month: .month; case .year: .year }
    }
    var interval: DateInterval { Calendar.current.dateInterval(of: component, for: .now)! }
}

enum GoalMetric: String, CaseIterable, Identifiable {
    case distance, time, elevation, count
    var id: String { rawValue }
    var label: String { self == .count ? "Activities" : rawValue.capitalized }
    var icon: String {
        switch self { case .distance: "arrow.left.and.right"; case .time: "clock"; case .elevation: "mountain.2"; case .count: "number" }
    }

    /// Raw value: meters, seconds, meters, count.
    func value(_ acts: [Activity]) -> Double {
        switch self {
        case .distance: acts.reduce(0) { $0 + $1.distance }
        case .time: acts.reduce(0) { $0 + $1.activeTime }
        case .elevation: acts.reduce(0) { $0 + $1.elevationGain }
        case .count: Double(acts.count)
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .distance: Fmt.distance(v, digits: 1)
        case .time: Fmt.hoursMinutes(v)
        case .elevation: Fmt.elevation(v)
        case .count: String(format: "%.0f", v)
        }
    }

    /// Editing works in display units.
    var displayStep: Double {
        switch self { case .distance: 5; case .time: 1; case .elevation: 100; case .count: 1 }
    }
    var displayUnit: String {
        switch self { case .distance: Fmt.distanceLabel; case .time: "h"; case .elevation: Fmt.elevationLabel; case .count: "" }
    }
    func toDisplay(_ raw: Double) -> Double {
        switch self {
        case .distance: Fmt.distanceValue(raw)
        case .time: raw / 3600
        case .elevation: Fmt.elevationValue(raw)
        case .count: raw
        }
    }
    func fromDisplay(_ v: Double) -> Double {
        switch self {
        case .distance: v * Fmt.distanceUnit
        case .time: v * 3600
        case .elevation: Fmt.imperial ? v / 3.28084 : v
        case .count: v
        }
    }
}

extension Goal {
    var metric: GoalMetric { GoalMetric(rawValue: metricRaw) ?? .distance }
    var period: GoalPeriod { GoalPeriod(rawValue: periodRaw) ?? .week }
    var sport: Sport? { Sport(rawValue: sportRaw) }
    var title: String { "\(period.label)ly \(sport?.label.lowercased() ?? "all-sport") \(metric.label.lowercased())" }

    func progress(_ activities: [Activity]) -> (value: Double, fraction: Double, projected: Double) {
        let iv = period.interval
        let acts = activities.filter { iv.contains($0.start) && (sport == nil || $0.sport == sport) }
        let v = metric.value(acts)
        let elapsed = max(Date.now.timeIntervalSince(iv.start) / iv.duration, 0.02)
        return (v, target > 0 ? v / target : 0, v / elapsed)
    }
}

struct GoalRow: View {
    let goal: Goal
    let activities: [Activity]

    var body: some View {
        let p = goal.progress(activities)
        let color = goal.sport?.color ?? DS.accent
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(color.opacity(0.18), lineWidth: 7)
                Circle().trim(from: 0, to: min(p.fraction, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(min(p.fraction, 9.99) * 100))%").font(.caption2.bold()).monospacedDigit()
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title).font(.subheadline.weight(.semibold))
                Text("\(goal.metric.format(p.value)) of \(goal.metric.format(goal.target))")
                    .font(.caption).foregroundStyle(.secondary)
                Text(p.fraction >= 1 ? "Goal reached 🎉"
                     : p.projected >= goal.target ? "On track · projected \(goal.metric.format(p.projected))"
                     : "Behind · projected \(goal.metric.format(p.projected))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(p.fraction >= 1 || p.projected >= goal.target ? .green : .orange)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

struct GoalEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var sport: Sport? = nil
    @State private var metric: GoalMetric = .distance
    @State private var period: GoalPeriod = .week
    @State private var target: Double = 20

    var body: some View {
        NavigationStack {
            Form {
                Picker("Sport", selection: $sport) {
                    Text("All sports").tag(Sport?.none)
                    ForEach(Sport.allCases) { Label($0.label, systemImage: $0.icon).tag(Sport?.some($0)) }
                }
                Picker("Period", selection: $period) { ForEach(GoalPeriod.allCases) { Text($0.label).tag($0) } }
                Picker("Measure", selection: $metric) { ForEach(GoalMetric.allCases) { Label($0.label, systemImage: $0.icon).tag($0) } }
                Stepper(value: $target, in: metric.displayStep...100_000, step: metric.displayStep) {
                    LabeledContent("Target", value: "\(Int(target)) \(metric.displayUnit)")
                }
            }
            .navigationTitle("New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: metric) { target = defaultTarget }
            .onChange(of: period) { target = defaultTarget }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        context.insert(Goal(sportRaw: sport?.rawValue ?? "", metricRaw: metric.rawValue,
                                            periodRaw: period.rawValue, target: metric.fromDisplay(target)))
                        dismiss()
                    }
                }
            }
        }
    }

    private var defaultTarget: Double {
        let mult: Double = period == .week ? 1 : period == .month ? 4 : 48
        switch metric {
        case .distance: return 20 * mult
        case .time: return 4 * mult
        case .elevation: return 500 * mult
        case .count: return 3 * mult
        }
    }
}
