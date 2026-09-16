import Foundation

/// 今天已工作时长与圆环进度。未打上班卡即无意义。
public enum WorkProgress {
    /// 已工作时长；未打上班卡时 nil。
    /// 终点：若有合格下班卡取之（实际总时长），否则取 now。
    public static func elapsed(_ record: DayRecord,
                               now: Date,
                               minWorkDuration: TimeInterval) -> TimeInterval? {
        guard let morning = record.morningDoneAt else { return nil }
        let end = PunchRules.effectiveEveningPunch(record, minWorkDuration: minWorkDuration) ?? now
        return max(0, end.timeIntervalSince(morning))
    }

    /// 圆环进度 0...1；未打上班卡为 0，最少工时为 0 时视为 1。
    public static func fraction(_ record: DayRecord,
                                now: Date,
                                minWorkDuration: TimeInterval) -> Double {
        guard let elapsed = elapsed(record, now: now, minWorkDuration: minWorkDuration) else {
            return 0
        }
        guard minWorkDuration > 0 else { return 1 }
        return min(1, elapsed / minWorkDuration)
    }
}
