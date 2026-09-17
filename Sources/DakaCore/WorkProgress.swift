import Foundation

/// 今天已工作时长与圆环进度。未打上班卡即无意义。
public enum WorkProgress {
    /// 已工作时长；未打上班卡时 nil。
    /// 终点：若有合格下班卡取之（实际总时长），否则取 now。
    public static func elapsed(_ record: DayRecord,
                               now: Date,
                               settings: Settings,
                               calendar: Calendar = .current) -> TimeInterval? {
        guard let morning = record.morningDoneAt else { return nil }
        let end = AttendanceRule.effectiveEveningPunch(record, settings: settings, on: now, calendar: calendar) ?? now
        return max(0, end.timeIntervalSince(morning))
    }

    /// 圆环进度 0...1；未打上班卡为 0，最少工时为 0 时视为 1。
    public static func fraction(_ record: DayRecord,
                                now: Date,
                                settings: Settings,
                                calendar: Calendar = .current) -> Double {
        let minWorkDuration = settings.workDuration
        guard let elapsed = elapsed(record, now: now, settings: settings, calendar: calendar) else {
            return 0
        }
        guard minWorkDuration > 0 else { return 1 }
        return min(1, elapsed / minWorkDuration)
    }

    /// 显示文案：`4h` / `4.5h` / `45m`；负值按 `0m`。
    public static func hoursText(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((max(0, interval) / 60).rounded(.down))
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let hours = Double(totalMinutes) / 60
        if hours == hours.rounded() { return "\(Int(hours))h" }
        return String(format: "%.1fh", hours)
    }
}
