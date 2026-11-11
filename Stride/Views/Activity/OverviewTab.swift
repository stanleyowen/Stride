import SwiftUI
import SwiftData
import Charts
import StrideCore

struct OverviewTab: View {
    @Bindable var activity: Activity
    let vm: ActivityViewModel
    @Query(sort: \Activity.start) private var all: [Activity]
    @Query private var gear: [Gear]
    @State private var selectedZone: Int?

    var body: some View {
        VStack(spacing: 16) {
            statsCard
            if activity.relativeEffort > 0 { effortCard }
            if !vm.insights.isEmpty { insightsCard }
            feelCard
            gearCard
            notesCard
        }
    }

    // MARK: Stats

    /// One figure in the stats card. `lane` is the Analysis chart it opens, if any.
    private struct Stat: Identifiable {
        let label: String
        let value: String
        var unit: String? = nil
        var lane: LaneKind? = nil
        var id: String { label }
    }

    private var headline: [Stat] {
        let s = activity.sport
        var out: [Stat] = []
        if activity.distance > 0 {
            out.append(Stat(label: "Distance", value: Fmt.distanceNumber(activity.distance), unit: Fmt.distanceLabel))
        }
        out.append(Stat(label: "Moving time", value: Fmt.duration(activity.activeTime)))
        if activity.distance > 0 {
            out.append(Stat(label: s.usesPace ? "Average pace" : "Average speed",
                            value: Fmt.speedOrPaceNumber(activity.avgSpeed, sport: s), unit: Fmt.speedOrPaceUnit(s)))
        } else if let hr = activity.avgHR {
            out.append(Stat(label: "Heart rate", value: String(format: "%.0f", hr), unit: "bpm"))
        }
        return out
    }

    private var details: [Stat] {
        let s = activity.sport
        let o = vm.analysis?.overall
        var out: [Stat] = []
        if activity.movingTime > 0 && activity.duration - activity.movingTime > 30 {
            out.append(Stat(label: "Elapsed time", value: Fmt.duration(activity.duration)))
        }
        if s.usesGAP, let o, o.gapSpeed > 0, activity.elevationGain >= 10 {
            let gap = o.gapDistance / max(activity.activeTime, 1)
            out.append(Stat(label: "Grade-adjusted pace", value: Fmt.speedOrPaceNumber(gap, sport: s), unit: Fmt.speedOrPaceUnit(s), lane: .pace))
        }
        if activity.hasRoute {
            out.append(Stat(label: "Elevation gain", value: String(format: "%.0f", Fmt.elevationValue(activity.elevationGain)),
                            unit: Fmt.elevationLabel, lane: .elevation))
        }
        if let hr = activity.avgHR, activity.distance > 0 {
            out.append(Stat(label: "Average heart rate", value: String(format: "%.0f", hr), unit: "bpm", lane: .heartRate))
        }
        if let hr = activity.maxHR { out.append(Stat(label: "Maximum heart rate", value: String(format: "%.0f", hr), unit: "bpm", lane: .heartRate)) }
        if let c = activity.avgCadence { out.append(Stat(label: "Cadence", value: String(format: "%.0f", c), unit: Fmt.cadenceUnit(s), lane: .cadence)) }
        if let p = activity.avgPower { out.append(Stat(label: "Power", value: String(format: "%.0f", p), unit: "W", lane: .power)) }
        if activity.energy > 0 { out.append(Stat(label: "Calories", value: String(format: "%.0f", activity.energy), unit: "kcal")) }
        if let h = activity.humidity { out.append(Stat(label: "Humidity", value: String(format: "%.0f", h), unit: "%")) }
        return out
    }

