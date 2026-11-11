import SwiftUI
import SwiftData
import Charts
import StrideCore

struct AnalysisTab: View {
    @Bindable var vm: ActivityViewModel
    let scrollToTop: () -> Void
    @AppStorage(Keys.analysisLanes) private var laneSetting = "pace,gap,heartRate,elevation,cadence,power"
    @State private var liveRange: ClosedRange<Double>?
    @State private var savingSegment = false

    private var enabled: Set<String> { Set(laneSetting.split(separator: ",").map(String.init)) }
    private var visible: [LaneKind] { LaneStyle.order.filter { enabled.contains($0.rawValue) && vm.lanes[$0] != nil } }
    private var sport: Sport { vm.sport }

    var body: some View {
        VStack(spacing: 12) {
            controls
            readout
            Card {
                if visible.isEmpty {
                    Text("No chartable data for this activity.").foregroundStyle(.secondary)
                }
                ForEach(Array(visible.enumerated()), id: \.element) { i, kind in
                    LaneChart(kind: kind, vm: vm,
                              showGAP: kind == .pace && enabled.contains(LaneKind.gap.rawValue),
                              isLast: i == visible.count - 1, liveRange: $liveRange)
                    if i < visible.count - 1 { Divider() }
                }
            }
            .onChange(of: liveRange) { _, r in
                if let r, r.upperBound - r.lowerBound > 0.001 { vm.rangeX = r; vm.highlight = nil }
            }
            if let s = vm.rangeStats { rangeCard(s) }
        }
        .sensoryFeedback(.selection, trigger: vm.scrubX.map { Int($0 * 20) })
        .sheet(isPresented: $savingSegment) {
            SaveSegmentSheet(vm: vm)
                .presentationDetents([.medium])
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 10) {
            if vm.analysis?.hasRoute == true {
                Picker("X axis", selection: $vm.axis) {
                    Text("Distance").tag(XAxis.distance)
                    Text("Time").tag(XAxis.time)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
            }
            Spacer()
            HStack(spacing: 0) {
                Button { withAnimation { vm.zoom = max(1, vm.zoom / 2) } } label: { Image(systemName: "minus.magnifyingglass") }
                    .disabled(vm.zoom <= 1)
                Button { withAnimation { vm.zoom = min(8, vm.zoom * 2) } } label: { Image(systemName: "plus.magnifyingglass") }
                    .disabled(vm.zoom >= 8)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Zoom")

            Menu {
                Section("Charts") {
                    ForEach(LaneStyle.order + (sport.usesGAP ? [.gap] : []), id: \.self) { k in
                        if vm.lanes[k] != nil {
                            Toggle(isOn: laneBinding(k)) { Text(k == .gap ? "Grade-adjusted pace (on pace chart)" : LaneStyle.name(k, sport)) }
                        }
                    }
                }
                Section("Compare with") {
                    Button { vm.compare = nil } label: {
                        Label("None", systemImage: vm.compare == nil ? "checkmark" : "")
                    }
                    ForEach(vm.similar.prefix(8)) { other in
                        Button { vm.compare = other } label: {
                            Label("\(other.start.formatted(date: .abbreviated, time: .omitted)) · \(Fmt.duration(other.activeTime))",
                                  systemImage: vm.compare?.healthID == other.healthID ? "checkmark" : "")
                        }
                    }
                    if vm.similar.isEmpty { Text("No other activities on this route yet") }
                }
            } label: {
                Image(systemName: "slider.horizontal.3").padding(6)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Chart options")
        }
    }

    private func laneBinding(_ k: LaneKind) -> Binding<Bool> {
        Binding {
            enabled.contains(k.rawValue)
        } set: { on in
            var s = enabled
            if on { s.insert(k.rawValue) } else { s.remove(k.rawValue) }
            laneSetting = s.sorted().joined(separator: ",")
        }
    }

    // MARK: Readout

    private var readout: some View {
        Group {
            if let x = vm.scrubX, let t = vm.scrubTime, let a = vm.analysis {
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.effectiveAxis == .distance
                         ? String(format: "%.2f %@ · %@", x, vm.xLabel, Fmt.duration(t - a.t0))
                         : "\(Fmt.duration(t - a.t0)) · \(Fmt.distance(a.distance(atTime: t)))")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(visible, id: \.self) { k in
                                if let p = vm.lanes[k]?.nearest(x) {
                                    MetricPill(icon: "circle.fill", text: LaneStyle.format(k, sport, p.y), tint: LaneStyle.color(k, sport))
                                        .contentTransition(.numericText())
                                }
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "hand.draw").foregroundStyle(.secondary)
                    Text(vm.zoom > 1 ? "Drag to pan · long-press to scrub · two fingers to select a range"
                                     : "Drag across a chart to scrub · two fingers to select a range")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .frame(minHeight: 52, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: Range

    private func rangeCard(_ s: RangeStats) -> some View {
        Card(title: "Selection", subtitle: "\(Fmt.distance(s.distance)) · \(Fmt.duration(s.duration))", icon: "selection.pin.in.out") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), spacing: 14) {
                StatTile(label: sport.usesPace ? "Pace" : "Speed", value: Fmt.speedOrPaceNumber(s.speed, sport: sport), unit: Fmt.speedOrPaceUnit(sport))
                if sport.usesGAP { StatTile(label: "Grade-adjusted", value: Fmt.speedOrPaceNumber(s.gapSpeed, sport: sport), unit: Fmt.speedOrPaceUnit(sport)) }
                StatTile(label: "Heart rate", value: s.avgHR.map { String(format: "%.0f", $0) } ?? "–", unit: "bpm")
                StatTile(label: "Elevation gain", value: String(format: "%.0f", Fmt.elevationValue(s.elevationGain)), unit: Fmt.elevationLabel)
                StatTile(label: "Elevation loss", value: String(format: "%.0f", Fmt.elevationValue(s.elevationLoss)), unit: Fmt.elevationLabel)
                if let c = s.avgCadence { StatTile(label: "Cadence", value: String(format: "%.0f", c), unit: Fmt.cadenceUnit(sport)) }
                if let p = s.avgPower { StatTile(label: "Power", value: String(format: "%.0f", p), unit: "W") }
                if s.distance > 0 {
                    StatTile(label: "Grade", value: String(format: "%.1f", s.elevationDelta / s.distance * 100), unit: "%")
                }
            }
            HStack {
                if vm.analysis?.hasRoute == true && s.distance >= 100 {
                    Button { savingSegment = true } label: { Label("Save as segment", systemImage: "flag.checkered") }
                        .buttonStyle(.borderedProminent)
                }
                Button { scrollToTop() } label: { Label("Map", systemImage: "map") }.buttonStyle(.bordered)
                Spacer()
                Button("Clear") { withAnimation { vm.rangeX = nil; liveRange = nil } }.buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

/// One synced analysis lane.
struct LaneChart: View {
    let kind: LaneKind
    @Bindable var vm: ActivityViewModel
    let showGAP: Bool
    let isLast: Bool
    @Binding var liveRange: ClosedRange<Double>?

    /// HR zone bands clipped to the visible data range.
    private func zoneBands(lo: Double, hi: Double) -> [(zone: Int, lo: Double, hi: Double)] {
        (0..<5).compactMap { z in
            let r = vm.zones.range(of: z)
            let a = Swift.max(z == 0 ? lo : r.lowerBound, lo), b = Swift.min(z == 4 ? hi : r.upperBound, hi)
            return b > a ? (z, a, b) : nil
        }
    }

    var body: some View {
        let sport = vm.sport
        let pts = vm.lanes[kind] ?? []
        let gap = showGAP ? vm.lanes[.gap] : nil
        let cmp = vm.compareLanes[kind]
        let color = LaneStyle.color(kind, sport)
        let ys = pts.map(\.y) + (gap?.map(\.y) ?? []) + (cmp?.map(\.y) ?? [])
        let lo = ys.min() ?? 0, hi = ys.max() ?? 1
        let pad = max((hi - lo) * 0.08, 0.5)
        let yBase = lo - pad
        let scrub = vm.scrubX.flatMap { pts.nearest($0) }
        let avg = pts.isEmpty ? 0 : pts.reduce(0) { $0 + $1.y } / Double(pts.count)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(LaneStyle.name(kind, sport)).font(.caption.weight(.semibold))
                if showGAP && gap != nil {
                    Text("· Grade-adjusted").font(.caption.weight(.semibold)).foregroundStyle(DS.Lane.gap)
                }
                if cmp != nil { Text("· compared").font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 4)
                Text(scrub.map { LaneStyle.format(kind, sport, $0.y) } ?? "Average " + LaneStyle.format(kind, sport, avg))
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(scrub == nil ? .secondary : color)
                    .contentTransition(.numericText())
                    .layoutPriority(1)
            }
            .lineLimit(1)

            Chart {
                if kind == .heartRate {
                    ForEach(zoneBands(lo: lo - pad, hi: hi + pad), id: \.zone) { b in
                        RectangleMark(yStart: .value("Lo", b.lo), yEnd: .value("Hi", b.hi))
                            .foregroundStyle(DS.zoneColors[b.zone].opacity(0.08))
                    }
                }
                if let r = vm.rangeX {
                    RectangleMark(xStart: .value("Start", r.lowerBound), xEnd: .value("End", r.upperBound))
                        .foregroundStyle(Color.yellow.opacity(0.18))
                }
                if kind == .elevation {
                    ForEach(pts) { p in
                        AreaMark(x: .value("X", p.x), yStart: .value("Base", yBase), yEnd: .value("Elevation", p.y))
                            .foregroundStyle(LinearGradient(stops: vm.gradeStops.isEmpty ? [.init(color: color, location: 0)] : vm.gradeStops,
                                                            startPoint: .leading, endPoint: .trailing).opacity(0.45))
                    }
                }
                if let cmp {
                    ForEach(cmp) { p in
                        LineMark(x: .value("X", p.x), y: .value("Y", p.y), series: .value("Series", "Compare"))
                            .foregroundStyle(Color.gray.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    }
                }
                if let gap {
                    ForEach(gap) { p in
                        LineMark(x: .value("X", p.x), y: .value("Y", p.y), series: .value("Series", "GAP"))
                            .foregroundStyle(DS.Lane.gap.opacity(0.75))
                            .lineStyle(StrokeStyle(lineWidth: 1.2))
                    }
                }
                ForEach(pts) { p in
                    LineMark(x: .value("X", p.x), y: .value("Y", p.y), series: .value("Series", "Main"))
                        .foregroundStyle(color)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                        .interpolationMethod(.monotone)
                }
                if let s = scrub {
                    RuleMark(x: .value("Scrub", s.x))
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("X", s.x), y: .value("Y", s.y))
                        .foregroundStyle(color)
                        .symbolSize(50)
                }
            }
            .chartXScale(domain: vm.xDomain)
            .chartYScale(domain: .automatic(includesZero: false, reversed: LaneStyle.reversed(kind, sport)))
            .chartXSelection(value: $vm.scrubX)
            .chartXSelection(range: $liveRange)
            .chartScrollableAxes(vm.zoom > 1 ? .horizontal : [])
            .chartXVisibleDomain(length: (vm.xDomain.upperBound - vm.xDomain.lowerBound) / vm.zoom)
            .chartScrollPosition(x: $vm.scrollX)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine()
                    AxisValueLabel { if let d = v.as(Double.self) { Text(LaneStyle.axisLabel(kind, sport, d)).font(.caption2) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { v in
                    AxisGridLine()
                    if isLast {
                        AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%g", (d * 10).rounded() / 10)).font(.caption2) } }
                    }
                }
            }
            .chartXAxisLabel(isLast ? vm.xLabel : "", alignment: .trailing)
            .frame(height: isLast ? 120 : 100)
            .accessibilityChartDescriptor(SeriesChartDescriptor(title: LaneStyle.name(kind, sport), xTitle: vm.xLabel,
                                                                yTitle: LaneStyle.name(kind, sport),
                                                                points: pts.map { (x: $0.x, y: $0.y) }))
        }
    }
}

struct SaveSegmentSheet: View {
    let vm: ActivityViewModel
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Segment name", text: $name)
                } footer: {
                    if let s = vm.rangeStats {
                        Text("\(Fmt.distance(s.distance)) · \(Fmt.elevation(s.elevationGain)) gain. Stride will find this segment in all your past and future \(vm.sport.label.lowercased())s and rank your efforts.")
                    }
                }
            }
            .navigationTitle("New Segment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(); dismiss() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if let s = vm.rangeStats { name = "\(vm.activity.name.components(separatedBy: " ").last ?? "Route") segment \(Fmt.distance(s.distance, digits: 1))" }
            }
        }
    }

    private func save() {
        guard let a = vm.analysis, let rt = vm.rangeTimes else { return }
        let (t1, t2) = rt
        let i = a.index(atTime: t1), j = a.index(atTime: t2)
        guard j > i else { return }
        let pts = Geo.simplify(Array(a.points[i...j]), max: 300)
        guard let data = try? JSONEncoder().encode(pts) else { return }
        let stats = a.stats(from: t1, to: t2)
        let seg = Segment(name: name, sportRaw: vm.sport.rawValue, pointsData: data,
                          distance: stats.distance, elevationGain: stats.elevationGain)
        context.insert(seg)
        Maintenance.matchAll(seg, in: context)
    }
}
