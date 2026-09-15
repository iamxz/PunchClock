# Daka v4（重复打卡）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 同一天同一项可重复打卡，保留全部时间点；统计上班取最早、下班取最晚；菜单栏圆形按钮始终可重复打。

**Architecture:** `DayRecord` 以 `morningPunches`/`eveningPunches` 数组为数据源，`morningDone`/`morningDoneAt` 等改为只读计算属性（调用方不变）；`PunchStore.mark` 追加；新增纯函数 `PunchTarget.resolve` 决定菜单栏按钮打项。

**Spec:** `docs/superpowers/specs/2026-09-15-daka-repeat-punch-design.md`

---

## Task 1: 核心 —— 打卡时间列表

**Files:**
- Modify: `Sources/DakaCore/Models.swift`（`DayRecord`）
- Create: `Sources/DakaCore/PunchTarget.swift`
- Modify: `Sources/DakaCore/PunchStore.swift`（`mark` 追加）
- Modify: `Tests/DakaCoreTests/ScheduleEvaluatorTests.swift`、`StatisticsTests.swift`、`PunchStoreTests.swift`
- Create: `Tests/DakaCoreTests/PunchTargetTests.swift`

### 1.1 `DayRecord`（替换整个结构体）

```swift
public struct DayRecord: Codable, Equatable, Sendable {
    public var morningPunches: [Date]
    public var eveningPunches: [Date]
    public var skipped: Bool

    public init(morningPunches: [Date] = [], eveningPunches: [Date] = [], skipped: Bool = false) {
        self.morningPunches = morningPunches
        self.eveningPunches = eveningPunches
        self.skipped = skipped
    }

    public var morningDone: Bool { !morningPunches.isEmpty }
    public var eveningDone: Bool { !eveningPunches.isEmpty }
    public var morningDoneAt: Date? { morningPunches.min() }
    public var eveningDoneAt: Date? { eveningPunches.max() }

    public func isDone(_ task: PunchTask) -> Bool {
        switch task {
        case .morning: return morningDone
        case .evening: return eveningDone
        }
    }

    private enum CodingKeys: String, CodingKey {
        case morningPunches, eveningPunches, skipped
        case morningDone, morningDoneAt, eveningDone, eveningDoneAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.skipped = try c.decodeIfPresent(Bool.self, forKey: .skipped) ?? false

        if let morning = try c.decodeIfPresent([Date].self, forKey: .morningPunches) {
            self.morningPunches = morning
        } else if try c.decodeIfPresent(Bool.self, forKey: .morningDone) ?? false {
            self.morningPunches = [try c.decodeIfPresent(Date.self, forKey: .morningDoneAt) ?? Date()]
        } else {
            self.morningPunches = []
        }

        if let evening = try c.decodeIfPresent([Date].self, forKey: .eveningPunches) {
            self.eveningPunches = evening
        } else if try c.decodeIfPresent(Bool.self, forKey: .eveningDone) ?? false {
            self.eveningPunches = [try c.decodeIfPresent(Date.self, forKey: .eveningDoneAt) ?? Date()]
        } else {
            self.eveningPunches = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(morningPunches, forKey: .morningPunches)
        try c.encode(eveningPunches, forKey: .eveningPunches)
        try c.encode(skipped, forKey: .skipped)
    }
}
```

### 1.2 新增 `Sources/DakaCore/PunchTarget.swift`

```swift
import Foundation

public enum PunchTarget {
    /// 菜单栏圆形按钮的目标项：待办优先；都完成后按时间补打（12 点前上班，之后下班）。
    public static func resolve(record: DayRecord, now: Date, calendar: Calendar = .current) -> PunchTask {
        if !record.morningDone { return .morning }
        if !record.eveningDone { return .evening }
        let hour = calendar.component(.hour, from: now)
        return hour < 12 ? .morning : .evening
    }
}
```

### 1.3 `PunchStore.mark` 追加

```swift
        switch task {
        case .morning:
            rec.morningPunches.append(date)
        case .evening:
            rec.eveningPunches.append(date)
        }
```

### 1.4 测试改动

- `ScheduleEvaluatorTests`：把 `var record = DayRecord(); record.morningDone = true` 之类改为构造数组，例如：
  - `DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])`
  - 两项都要时：`DayRecord(morningPunches: [...], eveningPunches: [...])`
  - `skipped` 仍用 `DayRecord(skipped: true)`。
