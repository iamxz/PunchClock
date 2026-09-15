# Daka v12 补卡 + v13 单一强提醒 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让用户能修正今天的打卡记录（补卡 / 改时间 / 删除），并把「温和 + 强制」两级提醒改成「进入窗口即全屏强提醒、按可配置间隔重复、直到完成」。

**Architecture:** `DakaCore` 保持纯逻辑可单测：`PunchStore` 新增改/删打卡方法；`ReminderState` 简化为单一待打卡集合，`ScheduleEvaluator` 返回 `[PunchTask]`，`Scheduler` 只驱动全屏强提醒。应用层 `AppModel` 增加包装方法，`PunchToolView` 加「今日打卡」列表与编辑弹窗，设置页加重复间隔。

**Tech Stack:** Swift 5.10 / SwiftPM、AppKit + SwiftUI、Swift Charts、XCTest。

**Specs:**
- `docs/superpowers/specs/2026-09-15-daka-punch-correction-design.md`（v12）
- `docs/superpowers/specs/2026-09-15-daka-hard-only-reminder-design.md`（v13）

---

## File Structure

**Modify**
- `Sources/DakaCore/PunchStore.swift` — 新增 `updatePunch` / `removePunch`
- `Sources/DakaCore/Models.swift` — 删除 `ReminderLevel` / `PendingReminder`，简化 `ReminderState`
- `Sources/DakaCore/ScheduleEvaluator.swift` — 返回 `[PunchTask]`
- `Sources/DakaCore/Scheduler.swift` — 只走 hard 路径
- `Sources/DakaCore/PetMood.swift` — `gentlePending`/`hardPending` → `punchPending`
- `Sources/Daka/ReminderController.swift` — 删除 gentle / 通知；间隔即时生效
- `Sources/Daka/AppModel.swift` — 补卡包装 + 间隔 setter
- `Sources/Daka/PunchToolView.swift` — 今日打卡列表 + 编辑 sheet
- `Sources/Daka/SettingsPages.swift` — 重复提醒间隔
- `Sources/Daka/DakaApp.swift` — 菜单栏图标两态
- `Sources/Daka/MenuBarView.swift` — 状态行去 gentle
- `Tests/DakaCoreTests/PunchStoreTests.swift` — 改/删测试
- `Tests/DakaCoreTests/ScheduleEvaluatorTests.swift` — 新判定
- `Tests/DakaCoreTests/SchedulerTests.swift` — 新状态与 SpyPresenter
- `Tests/DakaCoreTests/PetMoodTests.swift` — 合并表情
- `README.md`、`docs/verification.md` — 文案与验证清单

**不新增源文件。** `Sources/Daka/GentleNotifier.swift` 保留（健康提醒仍在用）。

**统一验证命令：** `make test`（等价 `swift test`），编译用 `make build`。

---

## Phase A — v12 补卡 / 改时间 / 删除

### Task 1: PunchStore 支持修改与删除打卡

**Files:**
- Modify: `Sources/DakaCore/PunchStore.swift`
- Test: `Tests/DakaCoreTests/PunchStoreTests.swift`

- [ ] **Step 1: 写失败测试**

在 `Tests/DakaCoreTests/PunchStoreTests.swift` 末尾（最后一个 `}` 之前）追加：

```swift
    func testUpdatePunchReplacesTimeInPlace() throws {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let original = TestTime.date(2026, 9, 14, 9, 5)
        let corrected = TestTime.date(2026, 9, 14, 8, 50)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: original, calendar: TestTime.calendar)
        try store.updatePunch(.morning, at: 0, to: corrected, on: day, calendar: TestTime.calendar)

        let record = store.record(for: day, calendar: TestTime.calendar)
        XCTAssertEqual(record.morningPunches.count, 1)
        XCTAssertEqual(record.morningDoneAt?.timeIntervalSince1970 ?? 0,
                       corrected.timeIntervalSince1970, accuracy: 1)

        let reloaded = PunchStore(fileURL: url)
        XCTAssertEqual(reloaded.record(for: day, calendar: TestTime.calendar).morningDoneAt?.timeIntervalSince1970 ?? 0,
                       corrected.timeIntervalSince1970, accuracy: 1)
    }

    func testRemovePunchDeletesEntry() throws {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let first = TestTime.date(2026, 9, 14, 9, 0)
        let second = TestTime.date(2026, 9, 14, 9, 10)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: first, calendar: TestTime.calendar)
        try store.mark(.morning, at: second, calendar: TestTime.calendar)
        try store.removePunch(.morning, at: 0, on: day, calendar: TestTime.calendar)

        let record = store.record(for: day, calendar: TestTime.calendar)
        XCTAssertEqual(record.morningPunches.count, 1)
        XCTAssertEqual(record.morningDoneAt?.timeIntervalSince1970 ?? 0,
                       second.timeIntervalSince1970, accuracy: 1)
    }

    func testRemoveLastMorningPunchMakesUndone() throws {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: day, calendar: TestTime.calendar)
        try store.removePunch(.morning, at: 0, on: day, calendar: TestTime.calendar)

        let record = store.record(for: day, calendar: TestTime.calendar)
        XCTAssertFalse(record.morningDone)
        XCTAssertNil(record.morningDoneAt)
    }

    func testUpdateAndRemoveOutOfRangeAreNoOp() throws {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let store = PunchStore(fileURL: url)
        try store.mark(.morning, at: day, calendar: TestTime.calendar)
        let before = store.record(for: day, calendar: TestTime.calendar).morningPunches

        try store.updatePunch(.morning, at: 5, to: TestTime.date(2026, 9, 14, 10, 0),
                              on: day, calendar: TestTime.calendar)
        try store.removePunch(.morning, at: 5, on: day, calendar: TestTime.calendar)

        XCTAssertEqual(store.record(for: day, calendar: TestTime.calendar).morningPunches, before)
    }

    func testUpdateAndRemoveEvening() throws {
        let day = TestTime.date(2026, 9, 14, 18, 0)
        let store = PunchStore(fileURL: url)
        try store.mark(.evening, at: TestTime.date(2026, 9, 14, 18, 0), calendar: TestTime.calendar)
        try store.mark(.evening, at: TestTime.date(2026, 9, 14, 18, 30), calendar: TestTime.calendar)

        try store.updatePunch(.evening, at: 1, to: TestTime.date(2026, 9, 14, 18, 45),
                              on: day, calendar: TestTime.calendar)
        XCTAssertEqual(store.record(for: day, calendar: TestTime.calendar).eveningDoneAt?.timeIntervalSince1970 ?? 0,
                       TestTime.date(2026, 9, 14, 18, 45).timeIntervalSince1970, accuracy: 1)

        try store.removePunch(.evening, at: 0, on: day, calendar: TestTime.calendar)
        XCTAssertEqual(store.record(for: day, calendar: TestTime.calendar).eveningPunches.count, 1)
    }
```

