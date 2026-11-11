import SwiftUI
import SwiftData
import Charts
import StrideCore

struct SplitsTab: View {
    @Bindable var vm: ActivityViewModel
    @State private var useLaps = true
    @State private var selected: Int?

    private var rows: [SplitStats] { useLaps && !vm.laps.isEmpty ? vm.laps : vm.splits }
    private var sport: Sport { vm.sport }

    var body: some View {
        VStack(spacing: 16) {
            if !vm.laps.isEmpty {
                Picker("Type", selection: $useLaps) {
                    Text("Watch laps (\(vm.laps.count))").tag(true)
                    Text("Auto splits").tag(false)
                }
                .pickerStyle(.segmented)
                .onChange(of: useLaps) { selected = nil; vm.highlight = nil }
            }
            if rows.isEmpty {
                EmptyState(icon: "list.number", title: "No splits", message: "Splits need a GPS route.")
            } else {
                chartCard
                tableCard
            }
        }
    }

    private var avgSpeed: Double {
        let full = rows.filter { !$0.isPartial }
        let d = full.reduce(0) { $0 + $1.stats.distance }, t = full.reduce(0) { $0 + $1.stats.duration }
        return t > 0 ? d / t : 0
    }

    private func tint(_ s: SplitStats) -> Color {
        let r = s.stats.speed / max(avgSpeed, 0.01)
        return r > 1.02 ? .green : r < 0.98 ? .red : sport.color
    }

    private var chartCard: some View {
        let speeds = rows.map(\.stats.speed)
        let lo = (speeds.min() ?? 0) * 0.8
        let hi = (speeds.max() ?? 1) * 1.02
        let unitText = useLaps && !vm.laps.isEmpty ? "per lap" : "per \(sport == .ride ? "5 " : "")\(Fmt.distanceLabel)"

        return Card(title: useLaps && !vm.laps.isEmpty ? "Laps" : "Splits", subtitle: "\(unitText.prefix(1).uppercased() + unitText.dropFirst()) · tap a bar", icon: "chart.bar.fill") {
            Chart {
              ForEach(rows) { s in
                BarMark(xStart: .value("Base", lo), xEnd: .value("Speed", s.stats.speed), y: .value("Split", s.label), height: .fixed(22))
                    .foregroundStyle(tint(s).gradient)
                    .opacity(selected == nil || selected == s.id ? 1 : 0.3)
                    .cornerRadius(4)
                    .annotation(position: .overlay, alignment: .leading) {
                        Text("\(s.label)  ·  \(Fmt.speedOrPaceNumber(s.stats.speed, sport: sport))")
                            .font(.caption.bold()).foregroundStyle(.white).padding(.leading, 8)
                    }
              }
                RuleMark(x: .value("Average", avgSpeed))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartXScale(domain: lo...hi)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .onChartTap { proxy, p in
                if let label = proxy.value(atY: p.y, as: String.self), let s = rows.first(where: { $0.label == label }) {
                    select(s)
                }
            }
            .frame(height: CGFloat(rows.count) * 30 + 10)
            HStack(spacing: 12) {
                Label("Faster than average", systemImage: "square.fill").foregroundStyle(.green)
                Label("Slower than average", systemImage: "square.fill").foregroundStyle(.red)
                Label("Average", systemImage: "line.diagonal").foregroundStyle(.secondary)
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }

    private var tableCard: some View {
        let showGAP = sport.usesGAP
        let showHR = rows.contains { $0.stats.avgHR != nil }
        let showCad = rows.contains { $0.stats.avgCadence != nil }

        return Card {
            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 0) {
                GridRow(alignment: .bottom) {
                    Text(useLaps && !vm.laps.isEmpty ? "Lap" : Fmt.distanceLabel)
                        .frame(maxWidth: .infinity, alignment: .leading).gridColumnAlignment(.leading)
                    Text(sport.usesPace ? "Pace" : "Speed")
                    if showGAP { Text("Grade-\nadjusted") }
                    if showHR { Text("Heart\nrate") }
                    Text("Elevation")
                    if showCad { Text("Cadence") }
                }
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .padding(.bottom, 6)

                ForEach(rows) { s in
                    Divider().gridCellUnsizedAxes(.horizontal)
                    GridRow {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2).fill(tint(s)).frame(width: 4, height: 18)
                            Text(s.label).font(.subheadline.weight(.semibold))
                        }
                        .gridColumnAlignment(.leading)
                        Text(Fmt.speedOrPaceNumber(s.stats.speed, sport: sport))
                        if showGAP { Text(Fmt.speedOrPaceNumber(s.stats.gapSpeed, sport: sport)).foregroundStyle(DS.Lane.gap) }
                        if showHR { Text(s.stats.avgHR.map { String(format: "%.0f", $0) } ?? "–") }
                        Text({ let e = Fmt.elevationValue(s.stats.elevationDelta).rounded(); return e == 0 ? "0" : String(format: "%+.0f", e) }())
                            .foregroundStyle(s.stats.elevationDelta > 2 ? .orange : s.stats.elevationDelta < -2 ? .teal : .secondary)
                        if showCad { Text(s.stats.avgCadence.map { String(format: "%.0f", $0) } ?? "–") }
                    }
                    .font(.subheadline).monospacedDigit()
                    .padding(.vertical, 9)
                    .background(selected == s.id ? DS.accent.opacity(0.12) : .clear)
                    .contentShape(Rectangle())
                    .onTapGesture { select(s) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)

                    if selected == s.id {
                        GridRow {
                            HStack {
                                Text("\(Fmt.distance(s.stats.distance)) in \(Fmt.duration(s.stats.duration))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { vm.focus(on: s) } label: {
                                    Label("Analyze", systemImage: "waveform.path.ecg")
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .gridCellColumns(6)
                        }
                        .padding(.bottom, 8)
                    }
                }
            }
        }
    }

    private func select(_ s: SplitStats) {
        withAnimation(.snappy) {
            if selected == s.id {
                selected = nil
                vm.highlight = nil
            } else {
                selected = s.id
                vm.rangeX = nil
                vm.highlight = (s.startIndex...max(s.endIndex, s.startIndex), "\(useLaps && !vm.laps.isEmpty ? "Lap" : "Split") \(s.label)")
            }
        }
    }
}
