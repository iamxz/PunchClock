import Foundation

public final class PunchStore {
    public private(set) var data: DakaData
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.data = PunchStore.load(from: fileURL)
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
        var rec = data.records[key] ?? DayRecord()
        switch task {
        case .morning:
            rec.morningDone = true
            rec.morningDoneAt = date
        case .evening:
            rec.eveningDone = true
            rec.eveningDoneAt = date
        }
        data.records[key] = rec
        try persist()
    }

    public func setSkipped(_ skipped: Bool, on date: Date, calendar: Calendar = .current) throws {
        let key = DakaDate.key(for: date, calendar: calendar)
        var rec = data.records[key] ?? DayRecord()
        rec.skipped = skipped
        data.records[key] = rec
        try persist()
    }

    public func updateSettings(_ settings: Settings) throws {
        data.settings = settings
        try persist()
    }

    private func persist() throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let out = try encoder.encode(data)
        // .atomic 内部即「写临时文件 + 原子替换」。
        try out.write(to: fileURL, options: .atomic)
    }

    private static func load(from url: URL) -> DakaData {
        guard let raw = try? Data(contentsOf: url) else { return DakaData() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(DakaData.self, from: raw)
        } catch {
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("data.json.corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: backup)
            return DakaData()
        }
    }
}
