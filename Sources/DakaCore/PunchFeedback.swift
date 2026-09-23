import Foundation

/// 打卡后若任务仍未完成，给出原因与还差多少的说明文案。
public enum PunchFeedback {
    public static func text(task: PunchTask,
                            record: DayRecord,
                            settings: Settings,
                            leaves: [LeaveRecord],
                            punchedAt: Date,
                            calendar: Calendar = .current) -> String? {
        switch task {
        case .morning:
            return nil
        case .evening:
            if AttendanceRule.isEveningComplete(record, settings: settings, on: punchedAt,
                                                leaves: leaves, calendar: calendar) {
                return nil
            }
            let time = timeText(punchedAt, calendar: calendar)
            let onLeave = AttendanceRule.leaveDuration(settings, on: punchedAt,
                                                        leaves: leaves, calendar: calendar)
            if onLeave >= settings.workDuration {
                // 只有用户自己又打了一张卡才会走到这里。
                return "已记录 \(time)；今天已整天请假，无需打卡。"
            }
            let need = AttendanceRule.requiredWorkDuration(settings, on: punchedAt,
                                                           leaves: leaves, calendar: calendar)
            let needHours = need / 3600
            let leaveNote = onLeave > 0 ? "今天请假 \(hoursText(onLeave / 3600)) 小时，" : ""
            guard let morning = record.morningDoneAt else {
                return "已记录 \(time)；今天还没有上班打卡，需先打上班卡；\(leaveNote)下班需满 \(hoursText(needHours)) 小时才算完成。"
            }
            let expectedLeave = AttendanceRule.expectedLeave(record, settings: settings, on: punchedAt,
                                                             leaves: leaves, calendar: calendar)
            let deadline = expectedLeave ?? morning.addingTimeInterval(need)
            return "已记录 \(time)；\(leaveNote)距上班满 \(hoursText(needHours)) 小时还差 \(remainingText(deadline.timeIntervalSince(punchedAt)))，满后自动完成。"
        }
    }

    private static func hoursText(_ hours: Double) -> String {
        hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
    }

    private static func remainingText(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "不足 1 分钟" }
        let totalMinutes = Int((seconds / 60).rounded(.up))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return m > 0 ? "\(h) 小时 \(m) 分钟" : "\(h) 小时"
        }
        return "\(m) 分钟"
    }

    private static func timeText(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
