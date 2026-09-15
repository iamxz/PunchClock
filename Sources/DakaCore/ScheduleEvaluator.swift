import Foundation

public struct ScheduleEvaluator {
    public init() {}

    /// 返回当前应催办的打卡项。
    /// - `launchForced`：应用刚启动，若上班未打卡且已过 `launchPromptEarliest`，
    ///   即使还没到上班时间也催办（仅影响 morning）。
    public func pendingTasks(now: Date,
                             settings: Settings,
                             record: DayRecord,
                             calendar: Calendar = .current,
                             launchForced: Bool = false) -> [PunchTask] {
        guard settings.enabled, !record.skipped else { return [] }
        guard settings.workdays.contains(DakaDate.weekday(of: now, calendar: calendar)) else { return [] }

        var tasks: [PunchTask] = []

        if !record.morningDone {
            let due = DakaDate.date(on: now, at: settings.morningTime, calendar: calendar)
            if let due, now >= due {
                tasks.append(.morning)
            } else if launchForced,
                      let due, now < due,
                      let earliest = DakaDate.date(on: now, at: settings.launchPromptEarliest, calendar: calendar),
                      now >= earliest {
                tasks.append(.morning)
            }
        }

        if !record.eveningDone {
            let due = DakaDate.date(on: now, at: settings.eveningTime, calendar: calendar)
            if let due, now >= due {
                tasks.append(.evening)
            }
        }

        return tasks
    }
}
