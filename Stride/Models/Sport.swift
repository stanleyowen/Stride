import SwiftUI
import HealthKit
import StrideCore

enum Sport: String, CaseIterable, Identifiable, Codable {
    case run, ride, walk, hike, swim, workout

    var id: String { rawValue }

    init(_ type: HKWorkoutActivityType) {
        switch type {
        case .running: self = .run
        case .cycling, .handCycling: self = .ride
        case .walking: self = .walk
        case .hiking: self = .hike
        case .swimming: self = .swim
        default: self = .workout
        }
    }

    var label: String {
        switch self {
        case .run: "Run"
        case .ride: "Ride"
        case .walk: "Walk"
        case .hike: "Hike"
        case .swim: "Swim"
        case .workout: "Workout"
        }
    }

    var icon: String {
        switch self {
        case .run: "figure.run"
        case .ride: "figure.outdoor.cycle"
        case .walk: "figure.walk"
        case .hike: "figure.hiking"
        case .swim: "figure.pool.swim"
        case .workout: "figure.mixed.cardio"
        }
    }

    var color: Color {
        switch self {
        case .run: .orange
        case .ride: .blue
        case .walk: .green
        case .hike: .brown
        case .swim: .cyan
        case .workout: .pink
        }
    }

    var gpxType: String {
        switch self {
        case .run: "running"
        case .ride: "cycling"
        case .walk: "walking"
        case .hike: "hiking"
        case .swim: "swimming"
        case .workout: "other"
        }
    }

    /// Runners think in pace, cyclists in speed.
    var usesPace: Bool { self != .ride }
    /// Grade-adjusted pace only makes sense on foot.
    var usesGAP: Bool { self == .run || self == .walk || self == .hike }
    /// Slowest pace (min per km) worth plotting; slower is treated as stopped.
    var paceCapMinPerKm: Double { self == .run ? 12 : 25 }
    /// Speed below which GPS movement counts as stopped (m/s).
    var movingThreshold: Double { self == .ride ? 1.0 : 0.5 }
    var gearKind: String { self == .ride ? "bike" : "shoes" }

    var effortTargets: [Double] {
        switch self {
        case .run: [400, 1000, 1609.34, 5000, 10000, 21097.5, 42195]
        case .ride: [5000, 10000, 20000, 40000, 100000]
        case .walk, .hike: [1000, 5000, 10000]
        case .swim, .workout: []
        }
    }

    static func effortLabel(_ meters: Double) -> String {
        switch Int(meters) {
        case 1609: "1 mile"
        case 21097: "Half Marathon"
        case 42195: "Marathon"
        case ..<1000: "\(Int(meters)) m"
        default: "\(Int(meters) / 1000) km"
        }
    }
}