- `StatisticsTests.records(:)` 帮助函数改为：
```swift
            r.morningPunches = morning ? [mat ?? Date(timeIntervalSince1970: 0)] : []
            r.eveningPunches = evening ? [eat ?? Date(timeIntervalSince1970: 0)] : []
```
- `PunchStoreTests` 新增：
```swift
    func testMorningPunchesAccumulateEarliestWins() throws {
        let first = TestTime.date(2026, 9, 14, 9, 0)
        let second = TestTime.date(2026, 9, 14, 10, 30)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: first, calendar: TestTime.calendar)
        try store.mark(.morning, at: second, calendar: TestTime.calendar)
        let record = store.record(for: first, calendar: TestTime.calendar)
        XCTAssertEqual(record.morningPunches.count, 2)
        XCTAssertEqual(record.morningDoneAt?.timeIntervalSince1970 ?? 0, first.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(record.eveningPunches.count, 0)
        let reloaded = PunchStore(fileURL: url)
        XCTAssertEqual(reloaded.record(for: first, calendar: TestTime.calendar).morningPunches.count, 2)
    }

    func testEveningPunchesAccumulateLatestWins() throws {
        let first = TestTime.date(2026, 9, 14, 17, 0)
        let second = TestTime.date(2026, 9, 14, 18, 10)
        let store = PunchStore(fileURL: url)
        try store.mark(.evening, at: first, calendar: TestTime.calendar)
        try store.mark(.evening, at: second, calendar: TestTime.calendar)
        let record = store.record(for: first, calendar: TestTime.calendar)
        XCTAssertEqual(record.eveningPunches.count, 2)
        XCTAssertEqual(record.eveningDoneAt?.timeIntervalSince1970 ?? 0, second.timeIntervalSince1970, accuracy: 1)
    }

    func testLegacyRecordDecodesToPunchList() throws {
        let legacyJSON = """
        {
          "morningDone": true,
          "morningDoneAt": "2026-09-14T01:00:00Z",
          "eveningDone": false,
          "skipped": false
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DayRecord.self, from: legacyJSON)
        XCTAssertEqual(decoded.morningPunches.count, 1)
        XCTAssertTrue(decoded.morningDone)
        XCTAssertFalse(decoded.eveningDone)
    }
```
- 新增 `Tests/DakaCoreTests/PunchTargetTests.swift`（5 个断言）：未打上班→morning；上班已打→evening；都打完 09:00→morning；都打完 15:00→evening；都打完 12:00→evening。

### 1.5 验证

`swift build && swift test`（期望原 63 + 新增约 9 ≈ 72）。提交：
`git commit -m "feat: repeat punches with morning-earliest/evening-latest semantics"`

---

## Task 2: 菜单栏圆形按钮 —— 始终可重复打卡

**Files:**
- Modify: `Sources/Daka/PunchButton.swift`
- Modify: `Sources/Daka/MenuBarView.swift`

- `PunchButton.task` 改为**非可选** `PunchTask`；去掉「已完成」禁用态与 `nil` 分支；无障碍标签用 `task.title`；提示文案「长按 3 秒打卡（可重复）」。
- `MenuBarView` 用 `PunchTarget.resolve(record: model.record, now: model.now)` 作为目标项，始终传入。
- 状态行显示时间（上班最早/下班最晚，已由 `DayRecord` 计算属性提供）；在两行下方或行内显示打卡次数，如「上班 09:01（2 次）」。

### 验证

`swift build && swift test`；`make install`。提交：
`git commit -m "feat: always-available repeat punch button in menu bar"`

---

## Task 3: 文档

- `docs/verification.md` 增加：同一天可重复打卡；上班取最早、下班取最晚；菜单栏按钮在都打完后按时间补打（12 点前上班 / 12 点后下班）；旧数据平滑升级。
- `make install`。

提交 `docs: verify repeat punches`。

---

## 完成标准

- `swift test` 全绿（≥72）。
- 同一天可对上班/下班各打多次，记录全部保留；统计用上班最早/下班最晚。
- 菜单栏圆形按钮始终可打；都完成后按时间补打。
