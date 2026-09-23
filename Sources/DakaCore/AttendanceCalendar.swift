import Foundation

/// 单日考勤状态，用于日历组件渲染。
public enum AttendanceStatus: String, CaseIterable, Equatable, Sendable {
    /// 非工作日 / 未来未到期的工作日：无需标记。
    case none
    /// 已完整打卡（上班 + 合格下班）。
    case done
    /// 应打卡却未打卡，且打卡窗口已过期。
    case missed
    /// 工作日、今天、窗口未过：待打卡。
    case pending
    /// 请假（当天应工作时长被请假全部抵扣，无需打卡）。
    case leave
}

/// 日历中的单个单元格数据（纯数据，无 UI 依赖，便于测试）。
public struct AttendanceDayCell: Equatable, Sendable {
    public let date: Date
    public let dateKey: String
    public let day: Int
    /// Calendar.weekday：Sun=1 ... Sat=7。
    public let weekday: Int
    public let isWorkday: Bool
    public let status: AttendanceStatus
    public let morningDoneAt: Date?
    public let eveningDoneAt: Date?
    public let isToday: Bool
    public let isFuture: Bool
    /// 当天有效（裁剪到当天）的请假片段，用于 tooltip 与右键菜单。
    public let leaveSlices: [LeaveSlice]
    /// 当天请假占应工作时长比例；非工作日为 0。
    public let leaveFraction: Double

    public init(date: Date,
                dateKey: String,
                day: Int,
                weekday: Int,
                isWorkday: Bool,
                status: AttendanceStatus,
                morningDoneAt: Date?,
                eveningDoneAt: Date?,
                isToday: Bool,
                isFuture: Bool,
                leaveSlices: [LeaveSlice] = [],
                leaveFraction: Double = 0) {
        self.date = date
        self.dateKey = dateKey
        self.day = day
        self.weekday = weekday
        self.isWorkday = isWorkday
        self.status = status
        self.morningDoneAt = morningDoneAt
        self.eveningDoneAt = eveningDoneAt
        self.isToday = isToday
        self.isFuture = isFuture
        self.leaveSlices = leaveSlices
        self.leaveFraction = leaveFraction
    }
}

/// 某月的日历网格（含前置/后置补齐的 nil 单元格，按周分行）。
public struct MonthGrid: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let firstWeekday: Int
    public let weeks: [[AttendanceDayCell?]]

    public init(year: Int, month: Int, firstWeekday: Int, weeks: [[AttendanceDayCell?]]) {
        self.year = year
        self.month = month
        self.firstWeekday = firstWeekday
        self.weeks = weeks
    }
}

public enum AttendanceCalendar {
    /// 计算某月日历网格。统计区间即该月的 1 号 ~ 月末。
    /// - Parameters:
    ///   - month: 任意落在目标月份的日期，取其年/月。
    ///   - now: 当前时间，用于判定今天 / 未来 / 缺卡窗口。
    ///   - leaves: 全部请假记录（含未来），用于判定请假与抵扣工时。
    public static func monthGrid(records: [String: DayRecord],
                                 settings: Settings,
                                 leaves: [LeaveRecord],
                                 month: Date,
                                 now: Date,
                                 calendar: Calendar = .current) -> MonthGrid {
        let comps = calendar.dateComponents([.year, .month], from: month)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else {
            return MonthGrid(year: year, month: month, firstWeekday: 1, weeks: [])
        }

        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 0
        let firstWeekday = calendar.component(.weekday, from: monthStart) // 1..7, Sun..Sat
        let todayMidnight = calendar.startOfDay(for: now)

        var flat: [AttendanceDayCell?] = []
        for _ in 0..<(firstWeekday - 1) { flat.append(nil) }

        for day in 1...daysInMonth {
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
            flat.append(makeCell(date: date, records: records, settings: settings,
                                 leaves: leaves, now: now,
                                 todayMidnight: todayMidnight, calendar: calendar))
        }

        while flat.count % 7 != 0 { flat.append(nil) }

        let weeks = stride(from: 0, to: flat.count, by: 7).map {
            Array(flat[$0..<min($0 + 7, flat.count)])
        }

        return MonthGrid(year: year, month: month, firstWeekday: firstWeekday, weeks: weeks)
    }

    private static func makeCell(date: Date,
                                 records: [String: DayRecord],
                                 settings: Settings,
                                 leaves: [LeaveRecord],
                                 now: Date,
                                 todayMidnight: Date,
                                 calendar: Calendar) -> AttendanceDayCell {
        let key = DakaDate.key(for: date, calendar: calendar)
        let record = records[key] ?? DayRecord()
        let weekday = DakaDate.weekday(of: date, calendar: calendar)
        let isWorkday = settings.isWorkday(date, calendar: calendar)
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let isFuture = date > todayMidnight

        let fullDayLeave = AttendanceRule.isFullDayLeave(settings, on: date,
                                                         leaves: leaves, calendar: calendar)
        let daySlices = LeaveRules.slices(on: date, in: leaves, calendar: calendar)

        let status: AttendanceStatus
        if fullDayLeave {
            status = .leave
        } else if !isWorkday {
            status = .none
        } else {
            let completedBoth = record.morningDone &&
                AttendanceRule.isEveningComplete(record, settings: settings, on: date,
                                                 leaves: leaves, calendar: calendar)
            if completedBoth {
                status = .done
            } else if isFuture {
                status = .none
            } else if isToday {
                let expectedLeave = AttendanceRule.expectedLeave(record, settings: settings, on: date,
                                                                 leaves: leaves, calendar: calendar)
                let expired = expectedLeave.map { now >= $0 } ?? false
                status = expired ? .missed : .pending
            } else {
                status = .missed
            }
        }

        let effectiveEvening = AttendanceRule.effectiveEveningPunch(record, settings: settings, on: date,
                                                                    leaves: leaves, calendar: calendar)

        return AttendanceDayCell(date: date, dateKey: key, day: calendar.component(.day, from: date),
                                 weekday: weekday, isWorkday: isWorkday, status: status,
                                 morningDoneAt: record.morningDoneAt, eveningDoneAt: effectiveEvening,
                                 isToday: isToday, isFuture: isFuture,
                                 leaveSlices: daySlices,
                                 leaveFraction: isWorkday
                                    ? AttendanceRule.leaveFraction(settings, on: date,
                                                                   leaves: leaves, calendar: calendar)
                                    : 0)
    }
}
