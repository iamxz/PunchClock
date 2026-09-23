import XCTest
@testable import DakaCore

final class QuitPromptTests: XCTestCase {
    func testAnyMissingPunchWarnsNoRetrofill() {
        for (morning, evening) in [(false, false), (true, false), (false, true)] {
            let text = QuitPrompt.impactText(onLeave: false,
                                             morningDone: morning,
                                             eveningDone: evening)
            XCTAssertEqual(text, "退出后，漏卡不补")
        }
    }

    func testAllDoneJustSaysRemindersStop() {
        let text = QuitPrompt.impactText(onLeave: false, morningDone: true, eveningDone: true)
        XCTAssertEqual(text, "退出后停止提醒")
    }

    func testFullDayLeaveSaysRelax() {
        let text = QuitPrompt.impactText(onLeave: true, morningDone: false, eveningDone: false)
        XCTAssertEqual(text, "今日休假，放心退出")
    }

    /// 半天假仍欠着工时，不能说「放心退出」。
    func testHalfDayLeaveStillWarns() {
        let text = QuitPrompt.impactText(onLeave: false, morningDone: true, eveningDone: false)
        XCTAssertEqual(text, "退出后，漏卡不补")
    }

    /// 一句话文案，不超过 10 字。
    func testStaysShort() {
        for onLeave in [true, false] {
            for morning in [true, false] {
                for evening in [true, false] {
                    let text = QuitPrompt.impactText(onLeave: onLeave,
                                                     morningDone: morning,
                                                     eveningDone: evening)
                    XCTAssertFalse(text.isEmpty)
                    XCTAssertFalse(text.contains("\n"))
                    XCTAssertTrue(text.count <= 10, text)
                }
            }
        }
    }
}
