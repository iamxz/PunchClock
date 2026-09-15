import Foundation

/// 打卡后若任务仍未完成，给出原因与还差多少的说明文案。
public enum PunchFeedback {
    public static func text(task: PunchTask,
                            record: DayRecord,
                            settings: Settings,
                            punchedAt: Date,
                            calendar: Calendar = .current) -> String? {
        switch task {
        case .morning:
            return nil
        case .evening:
            if PunchRules.isEveningComplete(record, minWorkDuration: settings.minWorkDuration) {
                return nil
            }
            let hours = settings.minWorkDurationHours
            let time = timeFormatter.string(from: punchedAt)
            guard let morning = record.morningDoneAt else {
                return "已记录 \(time)；今天还没有上班打卡，需先打上班卡；下班需满 \(hoursText(hours)) 小时才算完成。"
            }
            let need = morning.addingTimeInterval(settings.minWorkDuration)
            let remaining = need.timeIntervalSince(punchedAt)
            return "已记录 \(time)；距上班满 \(hoursText(hours)) 小时还差 \(remainingText(remaining))，满后自动完成。"
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

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
