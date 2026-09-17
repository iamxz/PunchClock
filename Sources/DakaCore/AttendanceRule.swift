import Foundation

public enum AttendanceRule {
    public static func windowStart(_ settings: Settings,
                                   on day: Date,
                                   calendar: Calendar = .current) -> Date? {
        DakaDate.date(on: day, at: settings.workStartTime, calendar: calendar)
    }

    public static func windowEnd(_ settings: Settings,
                                 on day: Date,
                                 calendar: Calendar = .current) -> Date? {
        windowStart(settings, on: day, calendar: calendar)?.addingTimeInterval(settings.flexDuration)
    }

    public static func effectiveStart(_ record: DayRecord,
                                      settings: Settings,
                                      on day: Date,
                                      calendar: Calendar = .current) -> Date? {
        guard let morning = record.morningDoneAt else { return nil }
        guard let start = windowStart(settings, on: day, calendar: calendar) else { return nil }
        return max(start, morning)
    }

    public static func expectedLeave(_ record: DayRecord,
                                     settings: Settings,
                                     on day: Date,
                                     calendar: Calendar = .current) -> Date? {
        effectiveStart(record, settings: settings, on: day, calendar: calendar)?
            .addingTimeInterval(settings.workDuration)
    }

    public static func effectiveEveningPunch(_ record: DayRecord,
                                             settings: Settings,
                                             on day: Date,
                                             calendar: Calendar = .current) -> Date? {
        guard let leave = expectedLeave(record, settings: settings, on: day, calendar: calendar) else { return nil }
        return record.eveningPunches.filter { $0 >= leave }.max()
    }

    public static func isEveningComplete(_ record: DayRecord,
                                         settings: Settings,
                                         on day: Date,
                                         calendar: Calendar = .current) -> Bool {
        effectiveEveningPunch(record, settings: settings, on: day, calendar: calendar) != nil
    }
}
