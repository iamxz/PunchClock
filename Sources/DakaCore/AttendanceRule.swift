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

    /// 合格下班卡：打卡时刻不早于「上班卡 + 工作时长」。
    /// 只比较绝对时刻，不依赖日历时区，因此调用方传入的日历时区
    /// 与打卡记录构造时区不一致时仍能正确判定。
    public static func isQualifyingEveningPunch(_ punch: Date,
                                               morning: Date,
                                               settings: Settings) -> Bool {
        punch >= morning.addingTimeInterval(settings.workDuration)
    }

    public static func effectiveEveningPunch(_ record: DayRecord,
                                             settings: Settings,
                                             on day: Date,
                                             calendar: Calendar = .current) -> Date? {
        guard let morning = record.morningDoneAt else { return nil }
        return record.eveningPunches.filter {
            isQualifyingEveningPunch($0, morning: morning, settings: settings)
        }.max()
    }

    public static func isEveningComplete(_ record: DayRecord,
                                         settings: Settings,
                                         on day: Date,
                                         calendar: Calendar = .current) -> Bool {
        effectiveEveningPunch(record, settings: settings, on: day, calendar: calendar) != nil
    }
}
