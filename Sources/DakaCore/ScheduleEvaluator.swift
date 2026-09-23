import Foundation

public struct ScheduleEvaluator {
    public init() {}

    public func pendingReminders(now: Date,
                                 settings: Settings,
                                 record: DayRecord,
                                 leaves: [LeaveRecord],
                                 calendar: Calendar = .current) -> [PunchTask] {
        guard settings.enabled else { return [] }
        guard !AttendanceRule.isFullDayLeave(settings, on: now, leaves: leaves, calendar: calendar) else { return [] }
        guard settings.isWorkday(now, calendar: calendar) else { return [] }
        // 唯一一条「请假进行中不唠叨」规则：不搬提醒时刻，只抑制当下。Scheduler 每秒 tick，
        // 请假结束的瞬间 pending 重新变非空，提醒自动接着弹。
        guard !LeaveRules.contains(now, slices: LeaveRules.slices(on: now, in: leaves, calendar: calendar)) else { return [] }

        var tasks: [PunchTask] = []

        if let windowStart = AttendanceRule.windowStart(settings, on: now, calendar: calendar),
           !record.morningDone,
           now >= windowStart {
            tasks.append(.morning)
        }

        if let expectedLeave = AttendanceRule.expectedLeave(record, settings: settings, on: now,
                                                            leaves: leaves, calendar: calendar),
           !AttendanceRule.isEveningComplete(record, settings: settings, on: now,
                                             leaves: leaves, calendar: calendar),
           now >= expectedLeave {
            tasks.append(.evening)
        }

        return tasks
    }
}
