import XCTest
@testable import DakaCore

final class PetMoodTests: XCTestCase {
    private let cal = TestTime.calendar
    private func resolve(_ hour: Int, calendar cal: Calendar) -> PetMood {
        PetMood.resolve(reminderState: ReminderState(), now: TestTime.date(2026, 9, 14, hour, 0), calendar: cal)
    }

    func testTimeBasedMoods() {
        XCTAssertEqual(resolve(5, calendar: cal), .cheerful)
        XCTAssertEqual(resolve(10, calendar: cal), .cheerful)
        XCTAssertEqual(resolve(11, calendar: cal), .lunch)
        XCTAssertEqual(resolve(13, calendar: cal), .focused)
        XCTAssertEqual(resolve(17, calendar: cal), .relaxed)
        XCTAssertEqual(resolve(21, calendar: cal), .sleepy)
        XCTAssertEqual(resolve(2, calendar: cal), .sleepy)
    }

    func testGentleOverridesTime() {
        let state = ReminderState(gentle: [.morning], hard: [])
        let mood = PetMood.resolve(reminderState: state, now: TestTime.date(2026, 9, 14, 9, 0), calendar: cal)
        XCTAssertEqual(mood, .gentlePending)
    }

    func testHardOverridesGentleAndTime() {
        let state = ReminderState(gentle: [.evening], hard: [.morning])
        let mood = PetMood.resolve(reminderState: state, now: TestTime.date(2026, 9, 14, 9, 0), calendar: cal)
        XCTAssertEqual(mood, .hardPending)
    }

    func testEveryMoodHasEmoji() {
        for mood in PetMood.allCases {
            XCTAssertFalse(mood.emoji.isEmpty)
        }
    }
}
