import Foundation

public enum PunchRules {
    /// 满足最少工时的最晚下班打卡；无上班卡或无合格下班卡时为 nil。
    public static func effectiveEveningPunch(_ record: DayRecord,
                                             minWorkDuration: TimeInterval) -> Date? {
        guard let morning = record.morningDoneAt else { return nil }
        return record.eveningPunches
            .filter { $0.timeIntervalSince(morning) >= minWorkDuration }
            .max()
    }

    public static func isEveningComplete(_ record: DayRecord,
                                         minWorkDuration: TimeInterval) -> Bool {
        effectiveEveningPunch(record, minWorkDuration: minWorkDuration) != nil
    }

}
