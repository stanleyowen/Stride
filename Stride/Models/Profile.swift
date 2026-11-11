import Foundation
import StrideCore

enum Keys {
    static let units = "units"
    static let maxHR = "maxHR"
    static let restHR = "restHR"
    static let birthYear = "birthYear"
    static let autoImport = "autoImport"
    static let hasOnboarded = "hasOnboarded"
    static let healthAuthorized = "healthAuthorized"
    static let analysisLanes = "analysisLanes"
    static let vo2History = "vo2History"
    static let rhrHistory = "rhrHistory"
}

/// Athlete profile backed by UserDefaults (views bind via @AppStorage with the same keys).
enum Profile {
    private static var d: UserDefaults { .standard }

    static var maxHR: Double {
        let v = d.double(forKey: Keys.maxHR)
        if v > 0 { return v }
        if let y = birthYear { return (208 - 0.7 * Double(Calendar.current.component(.year, from: .now) - y)).rounded() }
        return 190
    }

    static var restHR: Double {
        let v = d.double(forKey: Keys.restHR)
        return v > 0 ? v : 60
    }

    static var birthYear: Int? {
        let v = d.integer(forKey: Keys.birthYear)
        return v > 1900 ? v : nil
    }

    static var zones: HeartZones { HeartZones(maxHR: maxHR, restHR: restHR) }
    static var imperial: Bool { d.string(forKey: Keys.units) == "imperial" }
}

/// Longer-term Health metrics (VO₂max, resting HR) for trend charts.
enum HealthHistory {
    static var vo2Max: [TimedValue] {
        get { load(Keys.vo2History) }
        set { save(newValue, Keys.vo2History) }
    }

    static var restingHR: [TimedValue] {
        get { load(Keys.rhrHistory) }
        set { save(newValue, Keys.rhrHistory) }
    }

    private static func load(_ key: String) -> [TimedValue] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([TimedValue].self, from: data)) ?? []
    }

    private static func save(_ v: [TimedValue], _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(v), forKey: key)
    }
}
