import XCTest
@testable import DakaCore

final class PunchStoreTests: XCTestCase {
    private var dir: URL!
    private var url: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("data.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testEmptyStoreStartsWithDefaults() {
        let store = PunchStore(fileURL: url)
        XCTAssertEqual(store.data.settings, Settings.default)
        XCTAssertTrue(store.data.records.isEmpty)
    }

    func testMarkAndReloadRoundTrip() throws {
        let at = TestTime.date(2026, 9, 14, 9, 1, 12)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: at, calendar: TestTime.calendar)

        let reloaded = PunchStore(fileURL: url)
        let record = reloaded.record(for: at, calendar: TestTime.calendar)
        XCTAssertTrue(record.morningDone)
        XCTAssertEqual(record.morningDoneAt?.timeIntervalSince1970 ?? 0,
                       at.timeIntervalSince1970, accuracy: 1.0)
        XCTAssertFalse(record.eveningDone)
    }

    func testMarkEvening() throws {
        let at = TestTime.date(2026, 9, 14, 18, 31)
        let store = PunchStore(fileURL: url)
        try store.mark(.evening, at: at, calendar: TestTime.calendar)
        XCTAssertTrue(store.record(for: at, calendar: TestTime.calendar).eveningDone)
    }

    func testSettingsPersist() throws {
        var settings = Settings.default
        settings.morningDeadline = "08:00"
        settings.enabled = false
        let store = PunchStore(fileURL: url)
        try store.updateSettings(settings)

        let reloaded = PunchStore(fileURL: url)
        XCTAssertEqual(reloaded.data.settings.morningDeadline, "08:00")
        XCTAssertFalse(reloaded.data.settings.enabled)
    }

    func testSetSkipped() throws {
        let day = TestTime.date(2026, 9, 14, 12, 0)
        let store = PunchStore(fileURL: url)
        try store.setSkipped(true, on: day, calendar: TestTime.calendar)
        XCTAssertTrue(store.record(for: day, calendar: TestTime.calendar).skipped)
        try store.setSkipped(false, on: day, calendar: TestTime.calendar)
        XCTAssertFalse(store.record(for: day, calendar: TestTime.calendar).skipped)
    }

    func testDayRolloverKeepsHistory() throws {
        let day1 = TestTime.date(2026, 9, 14, 9, 0)
        let day2 = TestTime.date(2026, 9, 15, 9, 0)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: day1, calendar: TestTime.calendar)

        XCTAssertTrue(store.record(for: day1, calendar: TestTime.calendar).morningDone)
        XCTAssertFalse(store.record(for: day2, calendar: TestTime.calendar).morningDone)

        let reloaded = PunchStore(fileURL: url)
        XCTAssertEqual(reloaded.data.records.count, 1)
        XCTAssertTrue(reloaded.data.records["2026-09-14"]?.morningDone ?? false)
    }

    func testCorruptFileIsBackedUpAndReset() throws {
        try "this is not json".data(using: .utf8)!.write(to: url)
        let store = PunchStore(fileURL: url)
        XCTAssertTrue(store.data.records.isEmpty)
        XCTAssertEqual(store.data.settings, Settings.default)

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("data.json.corrupt-") },
                      "expected a corrupt backup file, got \(files)")
    }

    func testWorkdaysRoundTrip() throws {
        var settings = Settings.default
        settings.workdays = [1, 3, 5]
        let store = PunchStore(fileURL: url)
        try store.updateSettings(settings)

        let reloaded = PunchStore(fileURL: url)
        XCTAssertEqual(reloaded.data.settings.workdays, [1, 3, 5])
    }

    func testRecordForUnknownDayDoesNotInsert() {
        let store = PunchStore(fileURL: url)
        _ = store.record(for: TestTime.date(2026, 9, 14, 9, 0), calendar: TestTime.calendar)
        XCTAssertTrue(store.data.records.isEmpty)
    }

    func testCorruptionBackupURLIsExposed() throws {
        try "not json".data(using: .utf8)!.write(to: url)
        let store = PunchStore(fileURL: url)
        XCTAssertTrue(store.didRecoverFromCorruption)
        let backup = try XCTUnwrap(store.corruptionBackupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }

    func testMarkRollsBackInMemoryOnPersistFailure() throws {
        let blocker = dir.appendingPathComponent("blocker")
        try "x".data(using: .utf8)!.write(to: blocker)
        let badURL = blocker.appendingPathComponent("data.json")
        let store = PunchStore(fileURL: badURL)

        let day = TestTime.date(2026, 9, 14, 9, 0)
        XCTAssertThrowsError(try store.mark(.morning, at: day, calendar: TestTime.calendar))
        XCTAssertFalse(store.record(for: day, calendar: TestTime.calendar).morningDone)
    }

    func testMorningPunchesAccumulateEarliestWins() throws {
        let first = TestTime.date(2026, 9, 14, 9, 0)
        let second = TestTime.date(2026, 9, 14, 10, 30)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: first, calendar: TestTime.calendar)
        try store.mark(.morning, at: second, calendar: TestTime.calendar)
        let record = store.record(for: first, calendar: TestTime.calendar)
        XCTAssertEqual(record.morningPunches.count, 2)
        XCTAssertEqual(record.morningDoneAt?.timeIntervalSince1970 ?? 0, first.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(record.eveningPunches.count, 0)

        let reloaded = PunchStore(fileURL: url)
        XCTAssertEqual(reloaded.record(for: first, calendar: TestTime.calendar).morningPunches.count, 2)
    }

    func testEveningPunchesAccumulateLatestWins() throws {
        let first = TestTime.date(2026, 9, 14, 17, 0)
        let second = TestTime.date(2026, 9, 14, 18, 10)
        let store = PunchStore(fileURL: url)
        try store.mark(.evening, at: first, calendar: TestTime.calendar)
        try store.mark(.evening, at: second, calendar: TestTime.calendar)
        let record = store.record(for: first, calendar: TestTime.calendar)
        XCTAssertEqual(record.eveningPunches.count, 2)
        XCTAssertEqual(record.eveningDoneAt?.timeIntervalSince1970 ?? 0, second.timeIntervalSince1970, accuracy: 1)

        let reloaded = PunchStore(fileURL: url)
        XCTAssertEqual(reloaded.record(for: first, calendar: TestTime.calendar).eveningPunches.count, 2)
    }

    func testLegacyRecordDecodesToPunchList() throws {
        let legacyJSON = """
        {
          "morningDone": true,
          "morningDoneAt": "2026-09-14T01:00:00Z",
          "eveningDone": false,
          "skipped": false
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DayRecord.self, from: legacyJSON)
        XCTAssertEqual(decoded.morningPunches.count, 1)
        XCTAssertTrue(decoded.morningDone)
        XCTAssertFalse(decoded.eveningDone)
        let expected = ISO8601DateFormatter().date(from: "2026-09-14T01:00:00Z")!
        XCTAssertEqual(decoded.morningPunches.first?.timeIntervalSince1970 ?? 0,
                       expected.timeIntervalSince1970, accuracy: 1)
    }
}
