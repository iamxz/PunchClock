import Foundation

public enum PunchTarget {
    /// 菜单栏圆形按钮的目标项：待办优先；都完成后按时间补打（12 点前上班，之后下班）。
    public static func resolve(record: DayRecord,
                               now: Date,
                               minWorkDuration: TimeInterval = Settings.default.minWorkDuration,
                               calendar: Calendar = .current) -> PunchTask {
        if !record.morningDone { return .morning }
        if !PunchRules.isEveningComplete(record, minWorkDuration: minWorkDuration) { return .evening }
        let hour = calendar.component(.hour, from: now)
        return hour < 12 ? .morning : .evening
    }
}
