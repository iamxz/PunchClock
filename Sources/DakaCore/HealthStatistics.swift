import Foundation

public struct HealthDayStat: Equatable, Sendable {
    public let dateKey: String
    public let cups: Int
    public let stands: Int
    public let isWorkday: Bool

    public init(dateKey: String, cups: Int, stands: Int, isWorkday: Bool) {
        self.dateKey = dateKey
        self.cups = cups
        self.stands = stands
        self.isWorkday = isWorkday
    }
}

public struct HealthSummary: Equatable, Sendable {
    public var days: [HealthDayStat]
    public var rangeDays: Int
    public var waterGoalDays: Int
    public var movementGoalDays: Int
    public var averageCups: Double
    public var averageStands: Double
    public var waterStreak: Int
    public var movementStreak: Int

    public init(days: [HealthDayStat] = [],
                rangeDays: Int = 0,
                waterGoalDays: Int = 0,
                movementGoalDays: Int = 0,
                averageCups: Double = 0,
                averageStands: Double = 0,
                waterStreak: Int = 0,
                movementStreak: Int = 0) {
        self.days = days
        self.rangeDays = rangeDays
        self.waterGoalDays = waterGoalDays
        self.movementGoalDays = movementGoalDays
        self.averageCups = averageCups
        self.averageStands = averageStands
        self.waterStreak = waterStreak
        self.movementStreak = movementStreak
    }
}

public enum HealthStatistics {
    private enum Metric { case water, movement }

    public static func compute(records: [String: DayHealthRecord],
                               settings: HealthSettings,
                               schedule: Settings,
                               now: Date,
                               rangeDays: Int,
                               calendar: Calendar = .current) -> HealthSummary {
        let range = max(1, rangeDays)
        var days: [HealthDayStat] = []
        var totalCups = 0
        var totalStands = 0
        var waterGoalDays = 0
        var movementGoalDays = 0

        for offset in stride(from: range - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = DakaDate.key(for: day, calendar: calendar)
            let rec = records[key] ?? DayHealthRecord()
            let isWorkday = schedule.isWorkday(day, calendar: calendar)
            days.append(HealthDayStat(dateKey: key, cups: rec.cups,
                                      stands: rec.standCount, isWorkday: isWorkday))
            totalCups += rec.cups
            totalStands += rec.standCount
            if isWorkday && rec.cups >= settings.waterGoalCups { waterGoalDays += 1 }
            if isWorkday && rec.standCount >= settings.movementGoalCount { movementGoalDays += 1 }
        }

        let count = max(1, days.count)
        return HealthSummary(days: days,
                             rangeDays: range,
                             waterGoalDays: waterGoalDays,
                             movementGoalDays: movementGoalDays,
                             averageCups: Double(totalCups) / Double(count),
                             averageStands: Double(totalStands) / Double(count),
                             waterStreak: streak(records: records, settings: settings,
                                                 schedule: schedule, now: now,
                                                 metric: .water, calendar: calendar),
                             movementStreak: streak(records: records, settings: settings,
                                                    schedule: schedule, now: now,
                                                    metric: .movement, calendar: calendar))
    }

    private static func streak(records: [String: DayHealthRecord],
                               settings: HealthSettings,
                               schedule: Settings,
                               now: Date,
                               metric: Metric,
                               calendar: Calendar) -> Int {
        var cursor = calendar.startOfDay(for: now)
        var count = 0
        for _ in 0..<400 {
            let key = DakaDate.key(for: cursor, calendar: calendar)
            let rec = records[key] ?? DayHealthRecord()
            let isWorkday = schedule.isWorkday(cursor, calendar: calendar)
            if isWorkday {
                let met = metric == .water
                    ? rec.cups >= settings.waterGoalCups
                    : rec.standCount >= settings.movementGoalCount
                let isToday = calendar.isDate(cursor, inSameDayAs: now)
                if met {
                    count += 1
                } else if !isToday {
                    break
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
