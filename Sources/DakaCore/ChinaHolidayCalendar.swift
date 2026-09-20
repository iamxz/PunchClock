import Foundation

/// 内置节假日条目的类型。
public enum HolidayKind: String, Codable, Sendable {
    /// 法定假日（休息）。
    case holiday
    /// 调休补班（上班）。
    case makeup
}

/// 单条节假日/调休记录，按 "yyyy-MM-dd" 索引。
public struct HolidayEntry: Codable, Sendable, Equatable {
    public let date: String
    public let kind: HolidayKind
    public let name: String

    public init(date: String, kind: HolidayKind, name: String) {
        self.date = date
        self.kind = kind
        self.name = name
    }
}

/// 某一天在「标准日历」下的判定类型。
public enum WorkdayDayType: Equatable, Sendable {
    /// 正常工作日（基础星期内，非节假日）。
    case workday
    /// 常规休息日（周末，非调休补班）。
    case weekend
    /// 法定假日（休息），携带节日名。
    case holiday(name: String)
    /// 调休补班（上班），携带说明。
    case makeupWorkday(name: String)

    /// 该类型当天是否应上班。
    public var isWorkday: Bool {
        switch self {
        case .workday, .makeupWorkday: return true
        case .weekend, .holiday: return false
        }
    }

    /// 简短标记，用于日历单元格。
    public var badge: String {
        switch self {
        case .workday: return "班"
        case .weekend: return "休"
        case .holiday: return "休"
        case .makeupWorkday: return "班"
        }
    }

    /// 关联的节日/调休名称（用于提示）。
    public var title: String? {
        switch self {
        case .holiday(let n), .makeupWorkday(let n): return n
        default: return nil
        }
    }
}

/// 标准工作日日历引擎。
///
/// 判定优先级：
/// 1. 内置中国法定节假日/调休（`chinaHolidays`）。
/// 2. 基础星期模式（`baseWorkdays`，默认周一至周五）。
public struct WorkdayCalendar: Sendable {
    public var baseWorkdays: Set<Int>

    /// 内置的中国法定节假日与调休数据（2025、2026 年，官方公布口径）。
    public static let chinaHolidays: [String: HolidayEntry] = ChinaHolidayCalendarBuilder.build()

    public init(baseWorkdays: Set<Int> = [2, 3, 4, 5, 6]) {
        self.baseWorkdays = baseWorkdays
    }

    /// 某天是否应上班。
    public func isWorkday(_ date: Date, calendar: Calendar = .current) -> Bool {
        let key = DakaDate.key(for: date, calendar: calendar)
        if let entry = WorkdayCalendar.chinaHolidays[key] {
            return entry.kind == .makeup
        }
        let weekday = DakaDate.weekday(of: date, calendar: calendar)
        return baseWorkdays.contains(weekday)
    }

    /// 某天的详细类型（含节假日/调休信息）。
    public func dayType(_ date: Date, calendar: Calendar = .current) -> WorkdayDayType {
        let key = DakaDate.key(for: date, calendar: calendar)
        if let entry = WorkdayCalendar.chinaHolidays[key] {
            return entry.kind == .makeup
                ? .makeupWorkday(name: entry.name)
                : .holiday(name: entry.name)
        }
        let weekday = DakaDate.weekday(of: date, calendar: calendar)
        return baseWorkdays.contains(weekday) ? .workday : .weekend
    }
}

/// 中国节假日数据构建器（集中维护，便于后续年份扩展）。
enum ChinaHolidayCalendarBuilder {
    static func build() -> [String: HolidayEntry] {
        var dict: [String: HolidayEntry] = [:]
        func add(_ keys: [String], _ kind: HolidayKind, _ name: String) {
            for k in keys { dict[k] = HolidayEntry(date: k, kind: kind, name: name) }
        }

        // MARK: - 2026 年（国务院办公厅 2025-11-04 通知）
        // 元旦：1/1–1/3 放假，1/4 补班
        add(["2026-01-01", "2026-01-02", "2026-01-03"], .holiday, "元旦")
        add(["2026-01-04"], .makeup, "元旦调休")
        // 春节：2/15(除夕)–2/23 放假，2/14、2/28 补班
        add(["2026-02-15", "2026-02-16", "2026-02-17", "2026-02-18", "2026-02-19",
             "2026-02-20", "2026-02-21", "2026-02-22", "2026-02-23"], .holiday, "春节")
        add(["2026-02-14", "2026-02-28"], .makeup, "春节调休")
        // 清明节：4/4–4/6 放假，不调休
        add(["2026-04-04", "2026-04-05", "2026-04-06"], .holiday, "清明节")
        // 劳动节：5/1–5/5 放假，5/9 补班
        add(["2026-05-01", "2026-05-02", "2026-05-03", "2026-05-04", "2026-05-05"], .holiday, "劳动节")
        add(["2026-05-09"], .makeup, "劳动节调休")
        // 端午节：6/19–6/21 放假，不调休
        add(["2026-06-19", "2026-06-20", "2026-06-21"], .holiday, "端午节")
        // 中秋节：9/25–9/27 放假，不调休
        add(["2026-09-25", "2026-09-26", "2026-09-27"], .holiday, "中秋节")
        // 国庆节：10/1–10/7 放假，9/20、10/10 补班
        add(["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-04", "2026-10-05",
             "2026-10-06", "2026-10-07"], .holiday, "国庆节")
        add(["2026-09-20", "2026-10-10"], .makeup, "国庆节调休")

        // MARK: - 2025 年（国务院办公厅 2024-11-12 通知）
        // 元旦：1/1 放假 1 天，不调休
        add(["2025-01-01"], .holiday, "元旦")
        // 春节：1/28(除夕)–2/4 放假，1/26、2/8 补班
        add(["2025-01-28", "2025-01-29", "2025-01-30", "2025-01-31", "2025-02-01",
             "2025-02-02", "2025-02-03", "2025-02-04"], .holiday, "春节")
        add(["2025-01-26", "2025-02-08"], .makeup, "春节调休")
        // 清明节：4/4–4/6 放假，不调休
        add(["2025-04-04", "2025-04-05", "2025-04-06"], .holiday, "清明节")
        // 劳动节：5/1–5/5 放假，4/27 补班
        add(["2025-05-01", "2025-05-02", "2025-05-03", "2025-05-04", "2025-05-05"], .holiday, "劳动节")
        add(["2025-04-27"], .makeup, "劳动节调休")
        // 端午节：5/31–6/2 放假，不调休
        add(["2025-05-31", "2025-06-01", "2025-06-02"], .holiday, "端午节")
        // 国庆节、中秋节：10/1–10/8 放假，9/28、10/11 补班
        add(["2025-10-01", "2025-10-02", "2025-10-03", "2025-10-04", "2025-10-05",
             "2025-10-06", "2025-10-07", "2025-10-08"], .holiday, "国庆中秋")
        add(["2025-09-28", "2025-10-11"], .makeup, "国庆中秋调休")

        return dict
    }
}
