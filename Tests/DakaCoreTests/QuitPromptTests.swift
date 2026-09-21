import XCTest
@testable import DakaCore

final class QuitPromptTests: XCTestCase {
    func testNothingPunchedListsBothTasks() {
        let text = QuitPrompt.impactText(skipped: false, morningDone: false, eveningDone: false)
        XCTAssertTrue(text.contains("上班卡、下班卡"), text)
        XCTAssertTrue(text.contains("不会自动补记"), text)
    }

    func testOnlyEveningPending() {
        let text = QuitPrompt.impactText(skipped: false, morningDone: true, eveningDone: false)
        XCTAssertTrue(text.contains("下班卡"), text)
        XCTAssertFalse(text.contains("上班卡"), text)
    }

    func testAllDoneSaysNothingAffected() {
        let text = QuitPrompt.impactText(skipped: false, morningDone: true, eveningDone: true)
        XCTAssertTrue(text.contains("已全部完成"), text)
        XCTAssertFalse(text.contains("不会自动补记"), text)
    }

    func testSkippedDayHasNoPendingTasks() {
        let text = QuitPrompt.impactText(skipped: true, morningDone: false, eveningDone: false)
        XCTAssertTrue(text.contains("休假"), text)
        XCTAssertFalse(text.contains("不会自动补记"), text)
    }

    /// 无论今天打卡状态如何，都必须说明「退出后提醒会停止」这件关键影响。
    func testAlwaysExplainsReminderStopsAndDataKept() {
        for skipped in [true, false] {
            for morning in [true, false] {
                for evening in [true, false] {
                    let text = QuitPrompt.impactText(skipped: skipped,
                                                     morningDone: morning,
                                                     eveningDone: evening)
                    XCTAssertTrue(text.contains("提醒"), text)
                    XCTAssertTrue(text.contains("不会丢失"), text)
                }
            }
        }
    }
}
