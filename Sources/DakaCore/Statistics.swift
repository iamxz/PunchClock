import Foundation

public struct DailyStat: Equatable, Sendable {
    public let dateKey: String
    public let weekday: Int
    public let isWorkday: Bool
    public let completedBoth: Bool
    /// 当天应工作时长被请假全部抵扣，无需打卡。
    public let onLeave: Bool
    /// 当天落在应上班窗口内的请假秒数。
    public let leaveSeconds: TimeInterval
    /// `leaveSeconds / 应工作时长`，非工作日为 0。
    public let leaveFraction: Double
    public let morningDoneAt: Date?
    public let eveningDoneAt: Date?
    /// 实际在岗时长（首张上班卡 → 最后一张合格下班卡），不因请假扣减。
    public let workDuration: TimeInterval?

    public init(dateKey: String,
                weekday: Int,
                isWorkday: Bool,
                completedBoth: Bool,
                onLeave: Bool,
                leaveSeconds: TimeInterval,
                leaveFraction: Double,
                morningDoneAt: Date?,
                eveningDoneAt: Date?,
                workDuration: TimeInterval?) {
        self.dateKey = dateKey
        self.weekday = weekday
        self.isWorkday = isWorkday
        self.completedBoth = completedBoth
        self.onLeave = onLeave
        self.leaveSeconds = leaveSeconds
        self.leaveFraction = leaveFraction
        self.morningDoneAt = morningDoneAt
        self.eveningDoneAt = eveningDoneAt
        self.workDuration = workDuration
    }
}

public struct StatisticsSummary: Equatable, Sendable {
    public var days: [DailyStat]
    public var rangeDays: Int
    public var monthPunchDays: Int
    /// 本月请假折算天数：各工作日「请假时长 ÷ 应工作时长」之和，半天记 0.5。
    public var monthLeaveDays: Double
    public var currentStreak: Int
    public var averageWorkDuration: TimeInterval?
    public var missedDays: Int

    public init(days: [DailyStat] = [],
                rangeDays: Int = 0,
                monthPunchDays: Int = 0,
                monthLeaveDays: Double = 0,
                currentStreak: Int = 0,
                averageWorkDuration: TimeInterval? = nil,
                missedDays: Int = 0) {
        self.days = days
        self.rangeDays = rangeDays
        self.monthPunchDays = monthPunchDays
        self.monthLeaveDays = monthLeaveDays
        self.currentStreak = currentStreak
        self.averageWorkDuration = averageWorkDuration
        self.missedDays = missedDays
    }
}

