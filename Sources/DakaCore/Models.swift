import Foundation

public enum PunchTask: String, Codable, CaseIterable, Hashable, Sendable {
    case morning
    case evening

    public var title: String {
        switch self {
        case .morning: return "上班打卡"
        case .evening: return "下班打卡"
        }
    }
}

public struct Settings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var workdays: Set<Int>          // Sun=1 ... Sat=7，默认 Mon..Fri
    public var morningTime: String         // "HH:mm"
    public var eveningTime: String
    public var launchPromptEarliest: String
    public var reminderIntervalSeconds: TimeInterval

    public init(enabled: Bool = true,
                workdays: Set<Int> = [2, 3, 4, 5, 6],
                morningTime: String = "09:00",
                eveningTime: String = "18:30",
                launchPromptEarliest: String = "06:00",
                reminderIntervalSeconds: TimeInterval = 120) {
        self.enabled = enabled
        self.workdays = workdays
        self.morningTime = morningTime
        self.eveningTime = eveningTime
        self.launchPromptEarliest = launchPromptEarliest
        self.reminderIntervalSeconds = reminderIntervalSeconds
    }

    public static let `default` = Settings()
}

public struct DayRecord: Codable, Equatable, Sendable {
    public var date: String
    public var morningDone: Bool
    public var morningDoneAt: Date?
    public var eveningDone: Bool
    public var eveningDoneAt: Date?
    public var skipped: Bool

    public init(date: String,
                morningDone: Bool = false,
                morningDoneAt: Date? = nil,
                eveningDone: Bool = false,
                eveningDoneAt: Date? = nil,
                skipped: Bool = false) {
        self.date = date
        self.morningDone = morningDone
        self.morningDoneAt = morningDoneAt
        self.eveningDone = eveningDone
        self.eveningDoneAt = eveningDoneAt
        self.skipped = skipped
    }

    public func isDone(_ task: PunchTask) -> Bool {
        switch task {
        case .morning: return morningDone
        case .evening: return eveningDone
        }
    }
}

public struct DakaData: Codable, Equatable, Sendable {
    public var settings: Settings
    public var records: [String: DayRecord]

    public init(settings: Settings = .default, records: [String: DayRecord] = [:]) {
        self.settings = settings
        self.records = records
    }
}