- [ ] **Step 2: 运行测试，确认失败**

Run: `swift test --filter PunchStoreTests`
Expected: 编译失败，`value of type 'PunchStore' has no member 'updatePunch'`（以及 `removePunch`）。

- [ ] **Step 3: 实现 `updatePunch` / `removePunch`**

在 `Sources/DakaCore/PunchStore.swift` 的 `mark(_:at:calendar:)` 方法之后、`setSkipped` 之前插入：

```swift
    public func updatePunch(_ task: PunchTask,
                            at index: Int,
                            to date: Date,
                            on day: Date,
                            calendar: Calendar = .current) throws {
        let key = DakaDate.key(for: day, calendar: calendar)
        let previous = data.records[key]
        var rec = previous ?? DayRecord()
        switch task {
        case .morning:
            guard rec.morningPunches.indices.contains(index) else { return }
            rec.morningPunches[index] = date
        case .evening:
            guard rec.eveningPunches.indices.contains(index) else { return }
            rec.eveningPunches[index] = date
        }
        data.records[key] = rec
        try persist(rollingBack: { self.data.records[key] = previous })
    }

    public func removePunch(_ task: PunchTask,
                            at index: Int,
                            on day: Date,
                            calendar: Calendar = .current) throws {
        let key = DakaDate.key(for: day, calendar: calendar)
        let previous = data.records[key]
        var rec = previous ?? DayRecord()
        switch task {
        case .morning:
            guard rec.morningPunches.indices.contains(index) else { return }
            rec.morningPunches.remove(at: index)
        case .evening:
            guard rec.eveningPunches.indices.contains(index) else { return }
            rec.eveningPunches.remove(at: index)
        }
        data.records[key] = rec
        try persist(rollingBack: { self.data.records[key] = previous })
    }
```

- [ ] **Step 4: 运行测试，确认通过**

Run: `swift test --filter PunchStoreTests`
Expected: PASS（全部用例）。

- [ ] **Step 5: 提交**

```bash
git add Sources/DakaCore/PunchStore.swift Tests/DakaCoreTests/PunchStoreTests.swift
git commit -m "feat: allow editing and deleting today's punches in store"
```

---

### Task 2: AppModel 包装补卡 / 改时间 / 删除

**Files:**
- Modify: `Sources/Daka/AppModel.swift`

- [ ] **Step 1: 新增三个方法**

在 `Sources/Daka/AppModel.swift` 的 `punch(_:)` 方法（约 244-253 行）之后插入：

```swift
    func addPunch(_ task: PunchTask, at time: Date) {
        errorMessage = nil
        do {
            try store.mark(task, at: time)
            refreshRecord()
            scheduler?.tick()
        } catch {
            errorMessage = "打卡记录写入失败：\(error.localizedDescription)"
        }
    }

    func updatePunch(_ task: PunchTask, index: Int, to time: Date) {
        errorMessage = nil
        do {
            try store.updatePunch(task, at: index, to: time, on: clock.now)
            refreshRecord()
            scheduler?.tick()
        } catch {
            errorMessage = "打卡记录写入失败：\(error.localizedDescription)"
        }
    }

    func removePunch(_ task: PunchTask, index: Int) {
        errorMessage = nil
        do {
            try store.removePunch(task, at: index, on: clock.now)
            refreshRecord()
            scheduler?.tick()
        } catch {
            errorMessage = "打卡记录写入失败：\(error.localizedDescription)"
        }
    }
```

- [ ] **Step 2: 编译**

Run: `make build`
Expected: `Build complete!`（无错误）。

- [ ] **Step 3: 提交**

```bash
git add Sources/Daka/AppModel.swift
git commit -m "feat: add AppModel wrappers for punch correction"
```

---

### Task 3: 控制中心「今日打卡」列表与编辑弹窗

**Files:**
- Modify: `Sources/Daka/PunchToolView.swift`（整体替换）

