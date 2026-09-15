import Foundation

public enum PetMood: String, CaseIterable, Sendable {
    case cheerful       // 上午
    case lunch          // 午间
    case focused        // 下午
    case relaxed        // 傍晚
    case sleepy         // 夜间/深夜
    case gentlePending  // 打卡窗口内未完成
    case hardPending    // 已过截止未完成

    public var emoji: String {
        switch self {
        case .cheerful: return "🌞"
        case .lunch: return "😋"
        case .focused: return "💪"
        case .relaxed: return "😌"
        case .sleepy: return "😴"
        case .gentlePending: return "🤔"
        case .hardPending: return "😰"
        }
    }

    /// 打卡状态覆盖时间心情：hard > gentle > 时间。
    public static func resolve(reminderState: ReminderState,
                               now: Date,
                               calendar: Calendar = .current) -> PetMood {
        if !reminderState.hard.isEmpty { return .hardPending }
        if !reminderState.gentle.isEmpty { return .gentlePending }
        switch calendar.component(.hour, from: now) {
        case 5..<11: return .cheerful
        case 11..<13: return .lunch
        case 13..<17: return .focused
        case 17..<21: return .relaxed
        default: return .sleepy
        }
    }
}
