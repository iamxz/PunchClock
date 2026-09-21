import Foundation

/// 健康提醒内容（只以 toast 弱提示展示，不进全屏遮罩；全屏遮罩仅承载考勤）。
public struct HealthAlert: Identifiable, Equatable {
    public enum Kind: Equatable { case water, movement }

    public let kind: Kind
    public let title: String
    public let body: String
    public let repeatIntervalSeconds: TimeInterval

    public var id: Int { kind == .water ? 0 : 1 }

    public init(kind: Kind, title: String, body: String, repeatIntervalSeconds: TimeInterval) {
        self.kind = kind
        self.title = title
        self.body = body
        self.repeatIntervalSeconds = repeatIntervalSeconds
    }

    /// 忽略动态文案（如历分钟数），仅按提醒种类判断两组提醒是否为同一集合。
    /// 用于「内容在刷新、但不应再次抢焦点」的判定。
    public static func sameIdentity(_ a: [HealthAlert], _ b: [HealthAlert]) -> Bool {
        a.map(\.kind) == b.map(\.kind)
    }

    /// 取最短重复间隔；无提醒时回退到 fallback（如打卡重复间隔）。
    public static func minimumRepeatInterval(_ intervals: [TimeInterval], fallback: TimeInterval) -> TimeInterval {
        intervals.min() ?? fallback
    }
}