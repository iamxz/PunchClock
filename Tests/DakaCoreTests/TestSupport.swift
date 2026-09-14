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
}
