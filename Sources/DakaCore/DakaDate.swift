import Foundation

public enum DakaDate {
    /// "yyyy-MM-dd"，按给定日历/时区。
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 解析 "HH:mm"。
    public static func timeComponents(_ hhmm: String) -> (hour: Int, minute: Int)? {
        let parts = hhmm.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }

    /// 取 `day` 当天的 "HH:mm" 时刻。
    public static func date(on day: Date, at hhmm: String, calendar: Calendar = .current) -> Date? {
        guard let comps = timeComponents(hhmm) else { return nil }
        var dc = calendar.dateComponents([.year, .month, .day], from: day)
        dc.hour = comps.hour
        dc.minute = comps.minute
        dc.second = 0
        return calendar.date(from: dc)
    }

    /// Calendar 的 weekday：Sun=1 ... Sat=7。
    public static func weekday(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date)
    }
}
