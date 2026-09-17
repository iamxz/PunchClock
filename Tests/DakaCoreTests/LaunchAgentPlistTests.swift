import XCTest
@testable import DakaCore

final class LaunchAgentPlistTests: XCTestCase {
    func testLabelAndProgramArguments() throws {
        let dict = try parse(makePlist())
        XCTAssertEqual(dict["Label"] as? String, "com.xue.daka.schedule")
        let args = try XCTUnwrap(dict["ProgramArguments"] as? [String])
        XCTAssertEqual(args, ["/bin/sh", "-c",
                              "/usr/bin/pgrep -u \"$(id -u)\" -x Daka >/dev/null 2>&1 || /usr/bin/open -b com.xue.daka --args --background"])
    }

    func testThreeCalendarTimes() throws {
        let entries = try intervals(makePlist())
        XCTAssertEqual(entries.count, 3)
        XCTAssertTrue(entries.contains(["Hour": 9, "Minute": 0]))
        XCTAssertTrue(entries.contains(["Hour": 9, "Minute": 30]))
        XCTAssertTrue(entries.contains(["Hour": 18, "Minute": 0]))
    }

    func testNoRunAtLoad() throws {
        XCTAssertNil(try parse(makePlist())["RunAtLoad"])
    }

    func testInvalidTimeStringsAreSkipped() throws {
        let times = ["oops", "09:30", "18:00"]
        XCTAssertEqual(try intervals(LaunchAgentPlist.make(times: times, bundleID: "com.xue.daka")).count, 2)
    }

    func testAllInvalidYieldsNoIntervalKey() throws {
        let times = ["x", "y", "z", "w"]
        let dict = try parse(LaunchAgentPlist.make(times: times, bundleID: "com.xue.daka"))
        XCTAssertNil(dict["StartCalendarInterval"])
    }

    func testDuplicateTimesAreDeduped() throws {
        let times = ["09:00", "09:00", "18:00", "18:30"]
        let entries = try intervals(LaunchAgentPlist.make(times: times, bundleID: "com.xue.daka"))
        XCTAssertEqual(entries.count, 3)
    }

    // MARK: - Helpers

    private func makePlist() -> String {
        LaunchAgentPlist.make(times: ["09:00", "09:30", "18:00"],
                              bundleID: "com.xue.daka")
    }

    private func parse(_ plist: String) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(from: Data(plist.utf8),
                                                               options: [],
                                                               format: nil)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func intervals(_ plist: String) throws -> [[String: Int]] {
        try XCTUnwrap(try parse(plist)["StartCalendarInterval"] as? [[String: Int]])
    }
}
