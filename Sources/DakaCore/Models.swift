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

public struct ReminderState: Equatable, Sendable {
    public var pending: [PunchTask]

    public init(pending: [PunchTask] = []) {
        self.pending = pending
    }

    public var isEmpty: Bool { pending.isEmpty }

    public func contains(_ task: PunchTask) -> Bool { pending.contains(task) }
}

public struct Settings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var workdays: Set<Int>
    public var workStartTime: String
    public var workDurationHours: Double
    public var flexMinutes: Int
    public var reminderIntervalSeconds: TimeInterval

    public init(enabled: Bool = true,
                workdays: Set<Int> = [2, 3, 4, 5, 6],
                workStartTime: String = "09:00",
                workDurationHours: Double = 9,
                flexMinutes: Int = 30,
                reminderIntervalSeconds: TimeInterval = 120) {
        self.enabled = enabled
        self.workdays = workdays
        self.workStartTime = workStartTime
        self.workDurationHours = workDurationHours
        self.flexMinutes = flexMinutes
        self.reminderIntervalSeconds = reminderIntervalSeconds
    }

    /// 提醒间隔下限 30 秒，避免异常配置导致每秒刷屏。
    public var effectiveReminderIntervalSeconds: TimeInterval {
        max(30, reminderIntervalSeconds)
    }

    public var workDuration: TimeInterval { max(0.5, workDurationHours) * 3600 }
    public var flexDuration: TimeInterval { TimeInterval(max(0, flexMinutes) * 60) }

    public static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case enabled, workdays
        case workStartTime, workDurationHours, flexMinutes
        // Legacy keys kept only for decoder migration
        case morningWindowStart, morningDeadline
        case eveningWindowStart, eveningDeadline
        case minWorkDurationHours
        case reminderIntervalSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default

        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        self.workdays = try c.decodeIfPresent(Set<Int>.self, forKey: .workdays) ?? d.workdays
        self.reminderIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .reminderIntervalSeconds) ?? d.reminderIntervalSeconds

        // Decode legacy keys for migration fallback
        let legacyMorningStart = try c.decodeIfPresent(String.self, forKey: .morningWindowStart)
        let legacyMorningDeadline = try c.decodeIfPresent(String.self, forKey: .morningDeadline)
        let legacyMinWorkHours = try c.decodeIfPresent(Double.self, forKey: .minWorkDurationHours)

        // New fields: decode new keys first, fall back to legacy migration
        if let ws = try c.decodeIfPresent(String.self, forKey: .workStartTime) {
            self.workStartTime = ws
        } else {
            self.workStartTime = legacyMorningStart ?? d.workStartTime
        }

        if let wd = try c.decodeIfPresent(Double.self, forKey: .workDurationHours) {
            self.workDurationHours = wd
        } else {
            self.workDurationHours = legacyMinWorkHours ?? d.workDurationHours
        }

        if let fm = try c.decodeIfPresent(Int.self, forKey: .flexMinutes) {
            self.flexMinutes = fm
        } else {
            let wsStr = legacyMorningStart ?? d.workStartTime
            let dlStr = legacyMorningDeadline ?? "09:30"
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            if let start = fmt.date(from: wsStr),
               let deadline = fmt.date(from: dlStr) {
                self.flexMinutes = max(0, Int(deadline.timeIntervalSince(start) / 60))
            } else {
                self.flexMinutes = d.flexMinutes
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(workdays, forKey: .workdays)
        try c.encode(workStartTime, forKey: .workStartTime)
        try c.encode(workDurationHours, forKey: .workDurationHours)
        try c.encode(flexMinutes, forKey: .flexMinutes)
        try c.encode(reminderIntervalSeconds, forKey: .reminderIntervalSeconds)
    }

    // MARK: - 标准工作日日历

    /// 当前设置对应的标准工作日日历引擎（基础星期 + 内置节假日）。
    public var workdayCalendar: WorkdayCalendar {
        WorkdayCalendar(baseWorkdays: workdays)
    }

    /// 某天是否应上班（考虑节假日/调休）。
    public func isWorkday(_ date: Date, calendar: Calendar = .current) -> Bool {
        workdayCalendar.isWorkday(date, calendar: calendar)
    }

    /// 某天的详细类型（含节假日/调休信息）。
    public func dayType(_ date: Date, calendar: Calendar = .current) -> WorkdayDayType {
        workdayCalendar.dayType(date, calendar: calendar)
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
