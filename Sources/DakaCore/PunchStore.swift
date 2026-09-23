import Foundation

public final class PunchStore {
    public private(set) var data: DakaData
    public private(set) var didRecoverFromCorruption: Bool
    public private(set) var corruptionBackupURL: URL?
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let loaded = PunchStore.load(from: fileURL)
        self.data = loaded.data
        self.didRecoverFromCorruption = loaded.recovered
        self.corruptionBackupURL = loaded.backupURL
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Daka/data.json")
    }

    public func record(for date: Date, calendar: Calendar = .current) -> DayRecord {
        let key = DakaDate.key(for: date, calendar: calendar)
        return data.records[key] ?? DayRecord()
    }

    public func mark(_ task: PunchTask, at date: Date, calendar: Calendar = .current) throws {
        let key = DakaDate.key(for: date, calendar: calendar)
        let previous = data.records[key]
        var rec = previous ?? DayRecord()
        switch task {
        case .morning:
            rec.morningPunches.append(date)
        case .evening:
            rec.eveningPunches.append(date)
        }
        data.records[key] = rec
        try persist(rollingBack: { self.data.records[key] = previous })
    }

    public func updatePunch(_ task: PunchTask,
                            at index: Int,
                            to date: Date,
                            on day: Date,
                            calendar: Calendar = .current) throws {
        let key = DakaDate.key(for: day, calendar: calendar)
        let previous = data.records[key]
        var rec = previous ?? DayRecord()
        switch task {
        case .morning:
            guard rec.morningPunches.indices.contains(index) else { return }
            rec.morningPunches[index] = date
        case .evening:
            guard rec.eveningPunches.indices.contains(index) else { return }
            rec.eveningPunches[index] = date
        }
        data.records[key] = rec
        try persist(rollingBack: { self.data.records[key] = previous })
    }

    public func removePunch(_ task: PunchTask,
                            at index: Int,
                            on day: Date,
                            calendar: Calendar = .current) throws {
        let key = DakaDate.key(for: day, calendar: calendar)
        let previous = data.records[key]
        var rec = previous ?? DayRecord()
        switch task {
        case .morning:
            guard rec.morningPunches.indices.contains(index) else { return }
            rec.morningPunches.remove(at: index)
        case .evening:
            guard rec.eveningPunches.indices.contains(index) else { return }
            rec.eveningPunches.remove(at: index)
        }
        data.records[key] = rec
        try persist(rollingBack: { self.data.records[key] = previous })
    }

    // MARK: - 请假

    public var leaves: [LeaveRecord] { data.leaves }

    public func leaveSlices(on date: Date, calendar: Calendar = .current) -> [LeaveSlice] {
        LeaveRules.slices(on: date, in: data.leaves, calendar: calendar)
    }

    /// 与该天相交的完整请假记录（供右键菜单与 tooltip 使用）。
    public func leaves(intersecting date: Date, calendar: Calendar = .current) -> [LeaveRecord] {
        LeaveRules.records(intersecting: date, in: data.leaves, calendar: calendar)
    }

    /// 新增一条请假。`to <= from` 抛 `LeaveError.invalidRange`，不落盘、内存不变。
    /// 允许与已有请假重叠：抵扣时按应上班时长封顶，重复区间不会重复计时。
    @discardableResult
    public func addLeave(from: Date, to: Date, label: String? = nil) throws -> LeaveRecord {
        guard to > from else { throw LeaveError.invalidRange }
        let record = LeaveRecord(start: from, end: to, label: label)
        try mutateLeaves { $0.append(record) }
        return record
    }

    /// 修改一条请假；`id` 不存在时不写盘。
    public func updateLeave(id: UUID, from: Date, to: Date, label: String? = nil) throws {
        guard to > from else { throw LeaveError.invalidRange }
        guard data.leaves.contains(where: { $0.id == id }) else { return }
        try mutateLeaves { leaves in
            guard let index = leaves.firstIndex(where: { $0.id == id }) else { return }
            leaves[index].start = from
            leaves[index].end = to
            leaves[index].label = label
        }
    }

    public func removeLeave(id: UUID) throws {
        try mutateLeaves { $0.removeAll { $0.id == id } }
    }

    /// 取消与某天相交的**整条**请假（跨天请假日一次撤销）。返回删除条数。
    @discardableResult
    public func removeLeaves(on date: Date, calendar: Calendar = .current) throws -> Int {
        let doomed = Set(LeaveRules.records(intersecting: date, in: data.leaves, calendar: calendar)
            .map(\.id))
        guard !doomed.isEmpty else { return 0 }
        try mutateLeaves { $0.removeAll { doomed.contains($0.id) } }
        return doomed.count
    }

    private func mutateLeaves(_ mutate: (inout [LeaveRecord]) -> Void) throws {
        var next = data.leaves
        mutate(&next)
        next.sort { $0.start < $1.start }
        let previous = data.leaves
        data.leaves = next
        try persist(rollingBack: { self.data.leaves = previous })
    }

    public func updateSettings(_ settings: Settings) throws {
        let previous = data.settings
        data.settings = settings
        try persist(rollingBack: { self.data.settings = previous })
    }

    private func persist(rollingBack rollback: () -> Void) throws {
        do {
            try persist()
        } catch {
            rollback()
            throw error
        }
    }

    private func persist() throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let out = try encoder.encode(data)
        try out.write(to: fileURL, options: .atomic)
    }

    private struct LoadResult {
        var data: DakaData
        var recovered: Bool
        var backupURL: URL?
    }

    private static func load(from url: URL) -> LoadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return LoadResult(data: DakaData(), recovered: false, backupURL: nil)
        }
        guard let raw = try? Data(contentsOf: url) else {
            let backup = makeBackupURL(for: url)
            let moved = (try? fileManager.moveItem(at: url, to: backup)) != nil
            return LoadResult(data: DakaData(), recovered: true, backupURL: moved ? backup : nil)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return LoadResult(data: try decoder.decode(DakaData.self, from: raw),
                              recovered: false, backupURL: nil)
        } catch {
            let backup = makeBackupURL(for: url)
            let moved = (try? fileManager.moveItem(at: url, to: backup)) != nil
            return LoadResult(data: DakaData(), recovered: true, backupURL: moved ? backup : nil)
        }
    }

    private static func makeBackupURL(for url: URL) -> URL {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let suffix = UUID().uuidString.prefix(8)
        return url.deletingLastPathComponent()
            .appendingPathComponent("data.json.corrupt-\(stamp)-\(suffix)")
    }
}
