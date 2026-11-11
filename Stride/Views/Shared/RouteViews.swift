import SwiftUI
import SwiftData
import MapKit
import StrideCore

/// Lightweight route thumbnail (no MapKit in lists).
struct RouteShape: Shape {
    let points: [RoutePoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (i, pt) in Self.project(points, in: rect).enumerated() {
            i == 0 ? path.move(to: pt) : path.addLine(to: pt)
        }
        return path
    }

    /// Route points fitted into `rect`, keeping the aspect ratio.
    static func project(_ points: [RoutePoint], in rect: CGRect) -> [CGPoint] {
        guard points.count > 1 else { return [] }
        let pts = Geo.simplify(points, max: 200)
        let lats = pts.map(\.lat), lons = pts.map(\.lon)
        let minLat = lats.min()!, maxLat = lats.max()!, minLon = lons.min()!, maxLon = lons.max()!
        let k = cos(((minLat + maxLat) / 2) * .pi / 180)
        let w = max((maxLon - minLon) * k, 1e-9), h = max(maxLat - minLat, 1e-9)
        let scale = min(rect.width / w, rect.height / h)
        let ox = rect.minX + (rect.width - w * scale) / 2, oy = rect.minY + (rect.height - h * scale) / 2
        return pts.map { CGPoint(x: ox + ($0.lon - minLon) * k * scale, y: oy + (maxLat - $0.lat) * scale) }
    }
}

/// Route drawing for cards: soft glow, the line, and start/finish dots.
struct RouteThumbnail: View {
    let points: [RoutePoint]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let ends = RouteShape.project(points, in: rect)
            ZStack {
                RouteShape(points: points)
                    .stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    .blur(radius: 3)
                RouteShape(points: points)
                    .stroke(color.gradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                if let first = ends.first, let last = ends.last {
                    dot(.green).position(first)
                    dot(.red).position(last)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func dot(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 9, height: 9)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 1.5)
    }
}

struct RouteMapView: View {
    let points: [RoutePoint]
    let color: Color
    var highlight: ClosedRange<Int>? = nil
    var marker: CLLocationCoordinate2D? = nil
    var interactive = true

    var body: some View {
        let coords = Geo.simplify(points, max: 1500).map(\.coordinate)
        let full = points.map(\.coordinate)
        Map(initialPosition: .rect(Self.fittingRect(coords)), interactionModes: interactive ? .all : []) {
            MapPolyline(coordinates: coords)
                .stroke(highlight == nil ? color : color.opacity(0.4),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            if let h = highlight, h.lowerBound >= 0, h.upperBound < full.count, h.count > 1 {
                MapPolyline(coordinates: Array(full[h]))
                    .stroke(.yellow, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            }
            if let first = coords.first {
                Annotation("Start", coordinate: first) { endpoint(.green) }.annotationTitles(.hidden)
            }
            if let last = coords.last {
                Annotation("Finish", coordinate: last) { endpoint(.red) }.annotationTitles(.hidden)
            }
            if let marker {
                Annotation("Position", coordinate: marker) {
                    Circle().fill(.white).frame(width: 18, height: 18)
                        .overlay(Circle().fill(color).padding(4))
                        .shadow(radius: 3)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    private func endpoint(_ c: Color) -> some View {
        Circle().fill(c).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 2))
    }

    static func fittingRect(_ coords: [CLLocationCoordinate2D]) -> MKMapRect {
        let rect = coords.reduce(MKMapRect.null) { r, c in
            r.union(MKMapRect(origin: MKMapPoint(c), size: MKMapSize(width: 0, height: 0)))
        }
        guard !rect.isNull else { return MKMapRect.world }
        return rect.insetBy(dx: -rect.width * 0.15 - 150, dy: -rect.height * 0.15 - 150)
    }
}

/// Full-screen interactive map.
struct FullMapSheet: View {
    let title: String
    let points: [RoutePoint]
    let color: Color
    var highlight: ClosedRange<Int>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            RouteMapView(points: points, color: color, highlight: highlight)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Registers the navigation destinations shared by every tab.
struct StrideDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: Activity.self) { ActivityDetailView(activity: $0) }
            .navigationDestination(for: SegmentRoute.self) { SegmentLoader(id: $0.id) }
            .navigationDestination(for: EffortKey.self) { EffortHistoryView(key: $0) }
    }
}

extension View {
    func strideDestinations() -> some View { modifier(StrideDestinations()) }
}

/// Hashable navigation value for a segment (works around a macro-conformance visibility issue).
struct SegmentRoute: Hashable {
    let id: PersistentIdentifier
}

struct SegmentLoader: View {
    let id: PersistentIdentifier
    @Environment(\.modelContext) private var context

    var body: some View {
        if let seg = context.model(for: id) as? Segment, !seg.isDeleted {
            SegmentDetailView(segment: seg)
        } else {
            EmptyState(icon: "flag.slash", title: "Segment not found", message: "It may have been deleted.")
        }
    }
}