- [ ] **Step 1: 替换 `PunchToolView.swift`**

将 `Sources/Daka/PunchToolView.swift` 全文替换为：

```swift
import SwiftUI
import DakaCore

struct PunchEditorTarget: Identifiable {
    let task: PunchTask
    let index: Int?
    let initial: Date

    var id: String { "\(task.rawValue)-\(index.map(String.init) ?? "new")" }
    var isNew: Bool { index == nil }
}

struct PunchToolView: View {
    @ObservedObject var model: AppModel
    @State private var editor: PunchEditorTarget?
    @State private var pendingDeletion: PunchEditorTarget?

    var body: some View {
        VStack(spacing: 16) {
            todayPunches

            HStack {
                if model.record.skipped {
                    Button("恢复打卡提醒") { model.setSkipped(false) }
                } else {
                    Button("标记今天不打卡（休假）") { model.setSkipped(true) }
                }
                Spacer()
            }

            StatisticsView(model: model)
        }
        .sheet(item: $editor) { target in
            PunchTimeEditor(model: model, target: target)
        }
        .confirmationDialog("删除这条打卡记录？", isPresented: deletionBinding, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let target = pendingDeletion, let index = target.index {
                    model.removePunch(target.task, index: index)
                }
                pendingDeletion = nil
            }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } })
    }

    private var todayPunches: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日打卡").font(.headline)
            taskSection(.morning, dates: model.record.morningPunches)
            Divider()
            taskSection(.evening, dates: model.record.eveningPunches)
        }
    }

    private func taskSection(_ task: PunchTask, dates: [Date]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(task.title, systemImage: task == .morning ? "sunrise" : "sunset")
                Spacer()
                Button {
                    editor = PunchEditorTarget(task: task, index: nil, initial: model.now)
                } label: {
                    Label("补卡", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            if dates.isEmpty {
                Text("今天还没有打卡")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                    HStack {
                        Text(Self.timeFormatter.string(from: date))
                            .monospacedDigit()
                        Spacer()
                        Button("改时间") {
                            editor = PunchEditorTarget(task: task, index: index, initial: date)
                        }
                        .buttonStyle(.borderless)
                        Button("删除", role: .destructive) {
                            pendingDeletion = PunchEditorTarget(task: task, index: index, initial: date)
                        }
                        .buttonStyle(.borderless)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

struct PunchTimeEditor: View {
    @ObservedObject var model: AppModel
    let target: PunchEditorTarget
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date

    init(model: AppModel, target: PunchEditorTarget) {
        self.model = model
        self.target = target
        _time = State(initialValue: target.initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(target.isNew ? "补卡 · \(target.task.title)" : "修改时间 · \(target.task.title)")
                .font(.headline)
            DatePicker("打卡时间", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    if let index = target.index {
                        model.updatePunch(target.task, index: index, to: time)
                    } else {
                        model.addPunch(target.task, at: time)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
```

- [ ] **Step 2: 编译**

Run: `make build`
Expected: `Build complete!`。

- [ ] **Step 3: 手动验证（可选，但建议）**

Run: `make app && open build/Daka.app`，在控制中心「打卡统计」页：
- 「补卡」→ 时间选择器默认当前时间，保存后列表出现该条；
- 「改时间」→ 默认该条原时间，保存后时间变化；
- 「删除」→ 二次确认后记录消失；
- 改/删后统计卡与柱状图同步刷新。

- [ ] **Step 4: 提交**

```bash
git add Sources/Daka/PunchToolView.swift
git commit -m "feat: add today's punch list with make-up/edit/delete UI"
```

---

## Phase B — v13 单一强提醒 + 可配置间隔

> 说明：`ReminderState` 类型简化会牵动 `ScheduleEvaluator` / `Scheduler` / `ReminderPresenting` / `ReminderController` / 菜单栏 / 桌宠 / 测试。Swift 按模块整体编译，因此 Task 4 是**一个原子的类型重构**：先改测试与全部调用点，再统一 `swift test` 验证。

### Task 4: 删除轻提示，改为「窗口开始即全屏强提醒」

**Files:**
- Modify: `Sources/DakaCore/Models.swift`
- Modify: `Sources/DakaCore/ScheduleEvaluator.swift`
- Modify: `Sources/DakaCore/Scheduler.swift`
- Modify: `Sources/DakaCore/PetMood.swift`
- Modify: `Sources/Daka/ReminderController.swift`
- Modify: `Sources/Daka/DakaApp.swift`
- Modify: `Sources/Daka/MenuBarView.swift`
- Test: `Tests/DakaCoreTests/ScheduleEvaluatorTests.swift`
- Test: `Tests/DakaCoreTests/SchedulerTests.swift`
- Test: `Tests/DakaCoreTests/PetMoodTests.swift`

- [ ] **Step 1: 重写 `ScheduleEvaluatorTests.swift`**

将 `Tests/DakaCoreTests/ScheduleEvaluatorTests.swift` 全文替换为：

