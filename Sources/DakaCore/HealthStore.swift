import Foundation

public final class HealthStore {
    public private(set) var data: HealthData
    public private(set) var didRecoverFromCorruption: Bool
    public private(set) var corruptionBackupURL: URL?
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let loaded = HealthStore.load(from: fileURL)
        self.data = loaded.data
        self.didRecoverFromCorruption = loaded.recovered
        self.corruptionBackupURL = loaded.backupURL
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Daka/health.json")
    }

    public func record(for date: Date, calendar: Calendar = .current) -> DayHealthRecord {
        let key = DakaDate.key(for: date, calendar: calendar)
        return data.records[key] ?? DayHealthRecord()
    }

    public func log(_ kind: HealthLogKind, at date: Date, calendar: Calendar = .current) throws {
        let key = DakaDate.key(for: date, calendar: calendar)
        let previous = data.records[key]
        var rec = previous ?? DayHealthRecord()
        switch kind {
        case .water: rec.drinks.append(date)
        case .movement: rec.stands.append(date)
        }
        data.records[key] = rec
        try persist(rollingBack: { self.data.records[key] = previous })
    }

    public func updateSettings(_ settings: HealthSettings) throws {
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
        var data: HealthData
        var recovered: Bool
        var backupURL: URL?
    }

    private static func load(from url: URL) -> LoadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return LoadResult(data: HealthData(), recovered: false, backupURL: nil)
        }
        guard let raw = try? Data(contentsOf: url) else {
            let backup = makeBackupURL(for: url)
            let moved = (try? fileManager.moveItem(at: url, to: backup)) != nil
            return LoadResult(data: HealthData(), recovered: true, backupURL: moved ? backup : nil)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return LoadResult(data: try decoder.decode(HealthData.self, from: raw),
                              recovered: false, backupURL: nil)
        } catch {
            let backup = makeBackupURL(for: url)
            let moved = (try? fileManager.moveItem(at: url, to: backup)) != nil
            return LoadResult(data: HealthData(), recovered: true, backupURL: moved ? backup : nil)
        }
    }

    private static func makeBackupURL(for url: URL) -> URL {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let suffix = UUID().uuidString.prefix(8)
        return url.deletingLastPathComponent()
            .appendingPathComponent("health.json.corrupt-\(stamp)-\(suffix)")
    }
}