public enum Statistics {
    public static func compute(records: [String: DayRecord],
                               settings: Settings,
                               leaves: [LeaveRecord],
                               now: Date,
                               rangeDays: Int,
                               calendar: Calendar = .current) -> StatisticsSummary {
        let range = max(1, rangeDays)

        func fullDayLeave(_ day: Date) -> Bool {
            AttendanceRule.isFullDayLeave(settings, on: day, leaves: leaves, calendar: calendar)
        }

        func completed(_ record: DayRecord, on day: Date) -> Bool {
            record.morningDone && AttendanceRule.isEveningComplete(record, settings: settings, on: day,
                                                                   leaves: leaves, calendar: calendar)
        }

        var days: [DailyStat] = []
        var durations: [TimeInterval] = []
        var monthPunch = 0
        var missed = 0

        for offset in stride(from: range - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = DakaDate.key(for: day, calendar: calendar)
            let record = records[key] ?? DayRecord()
            let weekday = DakaDate.weekday(of: day, calendar: calendar)
            let isWorkday = settings.isWorkday(day, calendar: calendar)
            let onLeave = fullDayLeave(day)
            let leaveSeconds = AttendanceRule.leaveDuration(settings, on: day,
                                                             leaves: leaves, calendar: calendar)
            let completedBoth = completed(record, on: day)
            let effectiveEvening = AttendanceRule.effectiveEveningPunch(record, settings: settings, on: day,
                                                                        leaves: leaves, calendar: calendar)

            var duration: TimeInterval?
            if let morning = record.morningDoneAt, let evening = effectiveEvening, evening >= morning {
                duration = evening.timeIntervalSince(morning)
            }
            if let duration { durations.append(duration) }

            days.append(DailyStat(dateKey: key, weekday: weekday, isWorkday: isWorkday,
                                  completedBoth: completedBoth, onLeave: onLeave,
                                  leaveSeconds: leaveSeconds,
                                  leaveFraction: isWorkday
                                    ? AttendanceRule.leaveFraction(settings, on: day,
                                                                   leaves: leaves, calendar: calendar)
                                    : 0,
                                  morningDoneAt: record.morningDoneAt,
                                  eveningDoneAt: effectiveEvening,
                                  workDuration: duration))

            if isWorkday && !onLeave && !completedBoth {
                let isToday = calendar.isDate(day, inSameDayAs: now)
                if isToday {
                    let expectedLeave = AttendanceRule.expectedLeave(record, settings: settings, on: day,
                                                                     leaves: leaves, calendar: calendar)
                    let expired = expectedLeave.map { now >= $0 } ?? false
                    if expired { missed += 1 }
                } else {
                    missed += 1
                }
            }
        }

        if let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) {
            var day = calendar.startOfDay(for: monthStart)
            while day <= now {
                let key = DakaDate.key(for: day, calendar: calendar)
                let record = records[key] ?? DayRecord()
                let isWorkday = settings.isWorkday(day, calendar: calendar)
                if isWorkday && !fullDayLeave(day) && completed(record, on: day) {
                    monthPunch += 1
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        let average = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)

        let todayKey = DakaDate.key(for: now, calendar: calendar)
        let todayRecord = records[todayKey] ?? DayRecord()
        let todayCompleted = completed(todayRecord, on: now)
        let todayIsWorkday = settings.isWorkday(now, calendar: calendar)
        var todayInProgress = todayIsWorkday && !fullDayLeave(now) && !todayCompleted
        if todayInProgress {
            let expectedLeave = AttendanceRule.expectedLeave(todayRecord, settings: settings, on: now,
                                                             leaves: leaves, calendar: calendar)
            if let leave = expectedLeave, now >= leave {
                todayInProgress = false
            }
        }

        var cursor = calendar.startOfDay(for: now)
        if todayInProgress, let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
        }
        var streak = 0
        for _ in 0..<400 {
            let key = DakaDate.key(for: cursor, calendar: calendar)
            let record = records[key] ?? DayRecord()
            let isWorkday = settings.isWorkday(cursor, calendar: calendar)
            if isWorkday && !fullDayLeave(cursor) {
                if completed(record, on: cursor) {
                    streak += 1
                } else {
                    break
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return StatisticsSummary(days: days, rangeDays: range,
                                 monthPunchDays: monthPunch,
                                 monthLeaveDays: leaveDays(leaves: leaves, settings: settings,
                                                           month: now, calendar: calendar),
                                 currentStreak: streak,
                                 averageWorkDuration: average, missedDays: missed)
    }

    /// 整月（1 号 ~ 月末，含未来已排好的请假）请假折算天数。
    /// 只对工作日累加：周末与法定假日本来不用上班，请了也不算成本；调休补班日则计入。
    public static func leaveDays(leaves: [LeaveRecord],
                                 settings: Settings,
                                 month: Date,
                                 calendar: Calendar = .current) -> Double {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count else { return 0 }
        var total = 0.0
        for day in 1...dayCount {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: monthStart) else { continue }
            guard settings.isWorkday(date, calendar: calendar) else { continue }
            total += AttendanceRule.leaveFraction(settings, on: date, leaves: leaves, calendar: calendar)
        }
        return total
    }

    /// 请假天数的展示文本：整数去掉小数位，否则保留一位（`3` / `2.5` / `0.3`）。
    public static func leaveDaysText(_ days: Double) -> String {
        let rounded = (days * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded.rounded())) : String(format: "%.1f", rounded)
    }
}
