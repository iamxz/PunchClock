import XCTest
@testable import DakaCore

final class QuitPromptTests: XCTestCase {
    func testAnyMissingPunchWarnsNoRetrofill() {
        for (morning, evening) in [(false, false), (true, false), (false, true)] {
            let text = QuitPrompt.impactText(skipped: false,
                                             morningDone: morning,
                                             eveningDone: evening)
            XCTAssertEqual(text, "退出后，漏卡不补")
        }
    }

    func testAllDoneJustSaysRemindersStop() {
        let text = QuitPrompt.impactText(skipped: false, morningDone: true, eveningDone: true)
        XCTAssertEqual(text, "退出后停止提醒")
    }

    func testSkippedDay() {
        let text = QuitPrompt.impactText(skipped: true, morningDone: false, eveningDone: false)
        XCTAssertEqual(text, "今日休假，放心退出")
    }

    /// 一句话文案，不超过 10 字。
    func testStaysShort() {
        for skipped in [true, false] {
            for morning in [true, false] {
                for evening in [true, false] {
                    let text = QuitPrompt.impactText(skipped: skipped,
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
