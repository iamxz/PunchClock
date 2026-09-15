import Foundation

public enum PetMood: String, CaseIterable, Sendable {
    case cheerful       // 上午
    case lunch          // 午间
    case focused        // 下午
    case relaxed        // 傍晚
    case sleepy         // 夜间/深夜
    case gentlePending  // 打卡窗口内未完成
    case hardPending    // 已过截止未完成
    case thirsty        // 该喝水了
    case restless       // 该起身走动了

    public var emoji: String {
        switch self {
        case .cheerful: return "🌞"
        case .lunch: return "😋"
        case .focused: return "💪"
        case .relaxed: return "😌"
        case .sleepy: return "😴"
        case .gentlePending: return "🤔"
        case .hardPending: return "😰"
        case .thirsty: return "🥵"
        case .restless: return "😤"
        }
    }

    /// 状态覆盖时间：打卡 hard > 打卡 gentle > 健康（喝水 > 走动）> 时间。
    public static func resolve(reminderState: ReminderState,
                               now: Date,
                               health: HealthStatus? = nil,
                               calendar: Calendar = .current) -> PetMood {
        if !reminderState.hard.isEmpty { return .hardPending }
        if !reminderState.gentle.isEmpty { return .gentlePending }
        if let health {
            if health.waterDue { return .thirsty }
            if health.movementDue { return .restless }
        }
        switch calendar.component(.hour, from: now) {
        case 5..<11: return .cheerful
        case 11..<13: return .lunch
        case 13..<17: return .focused
        case 17..<21: return .relaxed
        default: return .sleepy
        }
    }
}
