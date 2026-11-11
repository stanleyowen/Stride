import Foundation
import SwiftData

/// The model exactly as shipped before versioning — must not change.
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [Activity.self] }

    @Model
    final class Activity {
        @Attribute(.unique) var healthID: UUID
        var sportRaw: String
        var name: String
        var start: Date
        var duration: TimeInterval
        var distance: Double
        var energy: Double
        var avgHR: Double?
        var maxHR: Double?
        var elevationGain: Double
        var routeData: Data?
        var hrData: Data?
        var notes: String = ""
        var effortsData: Data?

        init(healthID: UUID, sportRaw: String, name: String, start: Date, duration: TimeInterval,
             distance: Double, energy: Double, elevationGain: Double) {
            self.healthID = healthID; self.sportRaw = sportRaw; self.name = name; self.start = start
            self.duration = duration; self.distance = distance; self.energy = energy; self.elevationGain = elevationGain
        }
    }
}

enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Activity.self, Gear.self, Segment.self, SegmentEffort.self, Goal.self]
    }

    @Model
    final class Activity {
        @Attribute(.unique) var healthID: UUID
        var sportRaw: String
        var name: String
        var start: Date
        var duration: TimeInterval        // elapsed
        var distance: Double              // m
        var energy: Double                // kcal
        var avgHR: Double?
        var maxHR: Double?
        var elevationGain: Double
        var routeData: Data?
        var hrData: Data?
        var notes: String = ""
        var effortsData: Data?

        // V2
        var seriesData: Data?             // [String: [TimedValue]]
        var lapsData: Data?               // [TimeRange]
        var pausesData: Data?             // [TimeRange]
        var movingTime: Double = 0
        var temperature: Double?          // °C
        var humidity: Double?             // %
        var deviceName: String?
        var rpe: Int?                     // 1…10
        var feel: Int?                    // 1…5
        var relativeEffort: Double = 0
        var avgCadence: Double?
        var avgPower: Double?
        var insight: String?
        var dataVersion: Int = 0          // what was fetched from Health
        var derivedVersion: Int = 0       // what was computed locally
        var gear: Gear?
        @Relationship(deleteRule: .cascade, inverse: \SegmentEffort.activity)
        var segmentEfforts: [SegmentEffort] = []

        init(healthID: UUID, sportRaw: String, name: String, start: Date, duration: TimeInterval,
             distance: Double, energy: Double, elevationGain: Double) {
            self.healthID = healthID; self.sportRaw = sportRaw; self.name = name; self.start = start
            self.duration = duration; self.distance = distance; self.energy = energy; self.elevationGain = elevationGain
        }
    }

    @Model
    final class Gear {
        var uid: UUID = UUID()
        var name: String
        var kindRaw: String               // "shoes" | "bike"
        var defaultSportRaw: String?      // auto-assign to new activities of this sport
        var retireAtKm: Double
        var startingKm: Double = 0
        var retired: Bool = false
        var createdAt: Date = Date()
        @Relationship(deleteRule: .nullify, inverse: \Activity.gear)
        var activities: [Activity] = []

        init(name: String, kindRaw: String, defaultSportRaw: String?, retireAtKm: Double) {
            self.name = name; self.kindRaw = kindRaw; self.defaultSportRaw = defaultSportRaw; self.retireAtKm = retireAtKm
        }
    }

    @Model
    final class Segment {
        var uid: UUID = UUID()
        var name: String
        var sportRaw: String
        var pointsData: Data              // [RoutePoint]
        var distance: Double
        var elevationGain: Double
        var createdAt: Date = Date()
        @Relationship(deleteRule: .cascade, inverse: \SegmentEffort.segment)
        var efforts: [SegmentEffort] = []

        init(name: String, sportRaw: String, pointsData: Data, distance: Double, elevationGain: Double) {
            self.name = name; self.sportRaw = sportRaw; self.pointsData = pointsData
            self.distance = distance; self.elevationGain = elevationGain
        }
    }

    @Model
    final class SegmentEffort {
        var duration: TimeInterval
        var startDate: Date
        var startIndex: Int
        var endIndex: Int
        var segment: Segment?
        var activity: Activity?

        init(duration: TimeInterval, startDate: Date, startIndex: Int, endIndex: Int) {
            self.duration = duration; self.startDate = startDate; self.startIndex = startIndex; self.endIndex = endIndex
        }
    }

    @Model
    final class Goal {
        var uid: UUID = UUID()
        var sportRaw: String = ""         // "" = all sports
        var metricRaw: String
        var periodRaw: String
        var target: Double
        var createdAt: Date = Date()

        init(sportRaw: String, metricRaw: String, periodRaw: String, target: Double) {
            self.sportRaw = sportRaw; self.metricRaw = metricRaw; self.periodRaw = periodRaw; self.target = target
        }
    }
}

enum StrideMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    static var stages: [MigrationStage] { [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)] }
}

typealias Activity = SchemaV2.Activity
typealias Gear = SchemaV2.Gear
typealias Segment = SchemaV2.Segment
typealias SegmentEffort = SchemaV2.SegmentEffort
typealias Goal = SchemaV2.Goal

enum StrideStore {
    static func makeContainer() -> ModelContainer {
        do {
            return try ModelContainer(for: Schema(versionedSchema: SchemaV2.self), migrationPlan: StrideMigrationPlan.self)
        } catch {
            fatalError("Could not open the Stride database: \(error)")
        }
    }
}