```swift
import XCTest
@testable import DakaCore

final class ScheduleEvaluatorTests: XCTestCase {
    private let evaluator = ScheduleEvaluator()
    private let cal = TestTime.calendar

    private func reminders(_ date: Date,
                           settings: Settings = .default,
                           record: DayRecord = DayRecord()) -> [PunchTask] {
        evaluator.pendingReminders(now: date, settings: settings, record: record, calendar: cal)
    }

    func testBeforeMorningWindowHasNoReminders() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 8, 59)), [])
    }

    func testAtMorningWindowStartIsPending() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 0)), [.morning])
    }

    func testWithinMorningWindowIsPending() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 29)), [.morning])
    }

    func testAfterMorningDeadlineStillPending() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 31)), [.morning])
    }

    func testBeforeEveningWindowMorningOnly() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 17, 59)), [.morning])
    }

    func testAtEveningWindowStartBothPending() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 0)), [.morning, .evening])
    }

    func testMorningDoneOnlyEveningPending() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 10), record: record), [.evening])
    }

    func testBothDoneNoReminders() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 30)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 23, 0), record: record), [])
    }

    func testEveningUnderMinimumKeepsReminding() {
        var settings = Settings.default
        settings.minWorkDurationHours = 8
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 16, 0)])
        let now = TestTime.date(2026, 9, 14, 18, 30)
        XCTAssertEqual(reminders(now, settings: settings, record: record), [.evening])
    }

    func testEveningAboveMinimumClears() {
        var settings = Settings.default
        settings.minWorkDurationHours = 8
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 18, 30)
        XCTAssertEqual(reminders(now, settings: settings, record: record), [])
    }

    func testWeekendNoReminders() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 19, 10, 0)), [])
    }

    func testDisabledNoReminders() {
        var settings = Settings.default
        settings.enabled = false
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), settings: settings), [])
    }

    func testSkippedNoReminders() {
        let record = DayRecord(skipped: true)
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), record: record), [])
    }

    func testInvalidMorningTimesYieldNoMorningReminder() {
        var settings = Settings.default
        settings.morningWindowStart = "oops"
        settings.morningDeadline = "oops"
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), settings: settings), [])
    }

    func testInvalidStartYieldsNoReminder() {
        var settings = Settings.default
        settings.morningWindowStart = "oops"
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), settings: settings), [])
    }
}
```

- [ ] **Step 2: 重写 `SchedulerTests.swift`**

将 `Tests/DakaCoreTests/SchedulerTests.swift` 全文替换为：

```swift
import XCTest
@testable import DakaCore

final class SpyPresenter: ReminderPresenting {
    var lastHard: [PunchTask]?
    var hideCount = 0
    var refreshCount = 0

    func showHard(tasks: [PunchTask], settings: Settings, now: Date) { lastHard = tasks }
    func refresh(settings: Settings, now: Date) { refreshCount += 1 }
    func hide() { lastHard = nil; hideCount += 1 }
}

final class SchedulerTests: XCTestCase {
    private var dir: URL!
    private var url: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("data.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeScheduler(now: Date) -> (Scheduler, FixedClock, PunchStore, SpyPresenter) {
        let clock = FixedClock(now)
        let store = PunchStore(fileURL: url)
        let presenter = SpyPresenter()
        let scheduler = Scheduler(clock: clock, store: store, presenter: presenter,
                                  interval: 1, calendar: TestTime.calendar)
        return (scheduler, clock, store, presenter)
    }

    func testNothingBeforeWindowHidesOnce() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 8, 0))
        scheduler.tick()
        XCTAssertNil(presenter.lastHard)
        XCTAssertEqual(presenter.hideCount, 1)
    }

    func testWindowStartShowsHard() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])
    }

    func testStaysHardAcrossTicks() {
        let (scheduler, clock, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])

        clock.now = TestTime.date(2026, 9, 14, 9, 30)
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])
    }

    func testHidesAfterPunch() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 5))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])

        try store.mark(.morning, at: clock.now, calendar: TestTime.calendar)
        scheduler.tick()
        XCTAssertNil(presenter.lastHard)
    }

    func testRefreshWhileStable() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        scheduler.tick()
        XCTAssertEqual(presenter.refreshCount, 0)
        scheduler.tick()
        XCTAssertEqual(presenter.refreshCount, 1)
    }

    func testStateCallbackAndState() {
        let (scheduler, _, _, _) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        var observed: [ReminderState] = []
        scheduler.onStateChange = { observed.append($0) }
        scheduler.tick()
        XCTAssertEqual(observed, [ReminderState(pending: [.morning])])
        XCTAssertEqual(scheduler.state, ReminderState(pending: [.morning]))
    }

    func testDayRolloverFiresCallback() {
        let (scheduler, clock, _, _) = makeScheduler(now: TestTime.date(2026, 9, 14, 8, 0))
        var observed: [ReminderState] = []
        scheduler.onStateChange = { observed.append($0) }
        scheduler.tick()
        clock.now = TestTime.date(2026, 9, 15, 8, 0)
        scheduler.tick()
        XCTAssertEqual(observed, [ReminderState(), ReminderState()])
    }

    func testWeekendNeverShows() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 19, 10, 0))
        scheduler.tick()
        XCTAssertNil(presenter.lastHard)
    }

    func testMorningPunchedSwitchesToEvening() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 18, 10))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning, .evening])

        try store.mark(.morning, at: clock.now, calendar: TestTime.calendar)
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.evening])
    }
}
```

- [ ] **Step 3: 重写 `PetMoodTests.swift`**

将 `Tests/DakaCoreTests/PetMoodTests.swift` 全文替换为：

