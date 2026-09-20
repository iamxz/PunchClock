import Foundation

public struct ScheduleEvaluator {
    public init() {}

    public func pendingReminders(now: Date,
                                 settings: Settings,
                                 record: DayRecord,
                                 calendar: Calendar = .current) -> [PunchTask] {
        guard settings.enabled, !record.skipped else { return [] }
        guard settings.isWorkday(now, calendar: calendar) else { return [] }

        var tasks: [PunchTask] = []

        if let windowStart = AttendanceRule.windowStart(settings, on: now, calendar: calendar),
           !record.morningDone,
           now >= windowStart {
            tasks.append(.morning)
        }

        if let expectedLeave = AttendanceRule.expectedLeave(record, settings: settings, on: now, calendar: calendar),
           !AttendanceRule.isEveningComplete(record, settings: settings, on: now, calendar: calendar),
           now >= expectedLeave {
            tasks.append(.evening)
        }

        return tasks
    }
}
