import Foundation

public struct ScheduleEvaluator {
    public init() {}

    public func pendingReminders(now: Date,
                                 settings: Settings,
                                 record: DayRecord,
                                 calendar: Calendar = .current) -> [PendingReminder] {
        guard settings.enabled, !record.skipped else { return [] }
        guard settings.workdays.contains(DakaDate.weekday(of: now, calendar: calendar)) else { return [] }

        var reminders: [PendingReminder] = []

        if let level = level(now: now,
                             start: settings.morningWindowStart,
                             deadline: settings.morningDeadline,
                             done: record.morningDone,
                             calendar: calendar) {
            reminders.append(PendingReminder(task: .morning, level: level))
        }
        if let level = level(now: now,
                             start: settings.eveningWindowStart,
                             deadline: settings.eveningDeadline,
                             done: record.eveningDone,
                             calendar: calendar) {
            reminders.append(PendingReminder(task: .evening, level: level))
        }
        return reminders
    }

    private func level(now: Date,
                       start: String,
                       deadline: String,
                       done: Bool,
                       calendar: Calendar) -> ReminderLevel? {
        guard !done else { return nil }
        if let deadlineDate = DakaDate.date(on: now, at: deadline, calendar: calendar), now >= deadlineDate {
            return .hard
        }
        if let startDate = DakaDate.date(on: now, at: start, calendar: calendar), now >= startDate {
            return .gentle
        }
        return nil
    }
}