```swift
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

    func testPunchPendingOverridesTime() {
        let state = ReminderState(pending: [.morning])
        let mood = PetMood.resolve(reminderState: state, now: TestTime.date(2026, 9, 14, 9, 0), calendar: cal)
        XCTAssertEqual(mood, .punchPending)
    }

    func testEveryMoodHasEmoji() {
        for mood in PetMood.allCases {
            XCTAssertFalse(mood.emoji.isEmpty)
        }
    }

    func testHealthOverridesTimeWithThirstyFirst() {
        let status = HealthStatus(cups: 0, stands: 0,
                                  minutesSinceDrink: 90, minutesSinceStand: 90,
                                  waterDue: true, movementDue: true, active: true)
        let mood = PetMood.resolve(reminderState: ReminderState(),
                                   now: TestTime.date(2026, 9, 14, 10, 0),
                                   health: status, calendar: cal)
        XCTAssertEqual(mood, .thirsty)
    }

    func testRestlessWhenOnlyMovementDue() {
        let status = HealthStatus(cups: 3, stands: 0,
                                  minutesSinceDrink: 10, minutesSinceStand: 90,
                                  waterDue: false, movementDue: true, active: true)
        let mood = PetMood.resolve(reminderState: ReminderState(),
                                   now: TestTime.date(2026, 9, 14, 10, 0),
                                   health: status, calendar: cal)
        XCTAssertEqual(mood, .restless)
    }

    func testPunchPendingOverridesHealth() {
        let status = HealthStatus(cups: 0, stands: 0,
                                  minutesSinceDrink: 90, minutesSinceStand: 90,
                                  waterDue: true, movementDue: true, active: true)
        let mood = PetMood.resolve(reminderState: ReminderState(pending: [.morning]),
                                   now: TestTime.date(2026, 9, 14, 10, 0),
                                   health: status, calendar: cal)
        XCTAssertEqual(mood, .punchPending)
    }

    func testIdleHealthStatusKeepsTimeMood() {
        let mood = PetMood.resolve(reminderState: ReminderState(),
                                   now: TestTime.date(2026, 9, 14, 10, 0),
                                   health: .idle, calendar: cal)
        XCTAssertEqual(mood, .cheerful)
    }
}
```

- [ ] **Step 4: 运行测试，确认因 API 变更而失败**

Run: `swift test`
Expected: 编译失败（`ReminderState` 无 `gentle`/`hard`、`PetMood.gentlePending` 不存在等）。

- [ ] **Step 5: 修改 `Models.swift`**

把 `Sources/DakaCore/Models.swift` 第 15-40 行的 `ReminderLevel`、`PendingReminder`、`ReminderState` 三块整体替换为：

```swift
public struct ReminderState: Equatable, Sendable {
    public var pending: [PunchTask]

    public init(pending: [PunchTask] = []) {
        self.pending = pending
    }

    public var isEmpty: Bool { pending.isEmpty }

    public func contains(_ task: PunchTask) -> Bool { pending.contains(task) }
}
```

- [ ] **Step 6: 修改 `ScheduleEvaluator.swift`**

将 `Sources/DakaCore/ScheduleEvaluator.swift` 全文替换为：

```swift
import Foundation

public struct ScheduleEvaluator {
    public init() {}

    public func pendingReminders(now: Date,
                                 settings: Settings,
                                 record: DayRecord,
                                 calendar: Calendar = .current) -> [PunchTask] {
        guard settings.enabled, !record.skipped else { return [] }
        guard settings.workdays.contains(DakaDate.weekday(of: now, calendar: calendar)) else { return [] }

        var tasks: [PunchTask] = []

        if pending(start: settings.morningWindowStart,
                   done: record.morningDone,
                   now: now,
                   calendar: calendar) {
            tasks.append(.morning)
        }
        if pending(start: settings.eveningWindowStart,
                   done: PunchRules.isEveningComplete(record, minWorkDuration: settings.minWorkDuration),
                   now: now,
                   calendar: calendar) {
            tasks.append(.evening)
        }
        return tasks
    }

    private func pending(start: String, done: Bool, now: Date, calendar: Calendar) -> Bool {
        guard !done else { return false }
        guard let startDate = DakaDate.date(on: now, at: start, calendar: calendar) else { return false }
        return now >= startDate
    }
}
```

- [ ] **Step 7: 修改 `Scheduler.swift`**

将 `Sources/DakaCore/Scheduler.swift` 全文替换为：

```swift
import Foundation

public protocol ReminderPresenting: AnyObject {
    func showHard(tasks: [PunchTask], settings: Settings, now: Date)
    func refresh(settings: Settings, now: Date)
    func hide()
}

public final class Scheduler {
    public var onStateChange: ((ReminderState) -> Void)?

    private let clock: DakaClock
    private let evaluator: ScheduleEvaluator
    private let store: PunchStore
    private weak var presenter: ReminderPresenting?
    private let interval: TimeInterval
    private let calendarOverride: Calendar?
    private var calendar: Calendar { calendarOverride ?? .current }

    private var timer: Timer?
    private var lastState: ReminderState?
    private var lastDayKey: String?

    public private(set) var state = ReminderState()

    public init(clock: DakaClock,
                evaluator: ScheduleEvaluator = ScheduleEvaluator(),
                store: PunchStore,
                presenter: ReminderPresenting,
                interval: TimeInterval = 1,
                calendar: Calendar? = nil) {
        self.clock = clock
        self.evaluator = evaluator
        self.store = store
        self.presenter = presenter
        self.interval = interval
        self.calendarOverride = calendar
    }

    deinit {
        stop()
    }

    public func start() {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func tick() {
        let now = clock.now
        let dayKey = DakaDate.key(for: now, calendar: calendar)
        let dayChanged = dayKey != lastDayKey
        lastDayKey = dayKey

        let settings = store.data.settings
        let record = store.record(for: now, calendar: calendar)
        let pending = evaluator.pendingReminders(now: now, settings: settings, record: record,
                                                 calendar: calendar)
        apply(state: ReminderState(pending: pending), settings: settings, now: now, dayChanged: dayChanged)
    }

    private func apply(state newState: ReminderState, settings: Settings, now: Date, dayChanged: Bool) {
        state = newState
        let changed = newState != lastState
        if changed {
            lastState = newState
            if !newState.pending.isEmpty {
                presenter?.showHard(tasks: newState.pending, settings: settings, now: now)
            } else {
                presenter?.hide()
            }
        } else if !newState.isEmpty {
            presenter?.refresh(settings: settings, now: now)
        }
        if changed || dayChanged {
            onStateChange?(newState)
        }
    }
}
```

