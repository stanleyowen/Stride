import SwiftUI
import Charts
import Accessibility

/// Rounded surface used for every content block.
struct Card<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    var icon: String? = nil
    var tint: Color = DS.accent
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            if let title {
                HStack(alignment: .center, spacing: DS.Space.s + 2) {
                    if let icon { IconBadge(icon: icon, tint: tint) }
                    Text(title).font(.headline)
                    Spacer(minLength: 8)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing).lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surface, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

/// Small tinted rounded square holding an SF Symbol, used in card headers.
struct IconBadge: View {
    let icon: String
    var tint: Color = DS.accent
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Gently shrinks tappable cards and rows while pressed.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

/// A one-line "you can tap this" hint used under interactive charts.
struct TapHint: View {
    let text: String
    var icon = "hand.tap"

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var unit: String? = nil
    var tint: Color = .primary
    var large = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(large ? .heroValue : .statValue)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct MetricPill: View {
    let icon: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }
}

struct SectionHeader: View {
    let title: String
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        HStack {
            Text(title).font(.title3.bold())
            Spacer()
            if let action { Button(action.title, action: action.run).font(.subheadline.weight(.semibold)) }
        }
        .padding(.top, DS.Space.s)
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.borderedProminent)
            }
        }
    }
}

struct MedalView: View {
    let rank: Int?

    var body: some View {
        Group {
            switch rank {
            case 1: Image(systemName: "trophy.fill").foregroundStyle(DS.pr)
            case 2: Image(systemName: "medal.fill").foregroundStyle(.gray)
            case 3: Image(systemName: "medal.fill").foregroundStyle(.brown)
            default: Image(systemName: "circle").hidden()
            }
        }
        .frame(width: 22)
        .accessibilityLabel(rank.map { $0 <= 3 ? "Rank \($0)" : "" } ?? "")
    }
}

struct SportIcon: View {
    let sport: Sport
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: sport.icon)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(sport.color.gradient, in: Circle())
            .accessibilityLabel(sport.label)
    }
}

/// Placeholder shimmer while analysis is computing.
struct SkeletonBlock: View {
    var height: CGFloat = 120
    var body: some View {
        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            .fill(DS.surface)
            .frame(height: height)
            .overlay(ProgressView())
            .redacted(reason: .placeholder)
    }
}

extension View {
    /// Tap anywhere on a chart; the point is relative to the plot area.
    func onChartTap(_ action: @escaping (ChartProxy, CGPoint) -> Void) -> some View {
        chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame else { return }
                        let o = geo[plot].origin
                        action(proxy, CGPoint(x: location.x - o.x, y: location.y - o.y))
                    }
            }
        }
    }
}

/// VoiceOver audio-graph description for a simple series chart.
struct SeriesChartDescriptor: AXChartDescriptorRepresentable {
    let title: String
    let xTitle: String
    let yTitle: String
    let points: [(x: Double, y: Double)]

    func makeChartDescriptor() -> AXChartDescriptor {
        let xs = points.map(\.x), ys = points.map(\.y)
        let xr = (xs.min() ?? 0)...max(xs.max() ?? 1, (xs.min() ?? 0) + 0.001)
        let yr = (ys.min() ?? 0)...max(ys.max() ?? 1, (ys.min() ?? 0) + 0.001)
        let x = AXNumericDataAxisDescriptor(title: xTitle, range: xr, gridlinePositions: []) { String(format: "%.1f", $0) }
        let y = AXNumericDataAxisDescriptor(title: yTitle, range: yr, gridlinePositions: []) { String(format: "%.1f", $0) }
        let series = AXDataSeriesDescriptor(name: title, isContinuous: true,
                                            dataPoints: points.map { AXDataPoint(x: $0.x, y: $0.y) })
        return AXChartDescriptor(title: title, summary: nil, xAxis: x, yAxis: y, additionalAxes: [], series: [series])
    }
}