    private var statsCard: some View {
        let detail = details
        return Card {
            HStack(alignment: .top, spacing: 0) {
                ForEach(headline) { StatTile(label: $0.label, value: $0.value, unit: $0.unit, large: true) }
            }
            if !detail.isEmpty {
                Divider().padding(.vertical, 2)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12, alignment: .leading),
                                    GridItem(.flexible(), spacing: 12, alignment: .leading)], spacing: 8) {
                    ForEach(detail) { detailTile($0) }
                }
                if detail.contains(where: { $0.lane != nil && vm.lanes[$0.lane!] != nil }) {
                    TapHint(text: "Tap a metric to open its chart")
                }
            }
        }
    }

    @ViewBuilder private func detailTile(_ stat: Stat) -> some View {
        let tile = HStack {
            StatTile(label: stat.label, value: stat.value, unit: stat.unit)
            if let lane = stat.lane, vm.lanes[lane] != nil {
                Image(systemName: "chevron.right").font(.caption2.bold()).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(DS.inset.opacity(0.5), in: RoundedRectangle(cornerRadius: DS.Radius.inner, style: .continuous))

        if let lane = stat.lane, vm.lanes[lane] != nil {
            Button {
                withAnimation(.snappy) { vm.tab = .analysis }
            } label: { tile.contentShape(Rectangle()) }
            .buttonStyle(.pressable)
            .accessibilityHint("Opens the \(LaneStyle.name(lane, activity.sport).lowercased()) chart")
        } else {
            tile
        }
    }

    // MARK: Relative effort

    private var effortCard: some View {
        let cal = Calendar.current
        let week = cal.dateInterval(of: .weekOfYear, for: activity.start)!
        let weekLoad = all.filter { week.contains($0.start) && $0.start <= activity.start }.reduce(0) { $0 + $1.relativeEffort }
        let range = WeeklyLoad.range(all, before: week.start)
        let tiz = vm.timeInZones
        let total = max(tiz.reduce(0, +), 1)
        let score = activity.relativeEffort
        let level = score < 50 ? "Easy" : score < 100 ? "Moderate" : score < 200 ? "Hard" : score < 300 ? "Very hard" : "Massive"

        return Card(title: "Relative Effort",
                    subtitle: activity.heartRates.count > 5 ? "From heart rate" : "Estimated from perceived exertion and time",
                    icon: "heart.fill", tint: .red) {
            HStack(alignment: .center, spacing: 16) {
                Gauge(value: min(score, 300), in: 0...300) {
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int(score))").font(.title2.bold()).monospacedDigit()
                }
                .gaugeStyle(.accessoryCircular)
                .tint(Gradient(colors: [.green, .yellow, .orange, .red]))
                .scaleEffect(1.4)
                .frame(width: 80, height: 80)

                VStack(alignment: .leading, spacing: 4) {
                    Text(level).font(.headline)
                    Text("This week so far: \(Int(weekLoad))").font(.subheadline).foregroundStyle(.secondary)
                    if let range {
                        Text(WeeklyLoad.status(weekLoad, range).0).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if !tiz.isEmpty {
                VStack(spacing: 4) {
                    ForEach((0..<5).reversed(), id: \.self) { z in
                        zoneRow(z, time: tiz[z], share: tiz[z] / total)
                    }
                }
                .sensoryFeedback(.selection, trigger: selectedZone)
                if let z = selectedZone {
                    let r = vm.zones.range(of: z)
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(DS.zoneColors[z]).frame(width: 4, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Zone \(z + 1) · \(HeartZones.names[z])").font(.subheadline.weight(.semibold))
                            Text("\(Int(r.lowerBound))–\(Int(r.upperBound)) bpm · \(Int((tiz[z] / total * 100).rounded()))% of the activity")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    TapHint(text: "Tap a zone for details")
                }
            }
        }
    }

    private func zoneRow(_ z: Int, time: TimeInterval, share: Double) -> some View {
        let isSel = selectedZone == z
        return Button {
            withAnimation(.snappy) { selectedZone = isSel ? nil : z }
        } label: {
            HStack(spacing: 8) {
                Text("Zone \(z + 1)").font(.caption.bold()).frame(width: 52, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(DS.inset)
                        Capsule().fill(DS.zoneColors[z].gradient)
                            .frame(width: max(4, geo.size.width * share))
                    }
                }
                .frame(height: isSel ? 14 : 10)
                Text(Fmt.hoursMinutes(time)).font(.caption2).monospacedDigit()
                    .foregroundStyle(isSel ? .primary : .secondary).frame(width: 64, alignment: .trailing)
            }
            .padding(.vertical, 3).padding(.horizontal, 6)
            .background(isSel ? DS.zoneColors[z].opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
            .opacity(selectedZone == nil || isSel ? 1 : 0.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zone \(z + 1), \(HeartZones.names[z]): \(Fmt.hoursMinutes(time))")
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }

    // MARK: Insights

    private var insightsCard: some View {
        Card(title: "Insights", icon: "sparkles", tint: .purple) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(vm.insights) { i in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: i.icon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(i.tint)
                            .frame(width: 34, height: 34)
                            .background(i.tint.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(i.title).font(.subheadline.weight(.semibold))
                            Text(i.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Feel

    private static let feelings = [("😫", "Terrible"), ("😕", "Bad"), ("😐", "Okay"), ("🙂", "Good"), ("🤩", "Great")]

    private var feelCard: some View {
        Card(title: "How did it feel?", icon: "face.smiling", tint: .yellow) {
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { f in
                    let on = activity.feel == f
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) {
                            activity.feel = on ? nil : f
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(Self.feelings[f - 1].0)
                                .font(.title)
                                .scaleEffect(on ? 1.2 : 1)
                                .grayscale(activity.feel == nil || on ? 0 : 0.8)
                                .opacity(activity.feel == nil || on ? 1 : 0.5)
                            Text(Self.feelings[f - 1].1)
                                .font(.caption2.weight(on ? .semibold : .regular))
                                .foregroundStyle(on ? .primary : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(on ? DS.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.feelings[f - 1].1)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: activity.feel)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Perceived exertion").font(.subheadline)
                    Spacer()
                    Text(activity.rpe.map { "\($0)/10 · \(RPE.label($0))" } ?? "Not set")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(activity.rpe.map { RPE.color($0) } ?? .secondary)
                        .contentTransition(.numericText())
                }
                HStack(spacing: 4) {
                    ForEach(1...10, id: \.self) { v in
                        let filled = (activity.rpe ?? 0) >= v
                        Button {
                            withAnimation(.snappy) { activity.rpe = activity.rpe == v ? nil : v }
                            if activity.heartRates.count <= 5 { activity.recomputeDerived(profile: Profile.zones) }
                        } label: {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(filled ? AnyShapeStyle(RPE.color(v).gradient) : AnyShapeStyle(DS.inset))
                                .frame(height: activity.rpe == v ? 32 : 26)
                                .overlay(Text("\(v)").font(.caption2.bold()).foregroundStyle(filled ? .white : .secondary))
                                .frame(height: 32, alignment: .bottom)
                        }
                        .buttonStyle(PressableStyle(scale: 0.85))
                        .accessibilityLabel("Exertion \(v) of 10, \(RPE.label(v))")
                    }
                }
                .sensoryFeedback(.selection, trigger: activity.rpe)
                HStack {
                    Text("Easy"); Spacer(); Text("Max effort")
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Gear & notes

    @ViewBuilder private var gearCard: some View {
        let options = gear.filter { !$0.retired && $0.kindRaw == activity.sport.gearKind }
        if !options.isEmpty || activity.gear != nil {
            Card {
                HStack(spacing: 10) {
                    IconBadge(icon: activity.sport == .ride ? "bicycle" : "shoeprints.fill", tint: .teal)
                    Text(activity.sport == .ride ? "Bike" : "Shoes").font(.headline)
                    Spacer()
                    Menu {
                        Button("None") { activity.gear = nil }
                        ForEach(options) { g in Button(g.name) { activity.gear = g } }
                    } label: {
                        HStack(spacing: 4) {
                            Text(activity.gear?.name ?? "Choose")
                            Image(systemName: "chevron.up.chevron.down").font(.caption2)
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private var notesCard: some View {
        Card(title: "Notes", icon: "note.text", tint: .gray) {
            TextField("Add a private note…", text: $activity.notes, axis: .vertical)
                .lineLimit(2...8)
        }
    }
}
