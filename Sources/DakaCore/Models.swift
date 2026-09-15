import Foundation

public enum PunchTask: String, Codable, CaseIterable, Hashable, Sendable {
    case morning
    case evening

    public var title: String {
        switch self {
        case .morning: return "上班打卡"
        case .evening: return "下班打卡"
        }
    }
}

public enum ReminderLevel: String, Codable, Equatable, Sendable {
    case gentle
    case hard
}

public struct PendingReminder: Equatable, Sendable {
    public let task: PunchTask
    public let level: ReminderLevel

    public init(task: PunchTask, level: ReminderLevel) {
        self.task = task
        self.level = level
    }
}

public struct ReminderState: Equatable, Sendable {
    public var gentle: [PunchTask]
    public var hard: [PunchTask]

    public init(gentle: [PunchTask] = [], hard: [PunchTask] = []) {
        self.gentle = gentle
        self.hard = hard
    }

    public var isEmpty: Bool { gentle.isEmpty && hard.isEmpty }
}

public struct Settings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var workdays: Set<Int>
    public var morningWindowStart: String
    public var morningDeadline: String
    public var eveningWindowStart: String
    public var eveningDeadline: String
    public var reminderIntervalSeconds: TimeInterval
    public var minWorkDurationHours: Double

    public init(enabled: Bool = true,
                workdays: Set<Int> = [2, 3, 4, 5, 6],
                morningWindowStart: String = "09:00",
                morningDeadline: String = "09:30",
                eveningWindowStart: String = "18:00",
                eveningDeadline: String = "18:30",
                reminderIntervalSeconds: TimeInterval = 120,
                minWorkDurationHours: Double = 8) {
        self.enabled = enabled
        self.workdays = workdays
        self.morningWindowStart = morningWindowStart
        self.morningDeadline = morningDeadline
        self.eveningWindowStart = eveningWindowStart
        self.eveningDeadline = eveningDeadline
        self.reminderIntervalSeconds = reminderIntervalSeconds
        self.minWorkDurationHours = minWorkDurationHours
    }

    /// 提醒间隔下限 30 秒，避免异常配置导致每秒刷屏。
    public var effectiveReminderIntervalSeconds: TimeInterval {
        max(30, reminderIntervalSeconds)
    }

    public var minWorkDuration: TimeInterval { max(0, minWorkDurationHours) * 3600 }

    public static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case enabled, workdays
        case morningWindowStart, morningDeadline
        case eveningWindowStart, eveningDeadline
        case reminderIntervalSeconds
        case minWorkDurationHours
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        self.workdays = try c.decodeIfPresent(Set<Int>.self, forKey: .workdays) ?? d.workdays
        self.morningWindowStart = try c.decodeIfPresent(String.self, forKey: .morningWindowStart) ?? d.morningWindowStart
        self.morningDeadline = try c.decodeIfPresent(String.self, forKey: .morningDeadline) ?? d.morningDeadline
        self.eveningWindowStart = try c.decodeIfPresent(String.self, forKey: .eveningWindowStart) ?? d.eveningWindowStart
        self.eveningDeadline = try c.decodeIfPresent(String.self, forKey: .eveningDeadline) ?? d.eveningDeadline
        self.reminderIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .reminderIntervalSeconds) ?? d.reminderIntervalSeconds
        self.minWorkDurationHours = try c.decodeIfPresent(Double.self, forKey: .minWorkDurationHours) ?? d.minWorkDurationHours
    }
}

public struct DayRecord: Codable, Equatable, Sendable {
    public var morningPunches: [Date]
    public var eveningPunches: [Date]
    public var skipped: Bool

    public init(morningPunches: [Date] = [], eveningPunches: [Date] = [], skipped: Bool = false) {
        self.morningPunches = morningPunches
        self.eveningPunches = eveningPunches
        self.skipped = skipped
    }

    public var morningDone: Bool { !morningPunches.isEmpty }
    public var eveningDone: Bool { !eveningPunches.isEmpty }
    public var morningDoneAt: Date? { morningPunches.min() }
    public var eveningDoneAt: Date? { eveningPunches.max() }

    private enum CodingKeys: String, CodingKey {
        case morningPunches, eveningPunches, skipped
        case morningDone, morningDoneAt, eveningDone, eveningDoneAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.skipped = try c.decodeIfPresent(Bool.self, forKey: .skipped) ?? false

        if let morning = try c.decodeIfPresent([Date].self, forKey: .morningPunches) {
            self.morningPunches = morning
        } else if try c.decodeIfPresent(Bool.self, forKey: .morningDone) ?? false {
            self.morningPunches = [try c.decodeIfPresent(Date.self, forKey: .morningDoneAt) ?? Date()]
        } else {
            self.morningPunches = []
        }

        if let evening = try c.decodeIfPresent([Date].self, forKey: .eveningPunches) {
            self.eveningPunches = evening
        } else if try c.decodeIfPresent(Bool.self, forKey: .eveningDone) ?? false {
            self.eveningPunches = [try c.decodeIfPresent(Date.self, forKey: .eveningDoneAt) ?? Date()]
        } else {
            self.eveningPunches = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(morningPunches, forKey: .morningPunches)
        try c.encode(eveningPunches, forKey: .eveningPunches)
        try c.encode(skipped, forKey: .skipped)
    }
}

public struct DakaData: Codable, Equatable, Sendable {
    public var settings: Settings
    public var records: [String: DayRecord]

    public init(settings: Settings = .default, records: [String: DayRecord] = [:]) {
        self.settings = settings
        self.records = records
    }
}
