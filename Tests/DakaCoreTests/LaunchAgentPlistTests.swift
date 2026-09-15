import XCTest
@testable import DakaCore

final class LaunchAgentPlistTests: XCTestCase {
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

    func testContainsLabelAndOpenInvocation() {
        let plist = makePlist()
        XCTAssertTrue(plist.contains("<string>com.xue.daka.schedule</string>"))
        XCTAssertTrue(plist.contains("/usr/bin/open"))
        XCTAssertTrue(plist.contains("<string>-b</string>"))
        XCTAssertTrue(plist.contains("<string>com.xue.daka</string>"))
    }

    func testContainsFourCalendarTimes() {
        let plist = makePlist()
        let hours = timePairs(in: plist)
        XCTAssertEqual(hours.count, 4)
        XCTAssertTrue(hours.contains { $0 == (9, 0) })
        XCTAssertTrue(hours.contains { $0 == (9, 30) })
        XCTAssertTrue(hours.contains { $0 == (18, 0) })
        XCTAssertTrue(hours.contains { $0 == (18, 30) })
    }

    func testDoesNotRunAtLoad() {
        let plist = makePlist()
        XCTAssertFalse(plist.contains("RunAtLoad"))
    }

    func testInvalidTimeStringsAreSkipped() {
        let plist = makePlist(morningWindowStart: "oops")
        XCTAssertEqual(timePairs(in: plist).count, 3)
    }

    /// 从 plist 文本里提取所有 (Hour, Minute) 对，按出现顺序。
    private func timePairs(in plist: String) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        let lines = plist.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var i = 0
        while i < lines.count {
            if lines[i].contains("<key>Hour</key>"),
               i + 2 < lines.count, lines[i + 1].contains("<integer>"),
               lines[i + 2].contains("<key>Minute</key>"),
               i + 3 < lines.count, lines[i + 3].contains("<integer>") {
                let hour = Int(lines[i + 1].replacingOccurrences(of: "<integer>", with: "")
                    .replacingOccurrences(of: "</integer>", with: "")) ?? -1
                let minute = Int(lines[i + 3].replacingOccurrences(of: "<integer>", with: "")
                    .replacingOccurrences(of: "</integer>", with: "")) ?? -1
                result.append((hour, minute))
                i += 4
                continue
            }
            i += 1
        }
        return result
    }
}
