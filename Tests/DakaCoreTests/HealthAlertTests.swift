import XCTest
@testable import DakaCore

final class HealthAlertTests: XCTestCase {
    private func water(interval: TimeInterval = 3600, minutes: Int = 60) -> HealthAlert {
        HealthAlert(kind: .water,
                    title: "该喝水啦 💧",
                    body: "已经 \(minutes) 分钟没喝水了，起来接杯水吧。",
                    repeatIntervalSeconds: interval)
    }

    private func movement(interval: TimeInterval = 3600, minutes: Int = 60) -> HealthAlert {
        HealthAlert(kind: .movement,
                    title: "起来走两步 🚶",
                    body: "坐了 \(minutes) 分钟，活动一下肩颈和腿吧。",
                    repeatIntervalSeconds: interval)
    }

    func testSameIdentityIgnoresBodyAndTitleText() {
        let a = water(minutes: 60)
        let b = water(minutes: 61)
        XCTAssertTrue(HealthAlert.sameIdentity([a], [b]))
        XCTAssertTrue(HealthAlert.sameIdentity([], []))
    }

    func testSameIdentityDetectsKindAdded() {
        XCTAssertFalse(HealthAlert.sameIdentity([], [water()]))
        XCTAssertFalse(HealthAlert.sameIdentity([water()], [water(), movement()]))
    }

    func testSameIdentityDetectsKindResolved() {
        XCTAssertFalse(HealthAlert.sameIdentity([water()], []))
        XCTAssertFalse(HealthAlert.sameIdentity([water(), movement()], [water()]))
    }

    func testSameIdentityDetectsKindSwapped() {
        XCTAssertFalse(HealthAlert.sameIdentity([water()], [movement()]))
    }

    func testMinimumRepeatIntervalFallsBackWhenNoAlerts() {
        XCTAssertEqual(HealthAlert.minimumRepeatInterval([], fallback: 120), 120)
    }

    func testMinimumRepeatIntervalPicksShortest() {
        XCTAssertEqual(HealthAlert.minimumRepeatInterval([3600], fallback: 120), 3600)
        XCTAssertEqual(HealthAlert.minimumRepeatInterval([7200, 3600], fallback: 120), 3600)
        XCTAssertEqual(HealthAlert.minimumRepeatInterval([900, 3600, 5400], fallback: 120), 900)
    }
}