- [ ] **Step 8: 修改 `PetMood.swift`**

把 `Sources/DakaCore/PetMood.swift` 全文替换为：

```swift
import Foundation

public enum PetMood: String, CaseIterable, Sendable {
    case cheerful       // 上午
    case lunch          // 午间
    case focused        // 下午
    case relaxed        // 傍晚
    case sleepy         // 夜间/深夜
    case punchPending   // 打卡窗口内未完成
    case thirsty        // 该喝水了
    case restless       // 该起身走动了

    public var emoji: String {
        switch self {
        case .cheerful: return "🌞"
        case .lunch: return "😋"
        case .focused: return "💪"
        case .relaxed: return "😌"
        case .sleepy: return "😴"
        case .punchPending: return "😰"
        case .thirsty: return "🥵"
        case .restless: return "😤"
        }
    }

    /// 状态覆盖时间：打卡待办 > 健康（喝水 > 走动）> 时间。
    public static func resolve(reminderState: ReminderState,
                               now: Date,
                               health: HealthStatus? = nil,
                               calendar: Calendar = .current) -> PetMood {
        if !reminderState.isEmpty { return .punchPending }
        if let health {
            if health.waterDue { return .thirsty }
            if health.movementDue { return .restless }
        }
        switch calendar.component(.hour, from: now) {
        case 5..<11: return .cheerful
        case 11..<13: return .lunch
        case 13..<17: return .focused
        case 17..<21: return .relaxed
        default: return .sleepy
        }
    }
}
```

- [ ] **Step 9: 修改 `ReminderController.swift`**

将 `Sources/Daka/ReminderController.swift` 全文替换为（本步先完成「去 gentle」，间隔即时生效在 Task 5 再改）：

```swift
import AppKit
import SwiftUI
import DakaCore

/// 全屏遮罩窗口：置顶、跨所有 Space、拦截 ESC/关闭快捷键。
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           ["q", "w", "m", "h"].contains(chars) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { return } // ESC
        super.keyDown(with: event)
    }

    override func performClose(_ sender: Any?) {}
    override func performMiniaturize(_ sender: Any?) {}
}

@MainActor
final class ReminderController: @preconcurrency ReminderPresenting {
    private let reassertInterval: TimeInterval
    private let overlayModel = OverlayModel()
    private var windows: [OverlayWindow] = []
    private var builtFrames: [CGRect] = []
    private var reassertTimer: Timer?
    private var currentTasks: [PunchTask] = []

    init(interval: TimeInterval, onPunch: @escaping (PunchTask) -> Void) {
        self.reassertInterval = interval
        self.overlayModel.onPunch = onPunch
    }

    func showHard(tasks: [PunchTask], settings: DakaCore.Settings, now: Date) {
        currentTasks = tasks
        overlayModel.tasks = tasks
        overlayModel.settings = settings
        overlayModel.now = now
        rebuildWindowsIfNeeded()
        for w in windows { w.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        stopReassertTimer()
        startReassertTimer()
    }

    func refresh(settings: DakaCore.Settings, now: Date) {
        overlayModel.settings = settings
        overlayModel.now = now
        rebuildWindowsIfNeeded()
    }

    func hide() {
        stopReassertTimer()
        currentTasks = []
        for w in windows { w.orderOut(nil) }
    }

    deinit {
        reassertTimer?.invalidate()
    }

    private func rebuildWindowsIfNeeded() {
        let screens = NSScreen.screens
        let frames = screens.map { $0.frame }
        if frames == builtFrames, windows.count == screens.count { return }
        builtFrames = frames
        for w in windows { w.orderOut(nil) }

        windows = screens.map { screen in
            let window = OverlayWindow(contentRect: screen.frame,
                                       styleMask: .borderless,
                                       backing: .buffered,
                                       defer: false,
                                       screen: screen)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OverlayView(model: overlayModel))
            return window
        }

        if !currentTasks.isEmpty {
            for window in windows { window.makeKeyAndOrderFront(nil) }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func startReassertTimer() {
        guard reassertTimer == nil else { return }
        let t = Timer(timeInterval: reassertInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.currentTasks.isEmpty else { return }
                for w in self.windows { w.makeKeyAndOrderFront(nil) }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        reassertTimer = t
    }

    private func stopReassertTimer() {
        reassertTimer?.invalidate()
        reassertTimer = nil
    }
}
```

