import Foundation

public struct DailyStat: Equatable, Sendable {
    public let dateKey: String
    public let weekday: Int
    public let isWorkday: Bool
    public let completedBoth: Bool
    public let skipped: Bool
    public let morningDoneAt: Date?
    public let eveningDoneAt: Date?
    public let workDuration: TimeInterval?

    public init(dateKey: String,
                weekday: Int,
                isWorkday: Bool,
                completedBoth: Bool,
                skipped: Bool,
                morningDoneAt: Date?,
                eveningDoneAt: Date?,
                workDuration: TimeInterval?) {
        self.dateKey = dateKey
        self.weekday = weekday
        self.isWorkday = isWorkday
        self.completedBoth = completedBoth
        self.skipped = skipped
        self.morningDoneAt = morningDoneAt
        self.eveningDoneAt = eveningDoneAt
        self.workDuration = workDuration
    }
}

public struct StatisticsSummary: Equatable, Sendable {
    public var days: [DailyStat]
    public var rangeDays: Int
    public var monthPunchDays: Int
    public var currentStreak: Int
    public var averageWorkDuration: TimeInterval?
    public var missedDays: Int

    public init(days: [DailyStat] = [],
                rangeDays: Int = 0,
                monthPunchDays: Int = 0,
                currentStreak: Int = 0,
                averageWorkDuration: TimeInterval? = nil,
                missedDays: Int = 0) {
        self.days = days
        self.rangeDays = rangeDays
        self.monthPunchDays = monthPunchDays
        self.currentStreak = currentStreak
        self.averageWorkDuration = averageWorkDuration
        self.missedDays = missedDays
    }
}

public enum Statistics {
    public static func compute(records: [String: DayRecord],
                               settings: Settings,
                               now: Date,
                               rangeDays: Int,
                               calendar: Calendar = .current) -> StatisticsSummary {
        let range = max(1, rangeDays)

        func completed(_ record: DayRecord, on day: Date) -> Bool {
            record.morningDone && AttendanceRule.isEveningComplete(record, settings: settings, on: day, calendar: calendar)
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
            let isWorkday = settings.workdays.contains(weekday)
            let completedBoth = completed(record, on: day)
            let effectiveEvening = AttendanceRule.effectiveEveningPunch(record, settings: settings, on: day, calendar: calendar)

            var duration: TimeInterval?
            if let morning = record.morningDoneAt, let evening = effectiveEvening, evening >= morning {
                duration = evening.timeIntervalSince(morning)
            }
            if let duration { durations.append(duration) }

            days.append(DailyStat(dateKey: key, weekday: weekday, isWorkday: isWorkday,
                                  completedBoth: completedBoth, skipped: record.skipped,
                                  morningDoneAt: record.morningDoneAt,
                                  eveningDoneAt: effectiveEvening,
                                  workDuration: duration))

            if isWorkday && !record.skipped && !completedBoth {
                let isToday = calendar.isDate(day, inSameDayAs: now)
                if isToday {
                    let expectedLeave = AttendanceRule.expectedLeave(record, settings: settings, on: day, calendar: calendar)
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
                let isWorkday = settings.workdays.contains(DakaDate.weekday(of: day, calendar: calendar))
                if isWorkday && completed(record, on: day) {
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
        let todayIsWorkday = settings.workdays.contains(DakaDate.weekday(of: now, calendar: calendar))
        var todayInProgress = todayIsWorkday && !todayRecord.skipped && !todayCompleted
        if todayInProgress {
            let expectedLeave = AttendanceRule.expectedLeave(todayRecord, settings: settings, on: now, calendar: calendar)
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
            let isWorkday = settings.workdays.contains(DakaDate.weekday(of: cursor, calendar: calendar))
            if isWorkday && !record.skipped {
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
                                 monthPunchDays: monthPunch, currentStreak: streak,
                                 averageWorkDuration: average, missedDays: missed)
    }
}
