import XCTest
@testable import DakaCore

final class SettingsTests: XCTestCase {
    func testDefaults() {
        let s = Settings.default
        XCTAssertEqual(s.morningWindowStart, "09:00")
        XCTAssertEqual(s.morningDeadline, "09:30")
        XCTAssertEqual(s.eveningWindowStart, "18:00")
        XCTAssertEqual(s.eveningDeadline, "18:30")
        XCTAssertEqual(s.reminderIntervalSeconds, 120)
    }

    func testRoundTrip() throws {
        var s = Settings.default
        s.morningDeadline = "09:45"
        s.enabled = false
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testLegacyJSONUpgradesToDefaults() throws {
        let legacy = """
        {
          "enabled": true,
          "workdays": [2,3,4,5,6],
          "morningTime": "07:00",
          "eveningTime": "17:00",
          "launchPromptEarliest": "06:00",
          "reminderIntervalSeconds": 60
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: legacy)
        XCTAssertEqual(decoded.morningWindowStart, "09:00")
        XCTAssertEqual(decoded.morningDeadline, "09:30")
        XCTAssertEqual(decoded.eveningWindowStart, "18:00")
        XCTAssertEqual(decoded.eveningDeadline, "18:30")
        XCTAssertEqual(decoded.reminderIntervalSeconds, 60)
    }

    func testPartialJSONUsesDefaultsForMissing() throws {
        let partial = #"{"enabled": false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: partial)
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.morningWindowStart, "09:00")
    }

    func testReminderIntervalIsClampedForInvaliValues() {
        var s = Settings.default
        s.reminderIntervalSeconds = 0
        XCTAssertEqual(s.effectiveReminderIntervalSeconds, 30)
        s.reminderIntervalSeconds = -5
        XCTAssertEqual(s.effectiveReminderIntervalSeconds, 30)
        s.reminderIntervalSeconds = 120
        XCTAssertEqual(s.effectiveReminderIntervalSeconds, 120)
    }
}
