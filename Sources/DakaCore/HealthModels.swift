import Foundation

public struct HealthSettings: Codable, Equatable, Sendable {
    public var waterEnabled: Bool
    public var waterGoalCups: Int
    public var waterIntervalMinutes: Int
    public var movementEnabled: Bool
    public var movementGoalCount: Int
    public var movementIntervalMinutes: Int

    public init(waterEnabled: Bool = true,
                waterGoalCups: Int = 8,
                waterIntervalMinutes: Int = 60,
                movementEnabled: Bool = true,
                movementGoalCount: Int = 8,
                movementIntervalMinutes: Int = 60) {
        self.waterEnabled = waterEnabled
        self.waterGoalCups = waterGoalCups
        self.waterIntervalMinutes = waterIntervalMinutes
        self.movementEnabled = movementEnabled
        self.movementGoalCount = movementGoalCount
        self.movementIntervalMinutes = movementIntervalMinutes
    }

    public static let `default` = HealthSettings()

    /// 间隔下限 15 分钟，避免异常配置刷屏。
    public var effectiveWaterIntervalMinutes: Int { max(15, waterIntervalMinutes) }
    public var effectiveMovementIntervalMinutes: Int { max(15, movementIntervalMinutes) }

    private enum CodingKeys: String, CodingKey {
        case waterEnabled, waterGoalCups, waterIntervalMinutes
        case movementEnabled, movementGoalCount, movementIntervalMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HealthSettings.default
        self.waterEnabled = try c.decodeIfPresent(Bool.self, forKey: .waterEnabled) ?? d.waterEnabled
        self.waterGoalCups = try c.decodeIfPresent(Int.self, forKey: .waterGoalCups) ?? d.waterGoalCups
        self.waterIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .waterIntervalMinutes) ?? d.waterIntervalMinutes
        self.movementEnabled = try c.decodeIfPresent(Bool.self, forKey: .movementEnabled) ?? d.movementEnabled
        self.movementGoalCount = try c.decodeIfPresent(Int.self, forKey: .movementGoalCount) ?? d.movementGoalCount
        self.movementIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .movementIntervalMinutes) ?? d.movementIntervalMinutes
    }
}

public struct DayHealthRecord: Codable, Equatable, Sendable {
    public var drinks: [Date]
    public var stands: [Date]

    public init(drinks: [Date] = [], stands: [Date] = []) {
        self.drinks = drinks
        self.stands = stands
    }

    public var cups: Int { drinks.count }
    public var standCount: Int { stands.count }
    public var lastDrinkAt: Date? { drinks.max() }
    public var lastStandAt: Date? { stands.max() }

    private enum CodingKeys: String, CodingKey {
        case drinks, stands
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.drinks = try c.decodeIfPresent([Date].self, forKey: .drinks) ?? []
        self.stands = try c.decodeIfPresent([Date].self, forKey: .stands) ?? []
    }
}

public struct HealthData: Codable, Equatable, Sendable {
    public var settings: HealthSettings
    public var records: [String: DayHealthRecord]

    public init(settings: HealthSettings = .default,
                records: [String: DayHealthRecord] = [:]) {
        self.settings = settings
        self.records = records
    }

    private enum CodingKeys: String, CodingKey {
        case settings, records
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.settings = try c.decodeIfPresent(HealthSettings.self, forKey: .settings) ?? .default
        self.records = try c.decodeIfPresent([String: DayHealthRecord].self, forKey: .records) ?? [:]
    }
}

public enum HealthLogKind: String, Codable, Sendable {
    case water
    case movement
}
