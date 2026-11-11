import SwiftUI
import SwiftData
import StrideCore

struct ActivityDetailView: View {
    @Bindable var activity: Activity
    @Query private var peers: [Activity]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(RecordStore.self) private var records
    @State private var vm: ActivityViewModel
    @State private var showFullMap = false
    @State private var confirmDelete = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var showTitle = false

    init(activity: Activity) {
        _activity = Bindable(activity)
        _vm = State(initialValue: ActivityViewModel(activity: activity))
        let sport = activity.sportRaw
        _peers = Query(filter: #Predicate<Activity> { $0.sportRaw == sport })
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ActivityHero(activity: activity, vm: vm) { showFullMap = true }
                        .id("top")
                        .onGeometryChange(for: Bool.self) { $0.frame(in: .scrollView).maxY < 40 } action: { showTitle = $0 }

                    Section {
                        Group {
                            if vm.isLoading {
                                VStack(spacing: 16) { SkeletonBlock(height: 140); SkeletonBlock(height: 220); SkeletonBlock(height: 160) }
                            } else {
                                switch vm.tab {
                                case .overview: OverviewTab(activity: activity, vm: vm)
                                case .analysis: AnalysisTab(vm: vm) { withAnimation { proxy.scrollTo("top", anchor: .top) } }
                                case .splits: SplitsTab(vm: vm)
                                case .efforts:
                                    EffortsTab(activity: activity, vm: vm, book: records.book(peers)) {
                                        withAnimation { proxy.scrollTo("top", anchor: .top) }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    } header: {
                        Picker("Section", selection: $vm.tab) {
                            ForEach(DetailTab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(.bar)
                    }
                }
            }
        }
        .background(DS.canvas)
        .navigationTitle(showTitle ? activity.name : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .task { await vm.load(peers: peers, book: records.book(peers)) }
        .sensoryFeedback(.selection, trigger: vm.tab)
        .fullScreenCover(isPresented: $showFullMap) {
            FullMapSheet(title: activity.name, points: vm.analysis?.points ?? activity.route,
                         color: activity.sport.color, highlight: vm.mapHighlight)
        }
        .alert("Rename activity", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { activity.name = newName }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this activity?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let target = activity
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { context.delete(target) }
            }
        } message: {
            Text("Removes it from Stride only. Apple Health is not changed.")
        }
    }

    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { newName = activity.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                ShareLink(item: shareText) { Label("Share summary", systemImage: "square.and.arrow.up") }
                if activity.hasRoute {
                    ShareLink(item: Exporter.gpx(activity), preview: SharePreview("\(activity.name).gpx")) {
                        Label("Export GPX", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    }
                }
                Divider()
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    private var shareText: String {
        let s = activity.sport
        var parts = ["\(activity.name) — \(Fmt.distance(activity.distance)) in \(Fmt.duration(activity.activeTime))"]
        if activity.distance > 0 { parts.append("\(s.usesPace ? "Pace" : "Speed") \(Fmt.speedOrPace(activity.avgSpeed, sport: s))") }
        if activity.elevationGain >= 10 { parts.append("↑ \(Fmt.elevation(activity.elevationGain))") }
        if activity.relativeEffort > 0 { parts.append("Effort \(Int(activity.relativeEffort))") }
        return parts.joined(separator: " · ")
    }
}

/// Full-bleed map (or sport gradient) with title and conditions overlaid.
struct ActivityHero: View {
    let activity: Activity
    let vm: ActivityViewModel
    let onTapMap: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let a = vm.analysis, a.hasRoute {
                RouteMapView(points: a.points, color: activity.sport.color, highlight: vm.mapHighlight,
                             marker: vm.markerCoordinate, interactive: false)
                    .allowsHitTesting(false)
                    .id(vm.tab == .overview)   // re-fit the route when the hero resizes
            } else if activity.hasRoute {
                DS.inset
            } else {
                LinearGradient(colors: [activity.sport.color, activity.sport.color.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: activity.sport.icon).font(.system(size: 110)).foregroundStyle(.white.opacity(0.18)).padding(24)
                    }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    pill(activity.sport.label, activity.sport.icon)
                    if let t = activity.temperature { pill(Fmt.temperature(t), "thermometer.medium") }
                    if let rpe = activity.rpe { pill("Exertion \(rpe)/10", "gauge.with.dots.needle.50percent") }
                    if let label = vm.mapHighlightLabel { pill(label, "scope").foregroundStyle(.yellow) }
                }
                Text(activity.name).font(.title.bold()).foregroundStyle(.white).lineLimit(2)
                Text([activity.start.formatted(date: .abbreviated, time: .shortened), activity.deviceName].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
        }
        .frame(height: activity.hasRoute ? (vm.tab == .overview ? 340 : 230) : 200)
        .animation(.snappy, value: vm.tab)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { if activity.hasRoute { onTapMap() } }
        .overlay(alignment: .topTrailing) {
            if activity.hasRoute {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.footnote.bold()).padding(9)
                    .background(.ultraThinMaterial, in: Circle())
                    .padding(12)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(activity.hasRoute ? "Double-tap to open the full map" : "")
    }

    private func pill(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
    }
}
