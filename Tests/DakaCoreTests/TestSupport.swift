import Foundation
@testable import DakaCore

final class FixedClock: DakaClock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

enum TestTime {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    /// 2026-09-14 为周一。
    static func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0, _ s: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        return calendar.date(from: c)!
    }

    static var monday: Date { date(2026, 9, 14) }
    static var saturday: Date { date(2026, 9, 19) }

    /// 某一天内的一段时间请假（起止都用当天的时刻）。
    static func leave(on day: Date, from: (Int, Int), to: (Int, Int)) -> LeaveRecord {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        let start = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day,
                                                       hour: from.0, minute: from.1))!
        let end = calendar.date(from: DateComponents(year: c.year, month: c.month, day: c.day,
                                                     hour: to.0, minute: to.1))!
        return LeaveRecord(start: start, end: end)
    }

    /// 整天请假：`[当天 00:00, 次日 00:00)`，与旧 `skipped` 迁移出来的形状一致。
    static func fullDayLeave(on day: Date) -> LeaveRecord {
        let start = calendar.startOfDay(for: day)
        return LeaveRecord(start: start,
                           end: calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    /// 跨天请假。
    static func leave(from: (Date, Int, Int), to: (Date, Int, Int)) -> LeaveRecord {
        LeaveRecord(start: date(of: from.0, from.1, from.2),
                    end: date(of: to.0, to.1, to.2))
    }

    private static func date(of day: Date, _ hour: Int, _ minute: Int) -> Date {
        var c = calendar.dateComponents([.year, .month, .day], from: day)
        c.hour = hour
        c.minute = minute
        return calendar.date(from: c)!
    }
}
