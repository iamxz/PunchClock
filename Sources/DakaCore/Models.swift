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

    public init(enabled: Bool = true,
                workdays: Set<Int> = [2, 3, 4, 5, 6],
                morningWindowStart: String = "09:00",
                morningDeadline: String = "09:30",
                eveningWindowStart: String = "18:00",
                eveningDeadline: String = "18:30",
                reminderIntervalSeconds: TimeInterval = 120) {
        self.enabled = enabled
        self.workdays = workdays
        self.morningWindowStart = morningWindowStart
        self.morningDeadline = morningDeadline
        self.eveningWindowStart = eveningWindowStart
        self.eveningDeadline = eveningDeadline
        self.reminderIntervalSeconds = reminderIntervalSeconds
    }

    public static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case enabled, workdays
        case morningWindowStart, morningDeadline
        case eveningWindowStart, eveningDeadline
        case reminderIntervalSeconds
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
    }
}

public struct DayRecord: Codable, Equatable, Sendable {
    public var morningDone: Bool
    public var morningDoneAt: Date?
    public var eveningDone: Bool
    public var eveningDoneAt: Date?
    public var skipped: Bool

    public init(morningDone: Bool = false,
                morningDoneAt: Date? = nil,
                eveningDone: Bool = false,
                eveningDoneAt: Date? = nil,
                skipped: Bool = false) {
        self.morningDone = morningDone
        self.morningDoneAt = morningDoneAt
        self.eveningDone = eveningDone
        self.eveningDoneAt = eveningDoneAt
        self.skipped = skipped
    }

    public func isDone(_ task: PunchTask) -> Bool {
        switch task {
        case .morning: return morningDone
        case .evening: return eveningDone
        }
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
