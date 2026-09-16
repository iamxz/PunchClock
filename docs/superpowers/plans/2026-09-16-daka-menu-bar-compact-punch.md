# Daka 菜单栏弹窗紧凑化 + 圆环显示打卡时间 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 菜单栏下拉面板去掉行内时间并变窄，把「已打卡时间」移入圆形打卡按钮圆心，与「已工作时长」上下两行显示。

**Architecture:** 在 `DakaCore.PunchRules` 增加可测的 `latestPunch` 取数；`PunchButton` 圆心由单行改为两行；`MenuBarView` 行文案去时间并缩窄。`PunchButton` 为菜单栏弹窗与桌宠气泡面板共用，两处一致变化。

**Tech Stack:** Swift 5.10、SwiftUI、SwiftPM、XCTest。

**Spec:** `docs/superpowers/specs/2026-09-16-daka-menu-bar-compact-punch-design.md`

---

## File Structure

- `Sources/DakaCore/PunchRules.swift`（改）：新增 `latestPunch(_:task:)`。
- `Tests/DakaCoreTests/PunchRulesTests.swift`（改）：补 `latestPunch` 测试。
- `Sources/Daka/PunchButton.swift`（改）：说明文字去「（可重复）」；圆心两行。
- `Sources/Daka/MenuBarView.swift`（改）：行文案去时间；宽度 `220 → 180`。
- `docs/verification.md`（改）：更新 v4/v15 文案并新增 v16。

---

### Task 1: `PunchRules.latestPunch`（DakaCore，TDD）

**Files:**
- Modify: `Sources/DakaCore/PunchRules.swift`
- Test: `Tests/DakaCoreTests/PunchRulesTests.swift`

- [ ] **Step 1: 写失败测试**

在 `Tests/DakaCoreTests/PunchRulesTests.swift` 的 `PunchRulesTests` 类内追加：

```swift
    func testLatestPunchReturnsMostRecentPerTask() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0),
                                               TestTime.date(2026, 9, 14, 9, 20)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0),
                                                TestTime.date(2026, 9, 14, 18, 30)])
        XCTAssertEqual(PunchRules.latestPunch(record, task: .morning),
                       TestTime.date(2026, 9, 14, 9, 20))
        XCTAssertEqual(PunchRules.latestPunch(record, task: .evening),
                       TestTime.date(2026, 9, 14, 18, 30))
    }

    func testLatestPunchNilWhenEmpty() {
        let record = DayRecord()
        XCTAssertNil(PunchRules.latestPunch(record, task: .morning))
        XCTAssertNil(PunchRules.latestPunch(record, task: .evening))
    }
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter PunchRulesTests`
Expected: 编译失败，报 `type 'PunchRules' has no member 'latestPunch'`。

- [ ] **Step 3: 最小实现**

在 `Sources/DakaCore/PunchRules.swift` 的 `enum PunchRules` 内追加：

```swift
    /// 指定任务的最近一次打卡；无打卡时 nil。
    public static func latestPunch(_ record: DayRecord, task: PunchTask) -> Date? {
        switch task {
        case .morning: return record.morningPunches.max()
        case .evening: return record.eveningPunches.max()
        }
    }
```

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter PunchRulesTests`
Expected: PASS（该类全部用例通过）。

- [ ] **Step 5: 提交**

```bash
git add Sources/DakaCore/PunchRules.swift Tests/DakaCoreTests/PunchRulesTests.swift
git commit -m "feat: add PunchRules.latestPunch"
```

---

### Task 2: `PunchButton` 圆心两行 + 说明文字

**Files:**
- Modify: `Sources/Daka/PunchButton.swift`

- [ ] **Step 1: 改说明文字**

把 `Sources/Daka/PunchButton.swift:57` 的：

```swift
            Text("长按 3 秒打卡（可重复）")
```

改为：

```swift
            Text("长按 3 秒打卡")
```

- [ ] **Step 2: 圆心由单行改为两行**

把 `Sources/Daka/PunchButton.swift:73-75` 的：

```swift
            Text(centerText)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