- [ ] **Step 10: 修改 `DakaApp.swift` 的菜单栏图标**

将 `Sources/Daka/DakaApp.swift` 的 `iconName` 计算属性替换为：

```swift
    private var iconName: String {
        model.reminderState.isEmpty ? "checkmark.seal" : "exclamationmark.triangle.fill"
    }
```

- [ ] **Step 11: 修改 `MenuBarView.swift` 状态行**

把 `Sources/Daka/MenuBarView.swift` 中 `statusRow` 的这段：

```swift
            } else if model.reminderState.hard.contains(task) {
                Text("已过截止 \(deadline)\(suffix)").foregroundStyle(.red)
            } else if model.reminderState.gentle.contains(task) {
                Text("窗口内 \(start)–\(deadline)\(suffix)").foregroundStyle(.orange)
            } else {
                Text("待打卡 \(start)–\(deadline)\(suffix)").foregroundStyle(.secondary)
            }
```

替换为：

```swift
            } else if model.reminderState.contains(task) {
                if let due = DakaDate.date(on: model.now, at: deadline), model.now >= due {
                    Text("已过截止 \(deadline)\(suffix)").foregroundStyle(.red)
                } else {
                    Text("窗口内 \(start)–\(deadline)\(suffix)").foregroundStyle(.orange)
                }
            } else {
                Text("待打卡 \(start)–\(deadline)\(suffix)").foregroundStyle(.secondary)
            }
```

- [ ] **Step 12: 运行测试，确认通过**

Run: `swift test`
Expected: PASS（`ScheduleEvaluatorTests`、`SchedulerTests`、`PetMoodTests` 及其余全部用例）。

- [ ] **Step 13: 构建**

Run: `make build`
Expected: `Build complete!`。

- [ ] **Step 14: 提交**

```bash
git add Sources/DakaCore/Models.swift Sources/DakaCore/ScheduleEvaluator.swift \
        Sources/DakaCore/Scheduler.swift Sources/DakaCore/PetMood.swift \
        Sources/Daka/ReminderController.swift Sources/Daka/DakaApp.swift \
        Sources/Daka/MenuBarView.swift \
        Tests/DakaCoreTests/ScheduleEvaluatorTests.swift \
        Tests/DakaCoreTests/SchedulerTests.swift \
        Tests/DakaCoreTests/PetMoodTests.swift
git commit -m "feat: replace two-level reminders with window-start full-screen reminders"
```

---

### Task 5: 重复提醒间隔即时生效 + 设置页

**Files:**
- Modify: `Sources/Daka/ReminderController.swift`
- Modify: `Sources/Daka/AppModel.swift`
- Modify: `Sources/Daka/SettingsPages.swift`

- [ ] **Step 1: 让 `reassertInterval` 可变并支持即时更新**

在 `Sources/Daka/ReminderController.swift` 中：

1. 把 `private let reassertInterval: TimeInterval` 改为 `private var reassertInterval: TimeInterval`。
2. 把 `showHard` 方法替换为：

```swift
    func showHard(tasks: [PunchTask], settings: DakaCore.Settings, now: Date) {
        currentTasks = tasks
        overlayModel.tasks = tasks
        overlayModel.settings = settings
        overlayModel.now = now
        reassertInterval = settings.effectiveReminderIntervalSeconds
        rebuildWindowsIfNeeded()
        for w in windows { w.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        stopReassertTimer()
        startReassertTimer()
    }
```

3. 把 `refresh` 方法替换为：

```swift
    func refresh(settings: DakaCore.Settings, now: Date) {
        overlayModel.settings = settings
        overlayModel.now = now
        let desired = settings.effectiveReminderIntervalSeconds
        if desired != reassertInterval {
            reassertInterval = desired
            stopReassertTimer()
            startReassertTimer()
        }
        rebuildWindowsIfNeeded()
    }
```

- [ ] **Step 2: AppModel 新增间隔 setter**

在 `Sources/Daka/AppModel.swift` 的 `setEnabled` / `updateMorningStart` 等 setter 附近（约 266-270 行）插入：

```swift
    func setReminderIntervalMinutes(_ minutes: Int) {
        let clamped = min(60, max(1, minutes))
        updateSettings { $0.reminderIntervalSeconds = TimeInterval(clamped * 60) }
    }
```

- [ ] **Step 3: 设置页新增「重复提醒」**

在 `Sources/Daka/SettingsPages.swift` 的 `ScheduleSettingsView` 中，把「打卡窗口」`Section` 之后追加：

