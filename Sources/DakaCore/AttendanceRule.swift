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

    /// 考勤起点：下班线、合格下班卡、进度环、工时统计共用的唯一基准。
    /// 按弹性方式分派，早到能不能早走、晚到顺延多少，全部只在这里决定一次。
    public static func effectiveStart(_ record: DayRecord,
                                      settings: Settings,
                                      on day: Date,
                                      calendar: Calendar = .current) -> Date? {
        guard let morning = record.morningDoneAt else { return nil }
        guard let start = windowStart(settings, on: day, calendar: calendar) else { return nil }
        switch settings.flexMode {
        case .elasticBoth:
            // 起点夹进「上班时间 ± 弹性时间」：早到不能更早走，晚到也不能更晚走。
            return min(max(morning, start.addingTimeInterval(-settings.flexDuration)),
                       start.addingTimeInterval(settings.flexDuration))
        case .elasticBackward:
            return max(start, morning)
        }
    }

    /// 当天工时：考勤起点 → 最后一张合格下班卡，如实反映在岗时长，超出应工作时长也不截断。
    /// 没有上班卡或没有合格下班卡时为 nil。统计、日历格都走这一条，别处不要再自己相减。
    public static func workDuration(_ record: DayRecord,
                                    settings: Settings,
                                    on day: Date,
                                    leaves: [LeaveRecord],
                                    calendar: Calendar = .current) -> TimeInterval? {
        guard let start = effectiveStart(record, settings: settings, on: day, calendar: calendar),
              let evening = effectiveEveningPunch(record, settings: settings, on: day,
                                                  leaves: leaves, calendar: calendar),
              evening >= start else { return nil }
        return evening.timeIntervalSince(start)
    }

    /// 迟到多久：上班卡晚于「上班时间 + 弹性时间」的超出量，否则 nil。
    /// 是否记迟到由 `recordsLateArrival` 单独决定，与弹性方式无关；没上班卡时无从判迟到。
    public static func lateBy(_ record: DayRecord,
                              settings: Settings,
                              on day: Date,
                              calendar: Calendar = .current) -> TimeInterval? {
        guard settings.recordsLateArrival,
              let morning = record.morningDoneAt,
              let deadline = windowStart(settings, on: day, calendar: calendar)?
                .addingTimeInterval(settings.flexDuration) else { return nil }
        return morning > deadline ? morning.timeIntervalSince(deadline) : nil
    }

    public static func isLate(_ record: DayRecord,
                              settings: Settings,
                              on day: Date,
                              calendar: Calendar = .current) -> Bool {
        lateBy(record, settings: settings, on: day, calendar: calendar) != nil
    }

    public static func expectedLeave(_ record: DayRecord,
                                     settings: Settings,
                                     on day: Date,
                                     leaves: [LeaveRecord],
                                     calendar: Calendar = .current) -> Date? {
        effectiveStart(record, settings: settings, on: day, calendar: calendar)?
            .addingTimeInterval(requiredWorkDuration(settings, on: day,
                                                      leaves: leaves, calendar: calendar))
    }

    // MARK: - 请假抵扣

    /// 当天「应上班窗口」`[workStartTime, workStartTime + workDuration]` 内被请假覆盖的秒数，
    /// 封顶 `workDuration` —— 重叠或超长的请假不会重复计时。
    ///
    /// 固定以 canonical 窗口求交，不随打卡时刻收缩、也不迭代定点，避免「17:30–18:30 请假」
    /// 这类区间来回抖动；迟到由 `effectiveStart` 负责顺延。沿用全应用的单日窗口假设：
    /// 请假片段只与当天求交，跨零点的班次不在本函数管辖内。
    public static func leaveDuration(_ settings: Settings,
                                     on day: Date,
                                     leaves: [LeaveRecord],
                                     calendar: Calendar = .current) -> TimeInterval {
        guard let start = windowStart(settings, on: day, calendar: calendar) else { return 0 }
        let required = settings.workDuration
        let window = (start, start.addingTimeInterval(required))
        let covered = LeaveRules.slices(on: day, in: leaves, calendar: calendar)
            .reduce(TimeInterval(0)) { $0 + LeaveRules.overlap(window, ($1.start, $1.end)) }
        return min(required, covered)
    }

    /// 扣除请假后当天仍需工作的秒数。
    public static func requiredWorkDuration(_ settings: Settings,
                                            on day: Date,
                                            leaves: [LeaveRecord],
                                            calendar: Calendar = .current) -> TimeInterval {
        max(0, settings.workDuration - leaveDuration(settings, on: day,
                                                     leaves: leaves, calendar: calendar))
    }

    /// 当天请假占应工作时长的比例（0...1）；「半天」即 0.5。
    /// 非工作日不过问这里，由统计与日历各自决定怎么用。
    public static func leaveFraction(_ settings: Settings,
                                    on day: Date,
                                    leaves: [LeaveRecord],
                                    calendar: Calendar = .current) -> Double {
        let required = settings.workDuration
        guard required > 0 else { return 0 }
        return leaveDuration(settings, on: day, leaves: leaves, calendar: calendar) / required
    }

    /// 整天请假：应工作时长被请假扣光，这一天不需要任何打卡。
    public static func isFullDayLeave(_ settings: Settings,
                                      on day: Date,
                                      leaves: [LeaveRecord],
                                      calendar: Calendar = .current) -> Bool {
        leaveDuration(settings, on: day, leaves: leaves, calendar: calendar)
            >= settings.workDuration
    }

    /// 合格下班卡：打卡时刻不早于「考勤起点 + 扣除请假后应工作的时长」。
    /// `start` 必须是 `effectiveStart`（考勤起点）而不是原始上班卡，否则早到会换提前的下班线。
    /// 只比较绝对时刻，不依赖日历时区，因此调用方传入的日历时区
    /// 与打卡记录构造时区不一致时仍能正确判定。
    public static func isQualifyingEveningPunch(_ punch: Date,
                                                start: Date,
                                                requiredWorkDuration: TimeInterval) -> Bool {
        punch >= start.addingTimeInterval(requiredWorkDuration)
    }

    public static func effectiveEveningPunch(_ record: DayRecord,
                                             settings: Settings,
                                             on day: Date,
                                             leaves: [LeaveRecord],
                                             calendar: Calendar = .current) -> Date? {
        guard let start = effectiveStart(record, settings: settings, on: day, calendar: calendar) else { return nil }
        let required = requiredWorkDuration(settings, on: day, leaves: leaves, calendar: calendar)
        return record.eveningPunches.filter {
            isQualifyingEveningPunch($0, start: start, requiredWorkDuration: required)
        }.max()
    }

    public static func isEveningComplete(_ record: DayRecord,
                                         settings: Settings,
                                         on day: Date,
                                         leaves: [LeaveRecord],
                                         calendar: Calendar = .current) -> Bool {
        effectiveEveningPunch(record, settings: settings, on: day,
                              leaves: leaves, calendar: calendar) != nil
    }
}
