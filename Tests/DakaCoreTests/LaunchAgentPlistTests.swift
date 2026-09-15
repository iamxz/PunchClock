import XCTest
@testable import DakaCore

final class LaunchAgentPlistTests: XCTestCase {
    func testLabelAndProgramArguments() throws {
        let dict = try parse(makePlist())
        XCTAssertEqual(dict["Label"] as? String, "com.xue.daka.schedule")
        XCTAssertEqual(dict["ProgramArguments"] as? [String],
                       ["/usr/bin/open", "-b", "com.xue.daka"])
    }

    func testFourCalendarTimes() throws {
        let entries = try intervals(makePlist())
        XCTAssertEqual(entries.count, 4)
        XCTAssertTrue(entries.contains(["Hour": 9, "Minute": 0]))
        XCTAssertTrue(entries.contains(["Hour": 9, "Minute": 30]))
        XCTAssertTrue(entries.contains(["Hour": 18, "Minute": 0]))
        XCTAssertTrue(entries.contains(["Hour": 18, "Minute": 30]))
    }

    func testNoRunAtLoad() throws {
        XCTAssertNil(try parse(makePlist())["RunAtLoad"])
    }

    func testInvalidTimeStringsAreSkipped() throws {
        XCTAssertEqual(try intervals(makePlist(morningWindowStart: "oops")).count, 3)
    }

    func testAllInvalidYieldsNoIntervalKey() throws {
        let dict = try parse(makePlist(morningWindowStart: "x", morningDeadline: "y",
                                       eveningWindowStart: "z", eveningDeadline: "w"))
        XCTAssertNil(dict["StartCalendarInterval"])
    }

    func testDuplicateTimesAreDeduped() throws {
        let entries = try intervals(makePlist(morningWindowStart: "09:00",
                                              morningDeadline: "09:00"))
        XCTAssertEqual(entries.count, 3)
    }

    // MARK: - Helpers

    private func makePlist(morningWindowStart: String = "09:00",
                           morningDeadline: String = "09:30",
                           eveningWindowStart: String = "18:00",
                           eveningDeadline: String = "18:30") -> String {
        LaunchAgentPlist.make(morningWindowStart: morningWindowStart,
                              morningDeadline: morningDeadline,
                              eveningWindowStart: eveningWindowStart,
                              eveningDeadline: eveningDeadline,
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
