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
        settings.flexMinutes = 45
        settings.enabled = false
        let store = PunchStore(fileURL: url)
        try store.updateSettings(settings)

        let reloaded = PunchStore(fileURL: url)
        XCTAssertEqual(reloaded.data.settings.flexMinutes, 45)
        XCTAssertFalse(reloaded.data.settings.enabled)
    }

    // MARK: - 请假

    func testAddLeaveRoundTripsThroughFile() throws {
        let store = PunchStore(fileURL: url)
        let added = try store.addLeave(from: TestTime.date(2026, 9, 14, 16),
                                       to: TestTime.date(2026, 9, 14, 18),
                                       label: "年假")
        XCTAssertEqual(store.leaves.count, 1)

        let reloaded = PunchStore(fileURL: url)
        XCTAssertEqual(reloaded.leaves.count, 1)
        XCTAssertEqual(reloaded.leaves[0].id, added.id)
        XCTAssertEqual(reloaded.leaves[0].label, "年假")
        XCTAssertEqual(reloaded.leaveSlices(on: TestTime.date(2026, 9, 14, 9),
                                           calendar: TestTime.calendar).first?.start,
                       TestTime.date(2026, 9, 14, 16))
    }

    func testAddLeaveRejectsInvalidRangeWithoutTouchingDisk() throws {
        let store = PunchStore(fileURL: url)
        XCTAssertThrowsError(try store.addLeave(from: TestTime.date(2026, 9, 14, 18),
                                                to: TestTime.date(2026, 9, 14, 18)))
        XCTAssertThrowsError(try store.addLeave(from: TestTime.date(2026, 9, 14, 18),
                                                to: TestTime.date(2026, 9, 14, 9)))
        XCTAssertTrue(store.leaves.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "非法输入不该留下文件")
    }

    func testUpdateLeaveReplacesRangeAndLabel() throws {
        let store = PunchStore(fileURL: url)
        let added = try store.addLeave(from: TestTime.date(2026, 9, 14, 16),
                                       to: TestTime.date(2026, 9, 14, 18),
                                       label: "事假")
        try store.updateLeave(id: added.id,
                              from: TestTime.date(2026, 9, 14, 13),
                              to: TestTime.date(2026, 9, 16, 9),
                              label: nil)

        let reloaded = PunchStore(fileURL: url)
        XCTAssertEqual(reloaded.leaves.count, 1)
        XCTAssertEqual(reloaded.leaves[0].start, TestTime.date(2026, 9, 14, 13))
        XCTAssertEqual(reloaded.leaves[0].end, TestTime.date(2026, 9, 16, 9))
        XCTAssertNil(reloaded.leaves[0].label)

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let first = try XCTUnwrap((raw?["leaves"] as? [[String: Any]])?.first)
        XCTAssertNil(first["label"], "无备注时不该写入 label 键")

        // id 不存在 / 区间非法都不该改动已有数据。
        try store.updateLeave(id: UUID(), from: TestTime.date(2026, 9, 20), to: TestTime.date(2026, 9, 21))
        XCTAssertThrowsError(try store.updateLeave(id: added.id,
                                                   from: TestTime.date(2026, 9, 20, 18),
                                                   to: TestTime.date(2026, 9, 20, 9)))
        XCTAssertEqual(PunchStore(fileURL: url).leaves.count, 1)
        XCTAssertEqual(PunchStore(fileURL: url).leaves[0].start, TestTime.date(2026, 9, 14, 13))
    }

    func testRemoveLeavesOnDayDeletesWholeCrossDayRecord() throws {
        let store = PunchStore(fileURL: url)
        try store.addLeave(from: TestTime.date(2026, 9, 14, 14), to: TestTime.date(2026, 9, 16, 9))
        try store.addLeave(from: TestTime.date(2026, 9, 20, 9), to: TestTime.date(2026, 9, 20, 12))

        // 取消中间那天的请假 → 整条跨天记录被撤销。
        XCTAssertEqual(try store.removeLeaves(on: TestTime.date(2026, 9, 15),
                                             calendar: TestTime.calendar), 1)
        XCTAssertEqual(store.leaves.count, 1)
        XCTAssertEqual(store.leaves[0].start, TestTime.date(2026, 9, 20, 9))
        XCTAssertEqual(PunchStore(fileURL: url).leaves.count, 1)

        // 没有请假的日子返回 0 且不写盘。
        XCTAssertEqual(try store.removeLeaves(on: TestTime.date(2026, 10, 1),
                                              calendar: TestTime.calendar), 0)
    }

    func testRemoveLeaveById() throws {
        let store = PunchStore(fileURL: url)
        let a = try store.addLeave(from: TestTime.date(2026, 9, 14, 9), to: TestTime.date(2026, 9, 14, 12))
        _ = try store.addLeave(from: TestTime.date(2026, 9, 15, 9), to: TestTime.date(2026, 9, 15, 12))
        try store.removeLeave(id: a.id)
        XCTAssertEqual(store.leaves.count, 1)
        XCTAssertEqual(store.leaves[0].start, TestTime.date(2026, 9, 15, 9))
    }

    func testLeavesStaySortedByStartAfterOutOfOrderAdds() throws {
        let store = PunchStore(fileURL: url)
        try store.addLeave(from: TestTime.date(2026, 9, 20, 9), to: TestTime.date(2026, 9, 20, 12))
        try store.addLeave(from: TestTime.date(2026, 9, 14, 9), to: TestTime.date(2026, 9, 14, 12))
        try store.addLeave(from: TestTime.date(2026, 9, 16, 9), to: TestTime.date(2026, 9, 16, 12))
        XCTAssertEqual(store.leaves.map(\.start),
                       [TestTime.date(2026, 9, 14, 9), TestTime.date(2026, 9, 16, 9), TestTime.date(2026, 9, 20, 9)])
    }

    func testAddLeaveRollsBackInMemoryOnPersistFailure() throws {
        let store = PunchStore(fileURL: url)
        try store.addLeave(from: TestTime.date(2026, 9, 14, 9), to: TestTime.date(2026, 9, 14, 12))

        try FileManager.default.removeItem(at: dir)
        try "x".data(using: .utf8)!.write(to: dir)

        XCTAssertThrowsError(try store.addLeave(from: TestTime.date(2026, 9, 15, 9),
                                                to: TestTime.date(2026, 9, 15, 12)))
        XCTAssertEqual(store.leaves.count, 1)
        XCTAssertEqual(store.leaves[0].start, TestTime.date(2026, 9, 14, 9))
    }

    func testLegacySkippedFileLoadsAsLeaveEndToEnd() throws {
        // 老用户升级：data.json 里只有 skipped:true，没有 leaves 键。
        let legacy = """
        {"settings":{"workdays":[2,3,4,5,6],"workStartTime":"09:00","workDurationHours":9,"flexMinutes":30},
         "records":{"2026-09-14":{"morningPunches":[],"eveningPunches":[],"skipped":true}}}
        """
        try legacy.data(using: .utf8)!.write(to: url)

        let store = PunchStore(fileURL: url)
        XCTAssertEqual(store.leaves.count, 1)
        // 迁移按 `.current` 日历推导当天边界，断言也跟着它走，才不依赖 CI 的时区。
        let dayStart = try XCTUnwrap(DakaDate.date(for: "2026-09-14", calendar: .current))
        let slices = store.leaveSlices(on: dayStart)
        XCTAssertEqual(slices.count, 1, "迁移出的整天请假应当能按天派生出片段")
        XCTAssertEqual(slices[0].start, dayStart)
        XCTAssertEqual(slices[0].duration, 24 * 3600, accuracy: 3600)
    }

    func testLeavesConvenienceMatchesLeaveRules() throws {
        let store = PunchStore(fileURL: url)
        let added = try store.addLeave(from: TestTime.date(2026, 9, 14, 14), to: TestTime.date(2026, 9, 16, 9))
        let day = TestTime.date(2026, 9, 15, 10)
        XCTAssertEqual(store.leaves(intersecting: day, calendar: TestTime.calendar).map(\.id), [added.id])
        XCTAssertEqual(store.leaveSlices(on: day, calendar: TestTime.calendar).count, 1)
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

    func testUpdatePunchReplacesTimeInPlace() throws {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let original = TestTime.date(2026, 9, 14, 9, 5)
        let corrected = TestTime.date(2026, 9, 14, 8, 50)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: original, calendar: TestTime.calendar)
        try store.updatePunch(.morning, at: 0, to: corrected, on: day, calendar: TestTime.calendar)

        let record = store.record(for: day, calendar: TestTime.calendar)
        XCTAssertEqual(record.morningPunches.count, 1)
        XCTAssertEqual(record.morningDoneAt?.timeIntervalSince1970 ?? 0,
                       corrected.timeIntervalSince1970, accuracy: 1)

        let reloaded = PunchStore(fileURL: url)
        XCTAssertEqual(reloaded.record(for: day, calendar: TestTime.calendar).morningDoneAt?.timeIntervalSince1970 ?? 0,
                       corrected.timeIntervalSince1970, accuracy: 1)
    }

    func testRemovePunchDeletesEntry() throws {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let first = TestTime.date(2026, 9, 14, 9, 0)
        let second = TestTime.date(2026, 9, 14, 9, 10)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: first, calendar: TestTime.calendar)
        try store.mark(.morning, at: second, calendar: TestTime.calendar)
        try store.removePunch(.morning, at: 0, on: day, calendar: TestTime.calendar)

        let record = store.record(for: day, calendar: TestTime.calendar)
        XCTAssertEqual(record.morningPunches.count, 1)
        XCTAssertEqual(record.morningDoneAt?.timeIntervalSince1970 ?? 0,
                       second.timeIntervalSince1970, accuracy: 1)

        let reloaded = PunchStore(fileURL: url)
        let reloadedRecord = reloaded.record(for: day, calendar: TestTime.calendar)
        XCTAssertEqual(reloadedRecord.morningPunches.count, 1)
        XCTAssertEqual(reloadedRecord.morningDoneAt?.timeIntervalSince1970 ?? 0,
                       second.timeIntervalSince1970, accuracy: 1)
    }

    func testRemoveLastMorningPunchMakesUndone() throws {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: day, calendar: TestTime.calendar)
        try store.removePunch(.morning, at: 0, on: day, calendar: TestTime.calendar)

        let record = store.record(for: day, calendar: TestTime.calendar)
        XCTAssertFalse(record.morningDone)
        XCTAssertNil(record.morningDoneAt)
    }

    func testUpdateAndRemoveOutOfRangeAreNoOp() throws {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: day, calendar: TestTime.calendar)
        let before = store.record(for: day, calendar: TestTime.calendar).morningPunches

        try store.updatePunch(.morning, at: 5, to: TestTime.date(2026, 9, 14, 10, 0),
                              on: day, calendar: TestTime.calendar)
        try store.removePunch(.morning, at: 5, on: day, calendar: TestTime.calendar)

        XCTAssertEqual(store.record(for: day, calendar: TestTime.calendar).morningPunches, before)

        try store.mark(.evening, at: day, calendar: TestTime.calendar)
        let eveningBefore = store.record(for: day, calendar: TestTime.calendar).eveningPunches
        try store.updatePunch(.evening, at: 9, to: TestTime.date(2026, 9, 14, 23, 0),
                              on: day, calendar: TestTime.calendar)
        try store.removePunch(.evening, at: 9, on: day, calendar: TestTime.calendar)
        XCTAssertEqual(store.record(for: day, calendar: TestTime.calendar).eveningPunches, eveningBefore)
    }

    func testUpdateAndRemoveEvening() throws {
        let day = TestTime.date(2026, 9, 14, 18, 0)
        let store = PunchStore(fileURL: url)
        try store.mark(.evening, at: TestTime.date(2026, 9, 14, 18, 0), calendar: TestTime.calendar)
        try store.mark(.evening, at: TestTime.date(2026, 9, 14, 18, 30), calendar: TestTime.calendar)

        try store.updatePunch(.evening, at: 1, to: TestTime.date(2026, 9, 14, 18, 45),
                              on: day, calendar: TestTime.calendar)
        XCTAssertEqual(store.record(for: day, calendar: TestTime.calendar).eveningDoneAt?.timeIntervalSince1970 ?? 0,
                       TestTime.date(2026, 9, 14, 18, 45).timeIntervalSince1970, accuracy: 1)

        try store.removePunch(.evening, at: 0, on: day, calendar: TestTime.calendar)
        XCTAssertEqual(store.record(for: day, calendar: TestTime.calendar).eveningPunches.count, 1)
    }

    func testUpdatePunchRollsBackInMemoryOnPersistFailure() throws {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: day, calendar: TestTime.calendar)

        try FileManager.default.removeItem(at: dir)
        try "x".data(using: .utf8)!.write(to: dir)

        let corrected = TestTime.date(2026, 9, 14, 8, 50)
        XCTAssertThrowsError(try store.updatePunch(.morning, at: 0, to: corrected,
                                                   on: day, calendar: TestTime.calendar))
        XCTAssertEqual(store.record(for: day, calendar: TestTime.calendar).morningDoneAt?.timeIntervalSince1970 ?? 0,
                       day.timeIntervalSince1970, accuracy: 1)
    }

    func testRemovePunchRollsBackInMemoryOnPersistFailure() throws {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: day, calendar: TestTime.calendar)

        try FileManager.default.removeItem(at: dir)
        try "x".data(using: .utf8)!.write(to: dir)

        XCTAssertThrowsError(try store.removePunch(.morning, at: 0, on: day, calendar: TestTime.calendar))
        XCTAssertTrue(store.record(for: day, calendar: TestTime.calendar).morningDone)
    }
}
