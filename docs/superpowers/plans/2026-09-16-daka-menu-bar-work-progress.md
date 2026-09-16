# 菜单栏打卡圆环显示「已工作时长进度」Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `PunchButton` 的圆环在空闲态显示今天已工作时长进度（圆心显示 `4h` / `4.5h` / `45m`），长按 3 秒打卡时切回按压进度。

**Architecture:** 在 `DakaCore` 新增纯函数 `WorkProgress`（`elapsed` / `fraction` / `hoursText`），复用现有 `PunchRules.effectiveEveningPunch`。`PunchButton` 空闲态调它计算进度与文案，用 `TimelineView` 每分钟刷新；按压态保持原计时器。菜单栏与工具面板两个调用点补传数据。

**Tech Stack:** Swift 5.10 / SwiftUI（macOS 14）/ XCTest / SwiftPM（`swift test`、`swift build`）。

**Spec:** `docs/superpowers/specs/2026-09-16-daka-menu-bar-work-progress-design.md`

---

## 文件结构

- Create: `Sources/DakaCore/WorkProgress.swift` — 已工作时长的纯计算与显示文案。
- Create: `Tests/DakaCoreTests/WorkProgressTests.swift` — 上述逻辑单测。
- Modify: `Sources/Daka/PunchButton.swift` — 圆环空闲/按压两态、圆心文案、环色、每分钟刷新；接口新增 `record` / `nowProvider` / `minWorkDuration`。
- Modify: `Sources/Daka/MenuBarView.swift:32-36` — 调用点补传。
- Modify: `Sources/Daka/ToolPanelView.swift:54-58` — 调用点补传。
- Modify: `docs/verification.md` — 追加 v15 手动验证清单。

---

## Task 1: `WorkProgress.elapsed` 与 `fraction`

**Files:**
- Create: `Sources/DakaCore/WorkProgress.swift`
- Test: `Tests/DakaCoreTests/WorkProgressTests.swift`

- [ ] **Step 1: 写失败测试**

创建 `Tests/DakaCoreTests/WorkProgressTests.swift`：

```swift
import XCTest
@testable import DakaCore

final class WorkProgressTests: XCTestCase {
    private let eight: TimeInterval = 8 * 3600

    func testNoMorningPunchHasNoElapsedAndZeroFraction() {
        let record = DayRecord(eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 18, 0)
        XCTAssertNil(WorkProgress.elapsed(record, now: now, minWorkDuration: eight))
        XCTAssertEqual(WorkProgress.fraction(record, now: now, minWorkDuration: eight), 0)
    }

    func testFourOfEightHoursIsHalf() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 13, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, minWorkDuration: eight),
                       4 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, minWorkDuration: eight), 0.5)
    }

    func testOvertimeIsCappedAtOne() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 19, 0)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, minWorkDuration: eight), 1)
    }

    func testCompletionUsesQualifyingEveningPunch() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 20, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, minWorkDuration: eight),
                       9 * 3600)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, minWorkDuration: eight), 1)
    }

    func testCompletionUsesLatestQualifyingPunch() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 16, 0),
                                                TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 21, 0)
        XCTAssertEqual(WorkProgress.elapsed(record, now: now, minWorkDuration: eight),
                       9 * 3600)
    }

    func testZeroMinimumIsFull() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 9, 30)
        XCTAssertEqual(WorkProgress.fraction(record, now: now, minWorkDuration: 0), 1)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter WorkProgressTests`
Expected: 编译失败，`cannot find 'WorkProgress' in scope`。

- [ ] **Step 3: 写最小实现**

创建 `Sources/DakaCore/WorkProgress.swift`：

