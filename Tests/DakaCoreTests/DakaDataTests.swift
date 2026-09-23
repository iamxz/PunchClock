import XCTest
@testable import DakaCore

/// 请假存储的解码与旧 `skipped` 标记迁移。
///
/// 迁移走 `Calendar.current`（与 `PunchStore` 加载数据时一致），因此这些断言都用
/// `.current` 推出锚点；若改用 `TestTime.calendar` 在 UTC 的 CI 上会差一天。
final class DakaDataTests: XCTestCase {
    private let current = Calendar.current

    private func decode(_ json: String) throws -> DakaData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DakaData.self, from: json.data(using: .utf8)!)
    }

    private func encode(_ data: DakaData) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let object = try JSONSerialization.jsonObject(with: encoder.encode(data))
        return (object as? [String: Any]) ?? [:]
    }

    func testLegacySkippedMigratesToFullDayLeave() throws {
        let data = try decode("""
        {"settings":{"workStartTime":"09:00"},
         "records":{"2026-09-14":{"morningPunches":[],"eveningPunches":[],"skipped":true}}}
        """)
        XCTAssertEqual(data.leaves.count, 1)
        let dayStart = try XCTUnwrap(DakaDate.date(for: "2026-09-14", calendar: current))
        let dayEnd = try XCTUnwrap(current.date(byAdding: .day, value: 1, to: dayStart))
        XCTAssertEqual(data.leaves[0].start, dayStart)
        XCTAssertEqual(data.leaves[0].end, dayEnd)
        // 迁移后的请假必须真的能被派生出片段。
        XCTAssertEqual(LeaveRules.slices(on: dayStart, in: data.leaves, calendar: current).count, 1)
    }

    func testLegacySkippedFalseCreatesNoLeave() throws {
        let data = try decode("""
        {"records":{"2026-09-14":{"morningPunches":[],"eveningPunches":[],"skipped":false}}}
        """)
        XCTAssertTrue(data.leaves.isEmpty)
    }

    func testMigrationSkippedWhenLeavesKeyPresentEvenIfEmpty() throws {
        // 关键：用户把请假取消干净后（leaves: []），残留的 skipped 标记不得复活。
        let data = try decode("""
        {"leaves":[],
         "records":{"2026-09-14":{"morningPunches":[],"eveningPunches":[],"skipped":true}}}
        """)
        XCTAssertTrue(data.leaves.isEmpty)
    }

    func testMalformedLeavesDropOnlyLeaves() throws {
        let data = try decode("""
        {"leaves":[{"start":"garbage","end":"2026-09-14T10:00:00Z"}],
         "records":{"2026-09-14":{"morningPunches":["2026-09-14T01:00:00Z"],"eveningPunches":[]}}}
        """)
        XCTAssertTrue(data.leaves.isEmpty, "坏数据只该丢请假")
        XCTAssertEqual(data.records["2026-09-14"]?.morningPunches.count, 1, "打卡绝不能因为新键坏掉而丢失")
    }

    func testLeavesSortedOnDecode() throws {
        let data = try decode("""
        {"leaves":[
          {"start":"2026-09-16T01:00:00Z","end":"2026-09-16T02:00:00Z"},
          {"start":"2026-09-14T01:00:00Z","end":"2026-09-14T02:00:00Z"}]}
        """)
        XCTAssertEqual(data.leaves.map(\.start), data.leaves.map(\.start).sorted())
    }

    func testEncodeDropsSkippedAndWritesLeaves() throws {
        // 旧文件读进来 → 再写出：skipped 键消失、leaves 接管，打卡记录本身不变。
        let decoded = try decode("""
        {"records":{"2026-09-14":{"morningPunches":["2026-09-14T01:00:00Z"],"eveningPunches":[],"skipped":true}}}
        """)
        XCTAssertEqual(decoded.leaves.count, 1)

        let object = try encode(decoded)
        let records = try XCTUnwrap(object["records"] as? [String: Any])
        let day = try XCTUnwrap(records["2026-09-14"] as? [String: Any])
        XCTAssertNil(day["skipped"], "skipped 不该再被写出")
        XCTAssertEqual(day["morningPunches"] as? [String], ["2026-09-14T01:00:00Z"])
        XCTAssertNotNil(object["leaves"])
    }

    func testEncodeAlwaysWritesLeavesKey() throws {
        let empty = try encode(DakaData())
        let written = try XCTUnwrap(empty["leaves"] as? [Any])
        XCTAssertTrue(written.isEmpty, "空数组也要写出，作为「已完成迁移」的标记")
    }

    func testMemberwiseInitDefaultsToNoLeaves() {
        XCTAssertTrue(DakaData().leaves.isEmpty)
    }
}
