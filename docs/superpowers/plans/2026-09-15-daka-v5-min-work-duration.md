# Daka v5（最少工时）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 下班打卡只有距当天最早上班打卡满 `minWorkDurationHours`（默认 8h）才算「完成」；不满则继续全屏催，可重复打卡直到合格。

**Architecture:** 新增纯函数 `PunchRules` 计算「有效下班打卡」；`Settings` 增加 `minWorkDurationHours`；`ScheduleEvaluator`/`Statistics`/`PunchTarget`/UI 统一改用该判定。记录仍保留全部打卡。

**Spec:** `docs/superpowers/specs/2026-09-15-daka-min-work-duration-design.md`

---

## Task 1: 核心 —— 最少工时判定

**Files:**
- Modify: `Sources/DakaCore/Models.swift`（`Settings`）
- Create: `Sources/DakaCore/PunchRules.swift`
- Modify: `Sources/DakaCore/ScheduleEvaluator.swift`
- Modify: `Sources/DakaCore/Statistics.swift`
- Modify: `Sources/DakaCore/PunchTarget.swift`
- Create: `Tests/DakaCoreTests/PunchRulesTests.swift`
- Modify: `Tests/DakaCoreTests/{SettingsTests,ScheduleEvaluatorTests,StatisticsTests,PunchTargetTests}.swift`

### 1.1 `Settings` 增加最少工时

在 `Settings` 增加存储属性 `public var minWorkDurationHours: Double`，init 参数 `minWorkDurationHours: Double = 8`，`CodingKeys` 加 `case minWorkDurationHours`，`init(from:)` 加
`self.minWorkDurationHours = try c.decodeIfPresent(Double.self, forKey: .minWorkDurationHours) ?? d.minWorkDurationHours`。
并新增计算属性：

```swift
    public var minWorkDuration: TimeInterval { max(0, minWorkDurationHours) * 3600 }
```

### 1.2 新增 `Sources/DakaCore/PunchRules.swift`

```swift
import Foundation

public enum PunchRules {
    /// 满足最少工时的最晚下班打卡；无上班卡或无合格下班卡时为 nil。
    public static func effectiveEveningPunch(_ record: DayRecord,
                                             minWorkDuration: TimeInterval) -> Date? {
        guard let morning = record.morningDoneAt else { return nil }
        return record.eveningPunches
            .filter { $0.timeIntervalSince(morning) >= minWorkDuration }
            .max()
    }

    public static func isEveningComplete(_ record: DayRecord,
                                         minWorkDuration: TimeInterval) -> Bool {
        effectiveEveningPunch(record, minWorkDuration: minWorkDuration) != nil
    }
}
```

### 1.3 `ScheduleEvaluator`

`pendingReminders` 中上班仍用 `record.morningDone`，下班改为
`PunchRules.isEveningComplete(record, minWorkDuration: settings.minWorkDuration)`。

### 1.4 `Statistics`

- `completedBoth = record.morningDone && PunchRules.isEveningComplete(record, minWorkDuration: settings.minWorkDuration)`。
- `DailyStat.eveningDoneAt = PunchRules.effectiveEveningPunch(...)`；`workDuration` 用 `effectiveEvening − record.morningDoneAt`（两者都在且 `effective >= morning`）。
- 其余（monthPunch、missed、streak）沿用 `completedBoth`。

### 1.5 `PunchTarget`

```swift
    public static func resolve(record: DayRecord,
                               now: Date,
                               minWorkDuration: TimeInterval,
                               calendar: Calendar = .current) -> PunchTask {
        if !record.morningDone { return .morning }
        if !PunchRules.isEveningComplete(record, minWorkDuration: minWorkDuration) { return .evening }
        let hour = calendar.component(.hour, from: now)
        return hour < 12 ? .morning : .evening
    }
```

### 1.6 测试

- 新增 `Tests/DakaCoreTests/PunchRulesTests.swift`：
  - 无上班卡 → `effectiveEveningPunch == nil`。
  - 上班 09:00、下班 16:00 → nil（7h）；下班 17:00 → 17:00（8h）。
  - 上下班 09:00 + [17:00, 18:00] → 18:00。
  - `minWorkDuration = 0` → 有下班卡即合格。
- `SettingsTests`：默认 `minWorkDurationHours == 8`；旧 JSON 缺该键 → 8；往返一致。
- `ScheduleEvaluatorTests`：新增用例——上班 09:00、下班 17:00（7h）时，在下班截止后 `pendingReminders` 仍含 evening(.hard)；下班 18:00（9h）时无 evening。
- `StatisticsTests`：把 `records(_:)` 帮助函数里「done 但无时间戳」的兜底改为当天 09:00 / 18:00：
```swift
            let defaultMorning = DakaDate.date(on: day, at: "09:00", calendar: cal) ?? day
            let defaultEvening = DakaDate.date(on: day, at: "18:00", calendar: cal) ?? day
            r.morningPunches = morning ? [mat ?? defaultMorning] : []
            r.eveningPunches = evening ? [eat ?? defaultEvening] : []
```
  并新增：仅有 7h 的下班卡 → `completedBoth == false`、不计时长、算缺卡。
- `PunchTargetTests`：给 `resolve` 调用补 `minWorkDuration:` 参数（用 `8 * 3600`）；新增——下班有卡但不足 8h → 目标仍为 `.evening`。

### 1.7 验证

`swift build && swift test`（数量会因新增用例上升，全绿即可）。提交：
`git commit -m "feat: enforce minimum work duration before evening punch counts"`

---

## Task 2: 应用层 —— 设置项与展示

**Files:**
- Modify: `Sources/Daka/AppModel.swift`
- Modify: `Sources/Daka/MenuBarView.swift`
- Modify: `Sources/Daka/SettingsView.swift`

- `AppModel` 增加：
```swift
    var minWorkDuration: TimeInterval { settings.minWorkDuration }
    var effectiveEveningPunch: Date? {
        PunchRules.effectiveEveningPunch(record, minWorkDuration: settings.minWorkDuration)
    }
    var isEveningComplete: Bool {
        PunchRules.isEveningComplete(record, minWorkDuration: settings.minWorkDuration)
    }
    func setMinWorkHours(_ hours: Double) {
        updateSettings { $0.minWorkDurationHours = hours }
    }
```
- `MenuBarView`：
  - 下班状态行「完成时间」用 `model.effectiveEveningPunch`（未完成时按 hard/gentle/待打卡显示）；次数仍用 `record.eveningPunches.count`。
  - 圆形按钮目标：`PunchTarget.resolve(record: model.record, now: model.now, minWorkDuration: model.minWorkDuration)`。
- `SettingsView`：新增「每日最少工时」`Stepper`（1...12，步进 0.5，显示 `X 小时`），绑定 `setMinWorkHours`。

### 验证

`swift build && swift test`；`make install`。提交：
`git commit -m "feat: surface minimum work duration in settings and menu bar"`

---

## Task 3: 文档

- `docs/verification.md` 增加 v5 条目：下班不满最少工时不算完成、继续全屏催、可重复打卡到合格；设置里可改最少工时；无上班卡时下班不算完成。
- `make install`。

提交 `docs: verify minimum work duration`。

---

## 完成标准

- `swift test` 全绿。
- 下班打卡距最早上班 ≥ 最少工时才算完成；不满继续全屏催。
- 无上班卡 → 下班不算完成。
- 设置里可改最少工时（默认 8h）。
