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
    /// 考勤弹性方式：只决定上班卡如何换算成「考勤起点」。迟到记账是独立开关，工时统计始终按真实在岗时长。
    public enum FlexMode: String, Codable, CaseIterable, Sendable {
        /// 早到早走、晚到晚走，但浮动不超过「弹性时间」。
        case elasticBoth
        /// 早到按上班时间起算（不早走），晚到全额顺延补足。
        case elasticBackward

        public var title: String {
            switch self {
            case .elasticBoth: return "前后弹性"
            case .elasticBackward: return "只往后弹性"
            }
        }

        /// 设置页里对「弹性时间」在该模式下的作用说明。
        public var flexMeaning: String {
            switch self {
            case .elasticBoth: return "起点可在上班时间前后各浮动「弹性时间」那么多分钟，再早或再晚都不继续顺延下班线。"
            case .elasticBackward: return "起点不早于上班时间；晚打上班卡则按实际时刻顺延下班，「弹性时间」在此只用作迟到宽限。"
            }
        }

        /// 无法识别的值（例如早已废弃的写法）退回默认，不让整份配置读不出来。
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = FlexMode(rawValue: raw) ?? Settings.default.flexMode
        }
    }

    public var enabled: Bool
    public var workdays: Set<Int>
    public var workStartTime: String
    public var workDurationHours: Double
    public var flexMinutes: Int
    public var flexMode: FlexMode
    /// 是否把「上班卡晚于上班时间 + 弹性时间」记成迟到。与弹性方式无关，两种模式下都可开。
    public var recordsLateArrival: Bool
    public var reminderIntervalSeconds: TimeInterval
    /// 开机自启（登录项）的开关，关闭后重启应用不会再自动注册。
    public var loginItemEnabled: Bool
    /// 定点启动 LaunchAgent 的开关（到点拉起应用）。关闭后不安装、并清理已装的 plist。
    public var scheduledLaunchEnabled: Bool

    public init(enabled: Bool = true,
                workdays: Set<Int> = [2, 3, 4, 5, 6],
                workStartTime: String = "09:00",
                workDurationHours: Double = 9,
                flexMinutes: Int = 30,
                flexMode: FlexMode = .elasticBackward,
                recordsLateArrival: Bool = false,
                reminderIntervalSeconds: TimeInterval = 120,
                loginItemEnabled: Bool = true,
                scheduledLaunchEnabled: Bool = true) {
        self.enabled = enabled
        self.workdays = workdays
        self.workStartTime = workStartTime
        self.workDurationHours = workDurationHours
        self.flexMinutes = flexMinutes
        self.flexMode = flexMode
        self.recordsLateArrival = recordsLateArrival
        self.reminderIntervalSeconds = reminderIntervalSeconds
        self.loginItemEnabled = loginItemEnabled
        self.scheduledLaunchEnabled = scheduledLaunchEnabled
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
        case workStartTime, workDurationHours, flexMinutes, flexMode
        case recordsLateArrival
        // Legacy keys kept only for decoder migration
        case morningWindowStart, morningDeadline
        case eveningWindowStart, eveningDeadline
        case minWorkDurationHours
        case reminderIntervalSeconds
        case loginItemEnabled, scheduledLaunchEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default

        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        self.workdays = try c.decodeIfPresent(Set<Int>.self, forKey: .workdays) ?? d.workdays
        self.flexMode = try c.decodeIfPresent(FlexMode.self, forKey: .flexMode) ?? d.flexMode
        self.recordsLateArrival = try c.decodeIfPresent(Bool.self, forKey: .recordsLateArrival) ?? d.recordsLateArrival
        self.reminderIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .reminderIntervalSeconds) ?? d.reminderIntervalSeconds
        self.loginItemEnabled = try c.decodeIfPresent(Bool.self, forKey: .loginItemEnabled) ?? d.loginItemEnabled
        self.scheduledLaunchEnabled = try c.decodeIfPresent(Bool.self, forKey: .scheduledLaunchEnabled) ?? d.scheduledLaunchEnabled

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
        try c.encode(flexMode, forKey: .flexMode)
        try c.encode(recordsLateArrival, forKey: .recordsLateArrival)
        try c.encode(reminderIntervalSeconds, forKey: .reminderIntervalSeconds)
        try c.encode(loginItemEnabled, forKey: .loginItemEnabled)
        try c.encode(scheduledLaunchEnabled, forKey: .scheduledLaunchEnabled)
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
    /// ⚠️ 只用于解码旧 JSON —— 迁移成整天请假发生在 `DakaData.init(from:)`。
    /// 运行时判定一律读 `DakaData.leaves`：既不参与编码，也不能再被业务读取。
    public let skipped: Bool

    public init(morningPunches: [Date] = [], eveningPunches: [Date] = []) {
        self.morningPunches = morningPunches
        self.eveningPunches = eveningPunches
        self.skipped = false
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
        // `skipped` 不再写出：请假只存 `DakaData.leaves`（与 Settings「只写新键」同一套契约）。
    }
}

public struct DakaData: Codable, Equatable, Sendable {
    public var settings: Settings
    public var records: [String: DayRecord]
    /// 请假（时间段，可跨天）。跨天区间原样存一条，按天求交派生当天片段。
    public var leaves: [LeaveRecord]

    public init(settings: Settings = .default,
                records: [String: DayRecord] = [:],
                leaves: [LeaveRecord] = []) {
        self.settings = settings
        self.records = records
        self.leaves = leaves
    }

    private enum CodingKeys: String, CodingKey {
        case settings, records, leaves
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? .default
        self.records = try c.decodeIfPresent([String: DayRecord].self, forKey: .records) ?? [:]
        // 只在 `leaves` 键完全缺失（旧文件）时迁移：否则用户把请假清空成 [] 后旧标记会复活。
        // 新键走宽松解码 —— 一条写坏的请假只能丢请假，不能让整库被判损坏而连带丢打卡。
        self.leaves = c.contains(.leaves)
            ? ((try? c.decode([LeaveRecord].self, forKey: .leaves)) ?? []).sorted { $0.start < $1.start }
            : DakaData.migratedLeaves(from: self.records, calendar: .current)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(settings, forKey: .settings)
        try c.encode(records, forKey: .records)
        // 空数组也要写：它同时是「本文件已完成请假迁移」的标记。
        try c.encode(leaves, forKey: .leaves)
    }

    /// 旧 `records[key].skipped == true` → 一条整天请假 [key 00:00, key+1 00:00)。
    static func migratedLeaves(from records: [String: DayRecord], calendar: Calendar) -> [LeaveRecord] {
        records.reduce(into: [LeaveRecord]()) { result, entry in
            guard entry.value.skipped,
                  let dayStart = DakaDate.date(for: entry.key, calendar: calendar),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return }
            result.append(LeaveRecord(start: dayStart, end: dayEnd))
        }
        .sorted { $0.start < $1.start }
    }
}