```swift
import Foundation

/// 今天已工作时长与圆环进度。未打上班卡即无意义。
public enum WorkProgress {
    /// 已工作时长；未打上班卡时 nil。
    /// 终点：若有合格下班卡取之（实际总时长），否则取 now。
    public static func elapsed(_ record: DayRecord,
                               now: Date,
                               minWorkDuration: TimeInterval) -> TimeInterval? {
        guard let morning = record.morningDoneAt else { return nil }
        let end = PunchRules.effectiveEveningPunch(record, minWorkDuration: minWorkDuration) ?? now
        return max(0, end.timeIntervalSince(morning))
    }

    /// 圆环进度 0...1；未打上班卡为 0，最少工时为 0 时视为 1。
    public static func fraction(_ record: DayRecord,
                                now: Date,
                                minWorkDuration: TimeInterval) -> Double {
        guard let elapsed = elapsed(record, now: now, minWorkDuration: minWorkDuration) else {
            return 0
        }
        guard minWorkDuration > 0 else { return 1 }
        return min(1, elapsed / minWorkDuration)
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter WorkProgressTests`
Expected: `Executed 6 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/DakaCore/WorkProgress.swift Tests/DakaCoreTests/WorkProgressTests.swift
git commit -m "feat: add WorkProgress elapsed/fraction"
```

---

## Task 2: `WorkProgress.hoursText`

**Files:**
- Modify: `Sources/DakaCore/WorkProgress.swift`
- Test: `Tests/DakaCoreTests/WorkProgressTests.swift`

- [ ] **Step 1: 追加失败测试**

在 `WorkProgressTests` 类内追加：

```swift
    func testHoursTextUnderOneHourShowsMinutes() {
        XCTAssertEqual(WorkProgress.hoursText(45 * 60), "45m")
    }

    func testHoursTextWholeHours() {
        XCTAssertEqual(WorkProgress.hoursText(4 * 3600), "4h")
    }

    func testHoursTextHalfHour() {
        XCTAssertEqual(WorkProgress.hoursText(4.5 * 3600), "4.5h")
    }

    func testHoursTextNegativeIsZero() {
        XCTAssertEqual(WorkProgress.hoursText(-60), "0m")
    }
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter WorkProgressTests`
Expected: 编译失败，`type 'WorkProgress' has no member 'hoursText'`。

- [ ] **Step 3: 写最小实现**

在 `Sources/DakaCore/WorkProgress.swift` 的 `fraction` 方法后、枚举结束前追加：

```swift
    /// 显示文案：`4h` / `4.5h` / `45m`；负值按 `0m`。
    public static func hoursText(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((max(0, interval) / 60).rounded(.down))
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let hours = Double(totalMinutes) / 60
        if hours == hours.rounded() { return "\(Int(hours))h" }
        return String(format: "%.1fh", hours)
    }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter WorkProgressTests`
Expected: `Executed 10 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
git add Sources/DakaCore/WorkProgress.swift Tests/DakaCoreTests/WorkProgressTests.swift
git commit -m "feat: add WorkProgress hours text"
```

---

## Task 3: `PunchButton` 渲染已工作时长

**Files:**
- Modify: `Sources/Daka/PunchButton.swift:43-86`（整个 `PunchButton` 结构体）
- Modify: `Sources/Daka/MenuBarView.swift:32-36`
- Modify: `Sources/Daka/ToolPanelView.swift:54-58`

- [ ] **Step 1: 替换 `PunchButton`**

把 `Sources/Daka/PunchButton.swift` 中从 `struct PunchButton: View {` 到文件末尾的 `}` 整体替换为：

```swift
struct PunchButton: View {
    let task: PunchTask
    let record: DayRecord
    let nowProvider: () -> Date
    let minWorkDuration: TimeInterval
    let onComplete: (PunchTask) -> Void

    @StateObject private var press = PunchPressModel()

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.everyMinute) { _ in
                ring
            }
            Text("长按 3 秒打卡（可重复）")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: task) { _, _ in press.cancel() }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
            Circle()
                .trim(from: 0, to: ringFraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(centerText)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 108, height: 108)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in press.start { onComplete(task) } }
                .onEnded { _ in press.cancel() }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(task.title))
        .accessibilityHint(Text("长按 3 秒完成打卡；旁白可直接操作"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("完成打卡")) { onComplete(task) }
    }

    private var isPressing: Bool { press.progress > 0 }

    private var isEveningComplete: Bool {
        PunchRules.isEveningComplete(record, minWorkDuration: minWorkDuration)
    }

    private var ringFraction: CGFloat {
        if isPressing { return press.progress }
        return CGFloat(WorkProgress.fraction(record, now: nowProvider(), minWorkDuration: minWorkDuration))
    }

    private var tint: Color {
        if isEveningComplete && !isPressing { return .green }
        return task == .morning ? .green : .blue
    }

    private var centerText: String {
        if isPressing { return task.title }
        guard let elapsed = WorkProgress.elapsed(record, now: nowProvider(), minWorkDuration: minWorkDuration) else {
            return task.title
        }
        return WorkProgress.hoursText(elapsed)
    }
}
```

