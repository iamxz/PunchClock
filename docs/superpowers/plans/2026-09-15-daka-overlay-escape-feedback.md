# Daka v14 全屏遮罩 ESC 暂停 + 打卡反馈 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** 让全屏打卡遮罩可以按 ESC 临时关闭（过设定间隔自动重弹），并在打卡未完成时给出明确原因反馈。

**Architecture:** 新增 `DakaCore.PunchFeedback` 纯函数计算反馈文案（可单测）；应用层 `ReminderController` 处理 ESC → `snooze()` → 定时 `resume()`，并把 `PunchFeedback` 结果通过 `OverlayModel.message` 显示在 `OverlayView`。

**Tech Stack:** Swift 5.10 / SwiftPM、AppKit + SwiftUI、XCTest。

**Spec:** `docs/superpowers/specs/2026-09-15-daka-overlay-escape-feedback-design.md`

**验证命令：** `swift test`、`make build`。

---

### Task 7: `PunchFeedback` 反馈文案纯函数 + 测试

**Files:**
- Create: `Sources/DakaCore/PunchFeedback.swift`
- Test: `Tests/DakaCoreTests/PunchFeedbackTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `Tests/DakaCoreTests/PunchFeedbackTests.swift`：

```swift
import XCTest
@testable import DakaCore

final class PunchFeedbackTests: XCTestCase {
    private let cal = TestTime.calendar

    private func text(_ task: PunchTask,
                      record: DayRecord,
                      punchedAt: Date,
                      minHours: Double = 8) -> String? {
        var settings = Settings.default
        settings.minWorkDurationHours = minHours
        return PunchFeedback.text(task: task, record: record, settings: settings,
                                  punchedAt: punchedAt, calendar: cal)
    }

    func testMorningAlwaysNil() {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [day])
        XCTAssertNil(text(.morning, record: record, punchedAt: day))
    }

    func testCompletedEveningReturnsNil() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        XCTAssertNil(text(.evening, record: record, punchedAt: TestTime.date(2026, 9, 14, 18, 0)))
    }

    func testEveningUnderMinimumExplainsRemaining() {
        let morning = TestTime.date(2026, 9, 14, 9, 0)
        let evening = TestTime.date(2026, 9, 14, 16, 0)
        let record = DayRecord(morningPunches: [morning], eveningPunches: [evening])
        let message = text(.evening, record: record, punchedAt: evening)
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("还差 1 小时") ?? false, message ?? "nil")
        XCTAssertTrue(message?.contains("16:00") ?? false, message ?? "nil")
    }

    func testEveningWithoutMorningAsksForMorningPunch() {
        let evening = TestTime.date(2026, 9, 14, 16, 0)
        let record = DayRecord(eveningPunches: [evening])
        let message = text(.evening, record: record, punchedAt: evening)
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("还没有上班打卡") ?? false, message ?? "nil")
    }

    func testRemainingUnderOneMinute() {
        let morning = TestTime.date(2026, 9, 14, 9, 0)
        let evening = TestTime.date(2026, 9, 14, 16, 59, 30)
        let record = DayRecord(morningPunches: [morning], eveningPunches: [evening])
        let message = text(.evening, record: record, punchedAt: evening)
        XCTAssertTrue(message?.contains("不足 1 分钟") ?? false, message ?? "nil")
    }
}
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter PunchFeedbackTests`
Expected: 编译失败，`cannot find 'PunchFeedback' in scope`。

- [ ] **Step 3: 实现 `PunchFeedback`**

创建 `Sources/DakaCore/PunchFeedback.swift`：

```swift
import Foundation

/// 打卡后若任务仍未完成，给出原因与还差多少的说明文案。
public enum PunchFeedback {
    public static func text(task: PunchTask,
                            record: DayRecord,
                            settings: Settings,
                            punchedAt: Date,
                            calendar: Calendar = .current) -> String? {
        switch task {
        case .morning:
            return nil
        case .evening:
            if PunchRules.isEveningComplete(record, minWorkDuration: settings.minWorkDuration) {
                return nil
            }
            let hours = settings.minWorkDurationHours
            let time = timeFormatter.string(from: punchedAt)
            guard let morning = record.morningDoneAt else {
                return "已记录 \(time)；今天还没有上班打卡，需先打上班卡；下班需满 \(hoursText(hours)) 小时才算完成。"
            }
            let need = morning.addingTimeInterval(settings.minWorkDuration)
            let remaining = need.timeIntervalSince(punchedAt)
            return "已记录 \(time)；距上班满 \(hoursText(hours)) 小时还差 \(remainingText(remaining))，满后自动完成。"
        }
    }

    private static func hoursText(_ hours: Double) -> String {
        hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
    }

