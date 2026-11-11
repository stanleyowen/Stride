import SwiftUI

/// Design tokens. Use these instead of magic numbers.
enum DS {
    enum Space {
        static let xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12, l: CGFloat = 16, xl: CGFloat = 24
    }
    enum Radius {
        static let card: CGFloat = 18, inner: CGFloat = 12, chip: CGFloat = 999
    }
    static let accent = Color.orange
    static let pr = Color.yellow
    static let canvas = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let inset = Color(.tertiarySystemFill)

    static let zoneColors: [Color] = [.gray, .blue, .green, .orange, .red]

    static func gradeColor(_ g: Double) -> Color {
        switch g {
        case ..<(-0.03): .teal
        case ..<0.03: .green
        case ..<0.06: .yellow
        case ..<0.10: .orange
        default: .red
        }
    }

    enum Lane {
        static let pace = Color.orange
        static let gap = Color.purple
        static let heartRate = Color.red
        static let elevation = Color.green
        static let cadence = Color.indigo
        static let power = Color.pink
    }
}

extension Font {
    static let statValue = Font.system(.title3, design: .rounded).weight(.semibold)
    static let heroValue = Font.system(.largeTitle, design: .rounded).weight(.bold)
}
