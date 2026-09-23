import Foundation

/// 一条请假：起止时刻，可只占当天几小时，也可跨天/跨月。
/// 请假判定的唯一事实来源 —— 旧的 `DayRecord.skipped` 只在解码时迁移到这里。
public struct LeaveRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var start: Date
    public var end: Date
    /// 备注（年假 / 病假等）。nil 时不写入 JSON。
    public var label: String?

    public init(id: UUID = UUID(), start: Date, end: Date, label: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case id, start, end, label
    }

    /// 宽松解码：缺 id 或 label 时补默认值，不让整库因为一条手写记录而报废。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        self.start = try c.decode(Date.self, forKey: .start)
        self.end = try c.decode(Date.self, forKey: .end)
        let text = (try? c.decode(String.self, forKey: .label))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = (text?.isEmpty == false) ? text : nil
    }

    /// 非法区间（end <= start）允许存在于内存与 JSON 中，只是所有派生结果为空。
    public var isValid: Bool { end > start }
}

/// 一条请假与某个自然日求交后、裁剪到当天内的片段。
public struct LeaveSlice: Equatable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date

    public init(id: UUID, start: Date, end: Date) {
        self.id = id
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// 请假区间非法（结束不晚于开始）。UI 会先禁用保存，这里只是守住最后一道边界。
public enum LeaveError: Error, LocalizedError {
    case invalidRange

    public var errorDescription: String? {
        switch self {
        case .invalidRange: return "结束时间需晚于开始时间"
        }
    }
}

public enum LeaveRules {
    /// 与 `day` 所在自然日相交的请假片段，裁剪到当天边界并按 start 升序。
    /// 跨天请假会在每一天各出现一次；非法区间被丢弃。重叠片段不合并且保留原样。
    public static func slices(on day: Date,
                              in leaves: [LeaveRecord],
                              calendar: Calendar = .current) -> [LeaveSlice] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return leaves.compactMap { record in
            let start = max(record.start, dayStart)
            let end = min(record.end, dayEnd)
            guard end > start else { return nil }
            return LeaveSlice(id: record.id, start: start, end: end)
        }.sorted { $0.start < $1.start }
    }

    /// `moment` 是否落在请假期间。区间半开：含 start、不含 end。
    public static func contains(_ moment: Date, slices: [LeaveSlice]) -> Bool {
        slices.contains { moment >= $0.start && moment < $0.end }
    }

    /// 两个时间区间的交集秒数，负数钳到 0。
    public static func overlap(_ lhs: (Date, Date), _ rhs: (Date, Date)) -> TimeInterval {
        let start = max(lhs.0, rhs.0)
        let end = min(lhs.1, rhs.1)
        return max(0, end.timeIntervalSince(start))
    }

    /// 与某天相交的**完整**请假记录（取消请假时整条撤销、tooltip 显示原始区间）。
    public static func records(intersecting day: Date,
                               in leaves: [LeaveRecord],
                               calendar: Calendar = .current) -> [LeaveRecord] {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return leaves.filter { $0.isValid && $0.start < dayEnd && $0.end > dayStart }
            .sorted { $0.start < $1.start }
    }

    /// 该条请假覆盖的自然日数（0 表示非法区间）。
    public static func naturalDays(of record: LeaveRecord, calendar: Calendar = .current) -> Int {
        guard record.isValid else { return 0 }
        let from = calendar.startOfDay(for: record.start)
        // end 是开区间端点，因此取「end 前一秒」所在的那天。
        let to = calendar.startOfDay(for: record.end.addingTimeInterval(-1))
        return (calendar.dateComponents([.day], from: from, to: to).day ?? 0) + 1
    }
}
