import Foundation

public struct ScheduleEvaluator {
    public init() {}

    public func pendingReminders(now: Date,
                                 settings: Settings,
                                 record: DayRecord,
                                 calendar: Calendar = .current) -> [PunchTask] {
        guard settings.enabled, !record.skipped else { return [] }
        guard settings.workdays.contains(DakaDate.weekday(of: now, calendar: calendar)) else { return [] }

        var tasks: [PunchTask] = []

        if pending(start: settings.morningWindowStart,
                   done: record.morningDone,
                   now: now,
                   calendar: calendar) {
            tasks.append(.morning)
        }
        if pending(start: settings.eveningWindowStart,
                   done: PunchRules.isEveningComplete(record, minWorkDuration: settings.minWorkDuration),
                   now: now,
                   calendar: calendar) {
            tasks.append(.evening)
        }
        return tasks
    }

    private func pending(start: String, done: Bool, now: Date, calendar: Calendar) -> Bool {
        guard !done else { return false }
        guard let startDate = DakaDate.date(on: now, at: start, calendar: calendar) else { return false }
        return now >= startDate
    }
}
