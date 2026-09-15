import XCTest
@testable import DakaCore

final class HealthStoreTests: XCTestCase {
    private let cal = TestTime.calendar
    private var url: URL!
    private var store: HealthStore!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("health-\(UUID().uuidString).json")
        store = HealthStore(fileURL: url)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    func testLogAndReload() throws {
        let t = TestTime.date(2026, 9, 14, 9, 10)
        try store.log(.water, at: t, calendar: cal)
        try store.log(.water, at: t.addingTimeInterval(3600), calendar: cal)
        try store.log(.movement, at: t, calendar: cal)

        let reloaded = HealthStore(fileURL: url)
        let rec = reloaded.record(for: t, calendar: cal)
        XCTAssertEqual(rec.cups, 2)
        XCTAssertEqual(rec.standCount, 1)
    }

    func testUpdateSettings() throws {
        var s = HealthSettings.default
        s.waterGoalCups = 10
        try store.updateSettings(s)
        XCTAssertEqual(HealthStore(fileURL: url).data.settings.waterGoalCups, 10)
    }

    func testCorruptionRecovers() throws {
        try Data("not json".utf8).write(to: url)
        let recovered = HealthStore(fileURL: url)
        XCTAssertTrue(recovered.didRecoverFromCorruption)
        XCTAssertEqual(recovered.data.settings, .default)
        XCTAssertTrue(recovered.data.records.isEmpty)
    }

    func testMissingFileStartsEmpty() {
        XCTAssertFalse(store.didRecoverFromCorruption)
        XCTAssertTrue(store.data.records.isEmpty)
    }
}