```swift
            Section("重复提醒") {
                Stepper(value: Binding(get: { Int(model.settings.reminderIntervalSeconds / 60) },
                                       set: { model.setReminderIntervalMinutes($0) }),
                        in: 1...60) {
                    Text("每隔 \(Int(model.settings.reminderIntervalSeconds / 60)) 分钟重复提醒")
                }
                Text("进入打卡窗口即全屏提醒，完成对应打卡后停止。窗口截止时间仅用于统计缺卡。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 4: 构建**

Run: `make build`
Expected: `Build complete!`。

- [ ] **Step 5: 运行全部测试**

Run: `swift test`
Expected: PASS。

- [ ] **Step 6: 提交**

```bash
git add Sources/Daka/ReminderController.swift Sources/Daka/AppModel.swift Sources/Daka/SettingsPages.swift
git commit -m "feat: configurable repeat interval for full-screen reminder"
```

---

### Task 6: 更新 README 与手动验证清单

**Files:**
- Modify: `README.md`
- Modify: `docs/verification.md`

- [ ] **Step 1: README 功能特性第一条**

把 `README.md` 第 9 行：

```markdown
- **时间窗口 + 两级提醒**：进入打卡窗口先「温和提醒」（系统通知 + 菜单栏铃铛图标）；到达截止仍未打卡则升级为「强制提醒」（每屏全屏遮罩，每 2 分钟重弹置顶）。
```

替换为：

```markdown
- **时间窗口 + 全屏强提醒**：进入打卡窗口开始时间即弹出全屏遮罩（置顶、拦截退出快捷键），按可配置间隔（默认 2 分钟，1–60 分钟）重复重弹，直到完成对应打卡才停止。
```

- [ ] **Step 2: README 菜单栏图标说明**

把 `README.md` 第 45 行：

```markdown
- 菜单栏图标反映当前状态：`checkmark.seal` 正常 / `bell.badge` 窗口内待打卡 / `exclamationmark.triangle.fill` 已过截止。
```

替换为：

```markdown
- 菜单栏图标两态：`checkmark.seal` 正常 / `exclamationmark.triangle.fill` 有待打卡。
```

- [ ] **Step 3: README 使用说明补充补卡入口**

在 `README.md` 第 43 行（「主窗口左侧为工具列表…」那条）之后新增一条：

```markdown
- 「打卡统计」页顶部为「今日打卡」：可对上班/下班**补卡**（选时间）、**改时间**、**删除**误点记录，仅限今天。
```

- [ ] **Step 4: 重写 verification.md 的提醒章节**

把 `docs/verification.md` 第 10-28 行（「窗口内温和提醒」「过截止强制提醒」「通知权限」三节）整体替换为：

```markdown
## 全屏强提醒（v13）

- [ ] 08:59 → 无提醒；09:00 → 立即全屏遮罩「该上班打卡了」。
- [ ] 全屏遮罩置顶，ESC / Cmd+W / Cmd+M / Cmd+H 无效。
- [ ] 按设定间隔（默认 2 分钟）重复置顶；可在「设置 → 打卡时间 → 重复提醒」改成 1 分钟验证。
- [ ] 点「上班打卡」→ 全屏消失；18:00 到点后下班窗口再按同样规则全屏提醒。
- [ ] 上班、下班都欠账时，全屏同时显示两个按钮，打完一个少一个。
- [ ] 上午 09:00 触发后完成打卡，18:00 前不再有任何打卡提醒。
- [ ] 休假 / 禁用提醒 / 非工作日：到点不弹全屏。
```

- [ ] **Step 5: verification.md 修正三态与等级描述**

把 `docs/verification.md` 中的：

```markdown
- [ ] 状态栏图标三态（勾 / 铃铛 / 三角）仍正确；禁用或休假当天状态显示「今日不提醒」。
```

替换为：

```markdown
- [ ] 状态栏图标两态（勾 / 三角）正确；禁用或休假当天状态显示「今日不提醒」。
```

并把：

```markdown
- [ ] 改系统时间跨越 09:00 / 09:30 / 18:00 / 18:30，提醒等级随之变化。
```

替换为：

```markdown
- [ ] 改系统时间跨越 09:00 / 18:00，待打卡出现或消失（截止时间不再改变提醒级别）。
```

并把 v7 章节中的：

```markdown
- [ ] 打卡全部既有行为无回归（温和/全屏、重复打卡、最少工时、休假、定点启动）。
```

替换为：

```markdown
- [ ] 打卡全部既有行为无回归（全屏强提醒、重复打卡、最少工时、休假、定点启动）。
```

- [ ] **Step 6: verification.md 新增 v12 与 v13 补卡条目**

在 `docs/verification.md` 末尾（健康习惯 v11 章节之后）追加：

```markdown
## v12：今日补卡 / 改时间 / 删除

- [ ] 「打卡统计」页顶部出现「今日打卡」，上班/下班各列出今天已有的打卡时间。
- [ ] 点「补卡」弹时间选择器（默认当前时间），保存后该条出现在列表，统计同步刷新。
- [ ] 点「改时间」默认显示该条原时间，保存后时间更新；上班取最早、下班取最晚规则仍成立。
- [ ] 点「删除」弹确认框，确认后该条消失；删掉当天唯一上班卡后重新变为待打卡并再次弹出强提醒。
- [ ] 补卡/改时间/删除仅影响今天，历史日期不受影响。

## v13：单一强提醒 + 可配置间隔

- [ ] 「设置 → 打卡时间 → 重复提醒」可改 1–60 分钟；改后正在显示的全屏遮罩按新间隔重弹。
- [ ] 菜单栏图标只有两态（勾 / 三角），不再出现铃铛。
- [ ] 桌宠待打卡表情统一为 😰（不再区分窗口内/过截止）。
- [ ] 打卡提醒不再发送「窗口内」系统通知；喝水/走动的系统通知仍正常。
```

- [ ] **Step 7: 提交**

```bash
git add README.md docs/verification.md
git commit -m "docs: update reminder docs for make-up punch and hard-only reminders"
```

---

## 完成后

- 运行完整测试：`swift test` → 全部 PASS。
- 构建安装：`make install`（需 `Resources/Daka.icns` 已存在）。
- 按 `docs/verification.md` 的 v12 / v13 清单手动过一遍。