    private static func remainingText(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "不足 1 分钟" }
        let totalMinutes = Int((seconds / 60).rounded(.up))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h > 0 {
            return m > 0 ? "\(h) 小时 \(m) 分钟" : "\(h) 小时"
        }
        return "\(m) 分钟"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `swift test --filter PunchFeedbackTests`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add Sources/DakaCore/PunchFeedback.swift Tests/DakaCoreTests/PunchFeedbackTests.swift
git commit -m "feat: add punch feedback text helper"
```

---

### Task 8: ESC 暂停 + 遮罩反馈显示

**Files:**
- Modify: `Sources/Daka/ReminderController.swift`
- Modify: `Sources/Daka/OverlayView.swift`
- Modify: `Sources/Daka/AppModel.swift`

- [ ] **Step 1: `OverlayModel` 增加 message，并在视图显示**

在 `Sources/Daka/OverlayView.swift` 的 `OverlayModel` 增加：

```swift
    @Published var message: String?
```

在 `OverlayView.body` 里，`Text("当前时间 …")` 之后、`ForEach(model.tasks …)` 之前插入：

```swift
                if let message = model.message {
                    Text(message)
                        .font(.system(size: 18))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }
```

- [ ] **Step 2: `OverlayWindow` 回调 ESC**

在 `Sources/Daka/ReminderController.swift` 的 `OverlayWindow` 中增加属性：

```swift
    var onEscape: (() -> Void)?
```

把 `cancelOperation` 与 `keyDown` 改为：

```swift
    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?(); return } // ESC：暂停提醒
        super.keyDown(with: event)
    }
```

- [ ] **Step 3: `ReminderController` 增加 snooze / resume / showMessage**

1. 增加属性：`private var snoozeTimer: Timer?`
2. `showHard` 方法开头（设置 currentTasks 之前）插入：

```swift
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        overlayModel.message = nil
```

3. `hide()` 中追加：

```swift
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        overlayModel.message = nil
```

4. 在 `rebuildWindowsIfNeeded` 里创建 window 后（`return window` 之前）设置：

```swift
            window.onEscape = { [weak self] in self?.snooze() }
```

5. 增加方法：

```swift
    func snooze() {
        guard !currentTasks.isEmpty else { return }
        stopReassertTimer()
        for w in windows { w.orderOut(nil) }
        snoozeTimer?.invalidate()
        let t = Timer(timeInterval: reassertInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        }
        RunLoop.main.add(t, forMode: .common)
        snoozeTimer = t
    }

    func showMessage(_ text: String?) {
        overlayModel.message = text
    }

    private func resume() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        guard !currentTasks.isEmpty else { return }
        rebuildWindowsIfNeeded()
        for w in windows { w.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        startReassertTimer()
    }
```

- [ ] **Step 4: `AppModel.punch` 推送反馈**

把 `Sources/Daka/AppModel.swift` 的 `punch(_:)` 改为：

```swift
    func punch(_ task: PunchTask) {
        errorMessage = nil
        do {
            try store.mark(task, at: clock.now)
            refreshRecord()
            scheduler?.tick()
            reminder?.showMessage(PunchFeedback.text(task: task,
                                                      record: record,
                                                      settings: settings,
                                                      punchedAt: clock.now))
        } catch {
            errorMessage = "打卡记录写入失败：\(error.localizedDescription)"
        }
    }
```

（`PunchFeedback` 来自 `DakaCore`，`AppModel` 已 `import DakaCore`。）

- [ ] **Step 5: 构建与测试**

Run: `swift test` → 全部 PASS。
Run: `make build` → `Build complete!`。

- [ ] **Step 6: 提交**

```bash
git add Sources/Daka/ReminderController.swift Sources/Daka/OverlayView.swift Sources/Daka/AppModel.swift
git commit -m "feat: snooze overlay with ESC and show punch feedback"
```

---

### Task 9: 文档更新

**Files:**
- Modify: `README.md`
- Modify: `docs/verification.md`

- [ ] **Step 1: README**

把第 51 行：

```markdown
- 全屏强制遮罩仍无法用 ESC、Cmd+W、Cmd+M、Cmd+H 关闭；完成对应打卡后自动消失。
```

改为：

```markdown
- 全屏遮罩可用 **ESC 暂停**：立即隐藏，过「重复提醒」间隔后自动重新弹出，直到完成打卡；Cmd+W / Cmd+M / Cmd+H 仍无效。
- 打卡后若当天仍未完成（如下班未满最少工时或缺少上班卡），遮罩会显示原因与还差多久。
```

- [ ] **Step 2: verification.md**

把「全屏强提醒（v13）」章节里这条：

```markdown
- [ ] 全屏遮罩置顶，ESC / Cmd+W / Cmd+M / Cmd+H 无效。
```

改为：

```markdown
- [ ] 全屏遮罩置顶，Cmd+W / Cmd+M / Cmd+H 无效。
- [ ] 按 ESC → 遮罩立即隐藏，过设定间隔（默认 2 分钟）自动重新弹出，可反复。
```

并在文件末尾追加：

```markdown
## v14：遮罩 ESC 暂停 + 打卡反馈

- [ ] 全屏遮罩按 ESC → 立即消失，约 2 分钟后自动重新弹出；再按 ESC 仍可暂停。
- [ ] 上班卡较晚时点「下班打卡」→ 遮罩不消失，但显示「已记录 HH:mm；距上班满 X 小时还差 …，满后自动完成。」
- [ ] 当天没有上班卡就点「下班打卡」→ 显示需先打上班卡的提示。
- [ ] 满足最少工时后再点下班 → 遮罩消失且不再弹回。
- [ ] 通过菜单栏/控制中心完成打卡后，暂停中的遮罩不再自动弹回。
- [ ] 跨天后遮罩与待弹均结束。
```

- [ ] **Step 3: 提交**

```bash
git add README.md docs/verification.md
git commit -m "docs: document overlay ESC snooze and punch feedback"
```

---

## 完成后

- `swift test` 全绿；`make build` 成功。
- `make install` 后按 v14 清单手动验证。
