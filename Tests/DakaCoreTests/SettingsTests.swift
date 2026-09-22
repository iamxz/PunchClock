import XCTest
@testable import DakaCore

final class SettingsTests: XCTestCase {
    func testDefaults() {
        let s = Settings.default
        XCTAssertEqual(s.workStartTime, "09:00")
        XCTAssertEqual(s.workDurationHours, 9)
        XCTAssertEqual(s.flexMinutes, 30)
        XCTAssertEqual(s.reminderIntervalSeconds, 120)
        XCTAssertEqual(s.workDuration, 9 * 3600)
        XCTAssertEqual(s.flexDuration, 30 * 60)
    }

    func testRoundTrip() throws {
        var s = Settings.default
        s.workStartTime = "08:30"
        s.workDurationHours = 8.5
        s.flexMinutes = 15
        s.enabled = false
        s.loginItemEnabled = false
        s.scheduledLaunchEnabled = false
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testLegacyJSONMigratesOldKeys() throws {
        let legacy = """
        {
          "enabled": true,
          "workdays": [2,3,4,5,6],
          "morningWindowStart": "09:00",
          "morningDeadline": "09:40",
          "minWorkDurationHours": 8,
          "reminderIntervalSeconds": 60
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: legacy)
        XCTAssertEqual(decoded.workStartTime, "09:00")
        XCTAssertEqual(decoded.flexMinutes, 40)
        XCTAssertEqual(decoded.workDurationHours, 8)
        XCTAssertEqual(decoded.reminderIntervalSeconds, 60)
    }

    func testVeryOldJSONUsesDefaults() throws {
        let legacy = #"{"enabled": false, "morningTime": "07:00"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: legacy)
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.workStartTime, "09:00")
        XCTAssertEqual(decoded.flexMinutes, 30)
        XCTAssertEqual(decoded.workDurationHours, 9)
    }

    func testPartialJSONUsesDefaultsForMissing() throws {
        let partial = #"{"enabled": false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: partial)
        XCTAssertFalse(decoded.enabled)
        XCTAssertTrue(decoded.loginItemEnabled)
        XCTAssertTrue(decoded.scheduledLaunchEnabled)
        XCTAssertEqual(decoded.workStartTime, "09:00")
    }

    func testReminderIntervalIsClamped() {
        var s = Settings.default
        s.reminderIntervalSeconds = 0
        XCTAssertEqual(s.effectiveReminderIntervalSeconds, 30)
        s.reminderIntervalSeconds = 120
        XCTAssertEqual(s.effectiveReminderIntervalSeconds, 120)
    }

    func testEncodeWritesOnlyNewKeys() throws {
        let s = Settings.default
        let data = try JSONEncoder().encode(s)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(json["enabled"])
        XCTAssertNotNil(json["workdays"])
        XCTAssertNotNil(json["workStartTime"])
        XCTAssertNotNil(json["workDurationHours"])
        XCTAssertNotNil(json["flexMinutes"])
        XCTAssertNotNil(json["reminderIntervalSeconds"])
        XCTAssertNil(json["morningWindowStart"])
        XCTAssertNil(json["morningDeadline"])
        XCTAssertNil(json["eveningWindowStart"])
        XCTAssertNil(json["eveningDeadline"])
        XCTAssertNil(json["minWorkDurationHours"])
    }
}