- [ ] **Step 2: 更新菜单栏调用点**

把 `Sources/Daka/MenuBarView.swift:32-36` 替换为：

```swift
            PunchButton(task: PunchTarget.resolve(record: model.record,
                                                  now: model.now,
                                                  minWorkDuration: model.minWorkDuration),
                        record: model.record,
                        nowProvider: { model.now },
                        minWorkDuration: model.minWorkDuration) { task in
                model.punch(task)
            }
```

- [ ] **Step 3: 更新工具面板调用点**

把 `Sources/Daka/ToolPanelView.swift:54-58` 替换为：

```swift
            PunchButton(task: PunchTarget.resolve(record: model.record,
                                                  now: model.now,
                                                  minWorkDuration: model.minWorkDuration),
                        record: model.record,
                        nowProvider: { model.now },
                        minWorkDuration: model.minWorkDuration) { task in
                model.punch(task)
            }
```

- [ ] **Step 4: 构建验证**

Run: `make build`
Expected: `Build complete!`，无编译错误。

- [ ] **Step 5: 提交**

```bash
git add Sources/Daka/PunchButton.swift Sources/Daka/MenuBarView.swift Sources/Daka/ToolPanelView.swift
git commit -m "feat: show elapsed work progress on punch ring"
```

---

## Task 4: 全量测试与文档

**Files:**
- Modify: `docs/verification.md`

- [ ] **Step 1: 跑全量测试**

Run: `swift test`
Expected: 全部通过（含新增 `WorkProgressTests`）。

- [ ] **Step 2: 追加手动验证清单**

在 `docs/verification.md` 末尾追加：

```markdown

## v15：菜单栏圆环显示已工作时长

- [ ] 未打上班卡：菜单栏下拉圆环为空、圆心显示「上班」。
- [ ] 上班打卡后：圆环按「已工作时长 / 最少工时」填充（如 8 小时制上班 4 小时后约 50%），圆心显示 `4h` 字样。
- [ ] 保持应用打开，圆环与小时数每分钟自动前进。
- [ ] 长按圆环 3 秒：环从 0 重新填到满，圆心切回「上班 / 下班」，松开后恢复已工作时长进度。
- [ ] 下班打卡满足最少工时后：圆环满、变绿，圆心显示当天实际总时长。
- [ ] 工具面板里的圆形打卡按钮同样显示已工作时长进度。
- [ ] 「考勤规则」改最少工时后，圆环进度比例随之变化。
```

- [ ] **Step 3: 提交**

```bash
git add docs/verification.md
git commit -m "docs: add v15 work-progress ring verification"
```

---

## 自检

- **Spec 覆盖**：§3 语义 → Task 1；§4 文案 → Task 2；§4/§5/§6/§8 渲染与刷新 → Task 3；§11 文档 → Task 4。§7 API 已按 `nowProvider` 落地。§10 测试 → Task 1/2。
- **占位符**：无 TODO / TBD；每个代码步骤给全量代码。
- **类型一致**：`WorkProgress.elapsed/fraction/hoursText`、`PunchButton(task:record:nowProvider:minWorkDuration:onComplete:)` 在任务间一致；复用 `PunchRules.isEveningComplete` / `effectiveEveningPunch`。
- **人工验证**：UI 行为（环色、按压切换、每分钟刷新）在 Task 4 清单中手动确认。
