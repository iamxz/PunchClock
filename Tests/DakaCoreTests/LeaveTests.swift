import XCTest
@testable import DakaCore

/// 请假时间段的派生规则：裁剪、求交、边界。
final class LeaveTests: XCTestCase {
    private let cal = TestTime.calendar

    private func leave(_ y: Int, _ mo: Int, _ d: Int, _ h: Int,
                       _ y2: Int, _ mo2: Int, _ d2: Int, _ h2: Int,
                       m2: Int = 0) -> LeaveRecord {
        LeaveRecord(start: TestTime.date(y, mo, d, h),
                    end: TestTime.date(y2, mo2, d2, h2, m2))
    }

    func testSlicesClampToEachDay() {
        // 周一 16:00 → 周二 02:00
        let spans = [leave(2026, 9, 14, 16, 2026, 9, 15, 2)]
        let first = LeaveRules.slices(on: TestTime.monday, in: spans, calendar: cal)
        let second = LeaveRules.slices(on: TestTime.date(2026, 9, 15), in: spans, calendar: cal)

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].start, TestTime.date(2026, 9, 14, 16))
        XCTAssertEqual(first[0].end, TestTime.date(2026, 9, 15))
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].start, TestTime.date(2026, 9, 15))
        XCTAssertEqual(second[0].end, TestTime.date(2026, 9, 15, 2))
        XCTAssertTrue(LeaveRules.slices(on: TestTime.date(2026, 9, 13), in: spans, calendar: cal).isEmpty)
    }

    func testMidnightBoundaryBelongsToOneDayOnly() {
        // 整天请假 [周一 00:00, 周二 00:00) 不应在周二再出现一次。
        let fullDay = [leave(2026, 9, 14, 0, 2026, 9, 15, 0)]
        XCTAssertEqual(LeaveRules.slices(on: TestTime.monday, in: fullDay, calendar: cal).count, 1)
        XCTAssertTrue(LeaveRules.slices(on: TestTime.date(2026, 9, 15), in: fullDay, calendar: cal).isEmpty)
        XCTAssertTrue(LeaveRules.records(intersecting: TestTime.date(2026, 9, 15),
                                        in: fullDay, calendar: cal).isEmpty)
    }

    func testInvalidRangeYieldsNothing() {
        let equal = LeaveRecord(start: TestTime.monday, end: TestTime.monday)
        let reversed = LeaveRecord(start: TestTime.date(2026, 9, 15), end: TestTime.monday)
        for bad in [equal, reversed] {
            XCTAssertTrue(LeaveRules.slices(on: TestTime.monday, in: [bad], calendar: cal).isEmpty)
            XCTAssertTrue(LeaveRules.records(intersecting: TestTime.monday, in: [bad], calendar: cal).isEmpty)
            XCTAssertEqual(LeaveRules.naturalDays(of: bad), 0)
        }
    }

    func testOverlappingSlicesSurviveUnmergedAndSorted() {
        let later = leave(2026, 9, 14, 14, 2026, 9, 14, 16)
        let earlier = leave(2026, 9, 14, 9, 2026, 9, 14, 15)
        let slices = LeaveRules.slices(on: TestTime.monday, in: [later, earlier], calendar: cal)
        XCTAssertEqual(slices.count, 2)
        XCTAssertEqual(slices[0].start, TestTime.date(2026, 9, 14, 9))
        XCTAssertEqual(slices[1].start, TestTime.date(2026, 9, 14, 14))
    }

    func testContainsIsHalfOpen() {
        let slices = LeaveRules.slices(on: TestTime.monday,
                                      in: [leave(2026, 9, 14, 9, 2026, 9, 14, 11)],
                                      calendar: cal)
        XCTAssertTrue(LeaveRules.contains(TestTime.date(2026, 9, 14, 9), slices: slices))
        XCTAssertTrue(LeaveRules.contains(TestTime.date(2026, 9, 14, 10, 59), slices: slices))
        XCTAssertFalse(LeaveRules.contains(TestTime.date(2026, 9, 14, 11), slices: slices))
        XCTAssertFalse(LeaveRules.contains(TestTime.date(2026, 9, 14, 8, 59), slices: slices))
    }

    func testOverlapClampsToZero() {
        let day = (TestTime.date(2026, 9, 14, 9), TestTime.date(2026, 9, 14, 18))
        XCTAssertEqual(LeaveRules.overlap(day, (TestTime.date(2026, 9, 14, 16),
                                               TestTime.date(2026, 9, 14, 20))), 2 * 3600, accuracy: 1)
        XCTAssertEqual(LeaveRules.overlap(day, (TestTime.date(2026, 9, 14, 7),
                                                TestTime.date(2026, 9, 14, 9))), 0, accuracy: 1)
        XCTAssertEqual(LeaveRules.overlap(day, (TestTime.date(2026, 9, 14, 18),
                                                TestTime.date(2026, 9, 14, 19))), 0, accuracy: 1)
    }

    func testRecordsIntersectingReturnsWholeCrossDayRecord() {
        // 周一 09:00 → 周三 18:00：周一/周二/周三都应拿到整条记录。
        let span = leave(2026, 9, 14, 9, 2026, 9, 16, 18)
        for day in [14, 15, 16] {
            let found = LeaveRules.records(intersecting: TestTime.date(2026, 9, day),
                                           in: [span], calendar: cal)
            XCTAssertEqual(found.count, 1, "day \(day)")
            XCTAssertEqual(found[0], span)
        }
        XCTAssertTrue(LeaveRules.records(intersecting: TestTime.date(2026, 9, 17),
                                        in: [span], calendar: cal).isEmpty)
    }

    func testNaturalDays() {
        XCTAssertEqual(LeaveRules.naturalDays(of: leave(2026, 9, 14, 0, 2026, 9, 15, 0),
                                             calendar: cal), 1)
        XCTAssertEqual(LeaveRules.naturalDays(of: leave(2026, 9, 14, 9, 2026, 9, 14, 18),
                                             calendar: cal), 1)
        XCTAssertEqual(LeaveRules.naturalDays(of: leave(2026, 9, 14, 14, 2026, 9, 16, 9),
                                             calendar: cal), 3)
        // 结束正好落在某天的 00:00 时，那天不算被覆盖。
        XCTAssertEqual(LeaveRules.naturalDays(of: leave(2026, 9, 14, 14, 2026, 9, 16, 0),
                                             calendar: cal), 2)
    }

    func testLeaveRecordDecodesWithoutIDOrLabel() throws {
        let json = """
        {"start": "2026-09-14T01:00:00Z", "end": "2026-09-14T02:00:00Z"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(LeaveRecord.self, from: json)
        XCTAssertEqual(decoded.start.timeIntervalSince1970,
                       ISO8601DateFormatter().date(from: "2026-09-14T01:00:00Z")!.timeIntervalSince1970,
                       accuracy: 1)
        XCTAssertNil(decoded.label)
    }
}
