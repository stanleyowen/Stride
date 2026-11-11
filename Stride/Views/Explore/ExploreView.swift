import SwiftUI
import SwiftData
import MapKit
import StrideCore

struct ExploreView: View {
    enum Mode: String, CaseIterable { case heatmap = "Heatmap", segments = "Segments" }
    @State private var mode: Mode = .heatmap

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) { ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .padding(.horizontal).padding(.vertical, 8)
                switch mode {
                case .heatmap: HeatmapView()
                case .segments: SegmentListView()
                }
            }
            .background(DS.canvas)
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
            .strideDestinations()
        }
    }
}

struct HeatmapView: View {
    @Query(sort: \Activity.start, order: .reverse) private var all: [Activity]
    @State private var sport: Sport?
    @State private var days = 0     // 0 = all time

    var body: some View {
        let cutoff = days == 0 ? Date.distantPast : Calendar.current.date(byAdding: .day, value: -days, to: .now)!
        let shown = all.filter { $0.hasRoute && $0.start >= cutoff && (sport == nil || $0.sport == sport) }
        let lines = shown.map { a in (id: a.healthID, color: a.sport.color, coords: Geo.simplify(a.route, max: 150).map(\.coordinate)) }
        let allCoords = lines.flatMap(\.coords)

        ZStack(alignment: .bottom) {
            if shown.isEmpty {
                EmptyState(icon: "map", title: "No routes", message: "Activities with GPS appear here as a personal heatmap.")
            } else {
                Map(initialPosition: .rect(RouteMapView.fittingRect(allCoords))) {
                    ForEach(lines, id: \.id) { l in
                        MapPolyline(coordinates: l.coords)
                            .stroke(l.color.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .id("\(sport?.rawValue ?? "all")-\(days)")
            }
            VStack(spacing: 8) {
                HStack {
                    Text("\(shown.count) activit\(shown.count == 1 ? "y" : "ies") · \(Fmt.distance(shown.reduce(0) { $0 + $1.distance }, digits: 0))")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Menu {
                        Picker("Period", selection: $days) {
                            Text("All time").tag(0); Text("Past year").tag(365); Text("90 days").tag(90); Text("30 days").tag(30)
                        }
                    } label: {
                        Label(days == 0 ? "All time" : "\(days) days", systemImage: "calendar").font(.caption.weight(.semibold))
                    }
                }
                SportFilterBar(sports: Sport.allCases.filter { s in all.contains { $0.sport == s && $0.hasRoute } }, selection: $sport)
                    .padding(.horizontal, -16)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .padding()
        }
    }
}

struct SegmentListView: View {
    @Query(sort: \Segment.createdAt, order: .reverse) private var segments: [Segment]
    @Environment(\.modelContext) private var context

    var body: some View {
        if segments.isEmpty {
            EmptyState(icon: "flag.checkered", title: "No segments yet",
                       message: "Open an activity → Analysis, select a stretch with two fingers, then tap “Save as segment”. Stride finds it in every past and future activity and ranks your efforts.")
        } else {
            List {
                ForEach(segments) { s in
                    let pr = s.ranked.first
                    NavigationLink(value: SegmentRoute(id: s.persistentModelID)) {
                        HStack(spacing: 12) {
                            RouteShape(points: s.points)
                                .stroke(s.sport.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                                .frame(width: 54, height: 40)
                                .padding(6)
                                .background(DS.inset, in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.subheadline.weight(.semibold))
                                Text("\(Fmt.distance(s.distance)) · \(Fmt.elevation(s.elevationGain)) · \(s.efforts.count) efforts")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let pr {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(Fmt.duration(pr.duration)).font(.subheadline.bold()).monospacedDigit()
                                    Text("Record").font(.caption2.bold()).foregroundStyle(DS.pr)
                                }
                            }
                        }
                    }
                }
                .onDelete { $0.forEach { context.delete(segments[$0]) } }
            }
            .scrollContentBackground(.hidden)
        }
    }
}

struct SegmentDetailView: View {
    @Bindable var segment: Segment
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let s = segment
        let pts = s.points
        let grade = s.distance > 0 ? ((pts.last?.alt ?? 0) - (pts.first?.alt ?? 0)) / s.distance * 100 : 0
        let attempts = s.efforts.compactMap { e in
            e.activity.map { Attempt(id: e.persistentModelID, activity: $0, date: e.startDate, duration: e.duration, distance: s.distance) }
        }

        ScrollView {
            VStack(spacing: 16) {
                RouteMapView(points: pts, color: s.sport.color, interactive: false)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                Card {
                    HStack(spacing: 0) {
                        StatTile(label: "Distance", value: Fmt.distanceNumber(s.distance), unit: Fmt.distanceLabel)
                        StatTile(label: "Elevation gain", value: String(format: "%.0f", Fmt.elevationValue(s.elevationGain)), unit: Fmt.elevationLabel)
                        StatTile(label: "Average grade", value: String(format: "%.1f", grade), unit: "%")
                    }
                }
                if attempts.isEmpty {
                    EmptyState(icon: "flag", title: "No efforts", message: "None of your activities cover this segment yet.")
                } else {
                    AttemptHistory(attempts: attempts, sport: s.sport)
                }
                Button {
                    Maintenance.matchAll(s, in: context)
                } label: {
                    Label("Rescan all activities", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .background(DS.canvas)
        .navigationTitle(s.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { newName = s.name; renaming = true } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { context.delete(s) }
                    } label: { Label("Delete segment", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .alert("Rename segment", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Save") { segment.name = newName }
            Button("Cancel", role: .cancel) {}
        }
    }
}
