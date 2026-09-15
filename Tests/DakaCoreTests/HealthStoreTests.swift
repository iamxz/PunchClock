import XCTest
@testable import DakaCore

final class HealthStoreTests: XCTestCase {
    private let cal = TestTime.calendar
    private var dir: URL!
    private var url: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("health.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testLogAndReload() throws {
        let t = TestTime.date(2026, 9, 14, 9, 10)
        let store = HealthStore(fileURL: url)
        try store.log(.water, at: t, calendar: cal)
        try store.log(.water, at: t.addingTimeInterval(3600), calendar: cal)
        try store.log(.movement, at: t, calendar: cal)

        let reloaded = HealthStore(fileURL: url)
        let rec = reloaded.record(for: t, calendar: cal)
        XCTAssertEqual(rec.cups, 2)
        XCTAssertEqual(rec.standCount, 1)
        XCTAssertEqual(reloaded.data.records["2026-09-14"]?.cups, 2)
    }

    func testUpdateSettings() throws {
        var s = HealthSettings.default
        s.waterGoalCups = 10
        let store = HealthStore(fileURL: url)
        try store.updateSettings(s)
        XCTAssertEqual(HealthStore(fileURL: url).data.settings.waterGoalCups, 10)
    }

    func testDayRolloverKeepsHistory() throws {
        let day1 = TestTime.date(2026, 9, 14, 9, 0)
        let day2 = TestTime.date(2026, 9, 15, 9, 0)
        let store = HealthStore(fileURL: url)
        try store.log(.water, at: day1, calendar: cal)
        XCTAssertEqual(store.record(for: day1, calendar: cal).cups, 1)
        XCTAssertEqual(store.record(for: day2, calendar: cal).cups, 0)
        XCTAssertEqual(HealthStore(fileURL: url).data.records.count, 1)
    }

    func testCorruptionRecovers() throws {
        try Data("not json".utf8).write(to: url)
        let recovered = HealthStore(fileURL: url)
        XCTAssertTrue(recovered.didRecoverFromCorruption)
        XCTAssertEqual(recovered.data.settings, .default)
        XCTAssertTrue(recovered.data.records.isEmpty)
    }

    func testCorruptionBackupURLIsExposed() throws {
        try Data("not json".utf8).write(to: url)
        let store = HealthStore(fileURL: url)
        let backup = try XCTUnwrap(store.corruptionBackupURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }

    func testMissingFileStartsEmpty() {
        let store = HealthStore(fileURL: url)
        XCTAssertFalse(store.didRecoverFromCorruption)
        XCTAssertTrue(store.data.records.isEmpty)
        XCTAssertEqual(store.data.settings, .default)
    }

    func testLogRollsBackInMemoryOnPersistFailure() throws {
        let blocker = dir.appendingPathComponent("blocker")
        try Data("x".utf8).write(to: blocker)
        let badURL = blocker.appendingPathComponent("health.json")
        let store = HealthStore(fileURL: badURL)

        let day = TestTime.date(2026, 9, 14, 9, 0)
        XCTAssertThrowsError(try store.log(.water, at: day, calendar: cal))
        XCTAssertEqual(store.record(for: day, calendar: cal).cups, 0)
    }
}