```

改为：

```swift
            VStack(spacing: 2) {
                ForEach(Array(centerLines.enumerated()), id: \.offset) { index, line in
                    Text(line)
                        .font(.system(size: index == 0 ? 15 : 12,
                                      weight: index == 0 ? .semibold : .regular))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(tint)
```

- [ ] **Step 3: 替换 `centerText` 为 `centerLines` + 时间格式化**

把 `Sources/Daka/PunchButton.swift:107-113` 的：

```swift
    private var centerText: String {
        if isPressing { return task.title }
        guard let elapsed = WorkProgress.elapsed(record, now: nowProvider(), minWorkDuration: minWorkDuration) else {
            return task.title
        }
        return WorkProgress.hoursText(elapsed)
    }
```

替换为：

```swift
    private var centerLines: [String] {
        if isPressing { return [task.title] }

        var lines: [String] = []
        if let punch = PunchRules.latestPunch(record, task: task) {
            lines.append(Self.timeFormatter.string(from: punch))
        } else {
            lines.append(task.title)
        }
        if let elapsed = WorkProgress.elapsed(record, now: nowProvider(), minWorkDuration: minWorkDuration) {
            lines.append(WorkProgress.hoursText(elapsed))
        }
        return lines
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
```

- [ ] **Step 4: 编译确认**

Run: `swift build`
Expected: `Build complete!`，无错误。

- [ ] **Step 5: 提交**

```bash
git add Sources/Daka/PunchButton.swift
git commit -m "feat: show punch time and work duration in ring center"
```

---

### Task 3: `MenuBarView` 行文案去时间 + 缩窄

**Files:**
- Modify: `Sources/Daka/MenuBarView.swift`

- [ ] **Step 1: 更新两处调用点**

把 `Sources/Daka/MenuBarView.swift:24-29` 的：

```swift
                statusRow(.morning, done: model.record.morningDone, at: model.record.morningDoneAt,
                          count: model.record.morningPunches.count,
                          start: model.settings.morningWindowStart, deadline: model.settings.morningDeadline)
                statusRow(.evening, done: model.isEveningComplete, at: model.effectiveEveningPunch,
                          count: model.record.eveningPunches.count,
                          start: model.settings.eveningWindowStart, deadline: model.settings.eveningDeadline)
```

改为：

```swift
                statusRow(.morning, done: model.record.morningDone,
                          count: model.record.morningPunches.count,
                          deadline: model.settings.morningDeadline)
                statusRow(.evening, done: model.isEveningComplete,
                          count: model.record.eveningPunches.count,
                          deadline: model.settings.eveningDeadline)
```

- [ ] **Step 2: 重写 `statusRow`（去时间）**

把 `Sources/Daka/MenuBarView.swift:51-73` 整个 `statusRow` 方法替换为：

```swift
    private func statusRow(_ task: PunchTask, done: Bool, count: Int, deadline: String) -> some View {
        let suffix = count > 1 ? "（\(count) 次）" : ""
        return HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(task.title)
            Spacer()
            if done {
                Text("已完成\(suffix)").foregroundStyle(.secondary)
            } else if scheduleInactive {
                Text("今日不提醒").foregroundStyle(.secondary)
            } else if model.reminderState.contains(task) {
                if let due = DakaDate.date(on: model.now, at: deadline), model.now >= due {
                    Text("已过截止\(suffix)").foregroundStyle(.red)
                } else {
                    Text("窗口内\(suffix)").foregroundStyle(.orange)
                }
            } else {
                Text("待打卡\(suffix)").foregroundStyle(.secondary)
            }
        }
    }
```

- [ ] **Step 3: 删除已无用的 `timeFormatter`**

删除 `Sources/Daka/MenuBarView.swift` 末尾（原第 75-79 行）：

```swift
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
```

- [ ] **Step 4: 缩窄弹窗**

把 `Sources/Daka/MenuBarView.swift:42` 的：

```swift
        .frame(width: 220)
```

改为：

```swift
        .frame(width: 180)
```

- [ ] **Step 5: 编译确认**

Run: `swift build`
Expected: `Build complete!`，无错误、无未使用告警。

- [ ] **Step 6: 提交**

```bash
git add Sources/Daka/MenuBarView.swift
git commit -m "feat: drop times from menu bar rows and narrow panel"
```

---

### Task 4: 文档与整体构建验证

**Files:**
- Modify: `docs/verification.md`

- [ ] **Step 1: 更新 v4 里过时的行文案描述**

把 `docs/verification.md:66`：

```markdown
- [ ] 状态行在重复打卡后显示次数，如「17:00（2 次）」；上班显示最早时间，下班显示最晚时间。
```

改为：

```markdown
- [ ] 状态行在重复打卡后显示次数，如「已完成（2 次）」（具体时间已移到圆形按钮圆心）。
```

- [ ] **Step 2: 更新 v15 圆心描述**

把 `docs/verification.md:154`：

```markdown
- [ ] 上班打卡后：圆环按「已工作时长 / 最少工时」填充（如 8 小时制上班 4 小时后约 50%），圆心显示 `4h` 字样。
```

改为：

```markdown
- [ ] 上班打卡后：圆环按「已工作时长 / 最少工时」填充（如 8 小时制上班 4 小时后约 50%），圆心上行显示最近打卡时间（如 `09:05`）、下行显示已工作时长（如 `4h`）。
```

- [ ] **Step 3: 新增 v16 小节**

在 `docs/verification.md` 末尾追加：

```markdown
## v16：菜单栏弹窗紧凑化 + 圆环显示打卡时间

- [ ] 菜单栏下拉两行状态不再显示任何时间，只有「已完成 / 待打卡 / 窗口内 / 已过截止 / 今日不提醒」，重复次数仍显示为「（N 次）」。
- [ ] 弹窗整体更窄（220 → 200，状态文字放不下时自动缩小）。
- [ ] 圆形按钮圆心两行：上行上班打卡时间（如 `09:05`），下行已工作时长（如 `4h`）；未打上班卡时上行显示「上班打卡」且无下行。
- [ ] 圆形按钮下方文字为「长按 3 秒打卡」（不再有「（可重复）」）。
- [ ] 长按期间圆心仍显示任务标题与 3 秒进度。
- [ ] 桌宠气泡面板里的圆形按钮同样显示两行。
```

- [ ] **Step 4: 全量测试**

Run: `swift test`
Expected: 全部用例通过（含新增的 `PunchRulesTests`）。

- [ ] **Step 5: 构建并安装 App**

Run: `make install`
Expected: 输出 `Built build/Daka.app` 与 `Installed to /Applications/Daka.app`。

- [ ] **Step 6: 提交**

```bash
git add docs/verification.md
git commit -m "docs: verify compact menu bar and ring punch time"
```

---

## Self-Review

**Spec coverage：** §3 布局（Task 3 Step 2/4）、§4 行文案（Task 3 Step 2）、§5 圆心两行（Task 2）、§6 应用层改动（Task 2/3）、§7 `latestPunch`（Task 1）、§8 测试（Task 1 Step 1、Task 4 Step 4）、§10 交付（Task 4）。§9 多屏说明为文档性内容，无需代码任务。

**Placeholder scan：** 无 TBD/TODO；所有代码步骤均给出完整代码。

**Type consistency：** `centerLines` 在 Task 2 定义并使用；`statusRow` 新签名（`done:count:deadline:`）与 Task 3 调用点一致。

---

## 执行修订（2026-09-16）

代码评审发现：Task 1 的 `PunchRules.latestPunch(record:task:)` 取「当前目标任务」的最近打卡，但 `PunchTarget.resolve` 在上班后即切到下班，下班未打卡时返回 nil，导致白天圆心只显示「下班打卡」，看不到上班时间，与目标（把已打卡时间移进圆心）相反。

经确认改为**固定显示上班打卡时间** `record.morningDoneAt`：

- Task 1 作废：移除 `PunchRules.latestPunch` 及其两个测试（该 API 不再需要）。
- Task 2 Step 3 中 `centerLines` 第 1 行改为：
  ```swift
  if let morning = record.morningDoneAt {
      lines.append(Self.timeFormatter.string(from: morning))
  } else {
      lines.append(task.title)
  }
  ```
- 相应更新 spec §5/§7/§8 与 verification v16 文案。
