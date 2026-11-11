import SwiftUI
import SwiftData
import StrideCore

struct EffortsTab: View {
    let activity: Activity
    @Bindable var vm: ActivityViewModel
    let book: RecordBook
    let scrollToTop: () -> Void

    var body: some View {
        let sport = activity.sport
        VStack(spacing: 16) {
            if activity.efforts.isEmpty && activity.segmentEfforts.isEmpty {
                EmptyState(icon: "trophy", title: "No efforts yet",
                           message: "Best efforts are found automatically in GPS activities. Select a stretch in Analysis to create a segment.")
            }

            if !activity.efforts.isEmpty {
                Card(title: "Best Efforts", subtitle: "Tap to show on the map", icon: "stopwatch") {
                    VStack(spacing: 0) {
                        ForEach(activity.efforts, id: \.distance) { e in
                            let rank = book.rank(of: activity, distance: e.distance)
                            let yr = book.yearRank(of: activity, distance: e.distance)
                            let on = vm.highlight?.label == "Best \(Sport.effortLabel(e.distance))"
                            Button {
                                vm.rangeX = nil
                                vm.highlight = on ? nil : (e.startIndex...e.endIndex, "Best \(Sport.effortLabel(e.distance))")
                                if !on { scrollToTop() }
                            } label: {
                                HStack(spacing: 10) {
                                    MedalView(rank: rank)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(Sport.effortLabel(e.distance)).font(.subheadline.weight(.semibold))
                                        Text(rankText(rank, yr)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 1) {
                                        Text(Fmt.duration(e.duration)).font(.subheadline.bold()).monospacedDigit()
                                        Text(Fmt.speedOrPace(e.speed, sport: sport)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Image(systemName: on ? "map.fill" : "map").foregroundStyle(on ? Color.yellow : Color.secondary)
                                }
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if e.distance != activity.efforts.last?.distance { Divider() }
                        }
                    }
                }
            }

            if !activity.segmentEfforts.isEmpty {
                Card(title: "Segments", icon: "flag.checkered", tint: .green) {
                    VStack(spacing: 0) {
                        ForEach(activity.segmentEfforts.sorted { $0.startDate < $1.startDate }) { e in
                            SegmentEffortRow(effort: e) { vm.highlight = (e.startIndex...e.endIndex, e.segment?.name ?? "Segment") }
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func rankText(_ rank: Int?, _ year: Int?) -> String {
        switch (rank, year) {
        case (1, _): "Personal record"
        case (2, _): "Second best ever"
        case (3, _): "Third best ever"
        case (_, 1): "Best this year"
        case (let r?, _): "\(Fmt.ordinal(r)) best all-time"
        default: ""
        }
    }
}

struct SegmentEffortRow: View {
    let effort: SegmentEffort
    let onTap: () -> Void

    var body: some View {
        if let seg = effort.segment {
            let ranked = seg.ranked
            let rank = (ranked.firstIndex { $0.persistentModelID == effort.persistentModelID } ?? 0) + 1
            NavigationLink(value: SegmentRoute(id: seg.persistentModelID)) {
                HStack(spacing: 10) {
                    MedalView(rank: rank)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(seg.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(Fmt.ordinal(rank)) of \(ranked.count) · \(Fmt.distance(seg.distance))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.duration(effort.duration)).font(.subheadline.bold()).monospacedDigit()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded(onTap))
        }
    }
}
