# Daka 排期 v2（窗口 + 两级提醒 + 定点启动）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 Daka 从「到点即全屏」改为「窗口内温和、过截止全屏」的两级提醒，并新增定点启动（09:00/09:30/18:00/18:30 拉起）与单实例保护。

**Architecture:** 核心逻辑（`Settings` 四时间 + `ScheduleEvaluator` 返回 `PendingReminder` 等级 + `Scheduler` 按 hard/gentle 优先级驱动展示）保持在可测试的 `DakaCore`；应用层新增温和通知通道、菜单栏三态、`ScheduledLaunchManager`（写 LaunchAgent + launchctl）与单实例保护。`LaunchAgentPlist` 的 plist 生成放在 `DakaCore` 以便单测。

**Tech Stack:** Swift 5.10 language mode、SwiftUI、AppKit、SwiftPM、XCTest、UserNotifications、ServiceManagement、launchd。

**Spec:** `docs/superpowers/specs/2026-09-15-daka-schedule-v2-design.md`

---

## 文件结构（变更）

```
Sources/DakaCore/
├── Models.swift              # 改：ReminderLevel/PendingReminder/ReminderState；Settings 四时间 + 兼容解码
├── ScheduleEvaluator.swift   # 改：pendingReminders 返回两级
├── Scheduler.swift           # 改：ReminderState + 协议 showHard/showGentle/refresh/hide；删除 launchForced
├── LaunchAgentPlist.swift    # 新增：生成 launchd plist 字符串（纯函数）
└── (DakaClock/DakaDate/PunchStore 不变)

Sources/Daka/
├── ReminderController.swift  # 改：showHard（原全屏）/showGentle（通知+菜单）/refresh/hide
├── AppModel.swift            # 改：reminderState、4 时间、接入 ScheduledLaunchManager
├── MenuBarView.swift         # 改：4 个时间选择器、等级显示、定点启动状态
├── AppDelegate.swift         # 改：单实例保护；仅 hard 时拦截退出
├── DakaApp.swift             # 改：菜单栏图标三态
├── ScheduledLaunchManager.swift  # 新增：写 ~/Library/LaunchAgents + launchctl bootstrap
├── LoginItemManager.swift    # 不变
├── OverlayView.swift         # 微调：OverlayModel.settings 类型
└── (Info.plist/Makefile 不变)

Tests/DakaCoreTests/
├── ScheduleEvaluatorTests.swift  # 重写（两级边界）
├── SchedulerTests.swift          # 重写（ReminderState/等级）
├── SettingsTests.swift           # 新增（兼容解码 + 往返）
└── LaunchAgentPlistTests.swift   # 新增
```

---

## Task 1: `LaunchAgentPlist`（纯逻辑，独立）

**Files:**
- Create: `Sources/DakaCore/LaunchAgentPlist.swift`
- Create: `Tests/DakaCoreTests/LaunchAgentPlistTests.swift`

- [ ] **Step 1: 写失败测试 `Tests/DakaCoreTests/LaunchAgentPlistTests.swift`**

```swift
import XCTest
@testable import DakaCore

final class LaunchAgentPlistTests: XCTestCase {
    private let settings = Settings(
        morningWindowStart: "09:00", morningDeadline: "09:30",
        eveningWindowStart: "18:00", eveningDeadline: "18:30")

    func testContainsLabelAndOpenInvocation() {
        let plist = LaunchAgentPlist.make(settings: settings, bundleID: "com.xue.daka")
        XCTAssertTrue(plist.contains("<string>com.xue.daka.schedule</string>"))
        XCTAssertTrue(plist.contains("/usr/bin/open"))
        XCTAssertTrue(plist.contains("<string>-b</string>"))
        XCTAssertTrue(plist.contains("<string>com.xue.daka</string>"))
    }

    func testContainsFourCalendarTimes() {
        let plist = LaunchAgentPlist.make(settings: settings, bundleID: "com.xue.daka")
        let hours = timePairs(in: plist)
        XCTAssertEqual(hours.count, 4)
        XCTAssertTrue(hours.contains { $0 == (9, 0) })
        XCTAssertTrue(hours.contains { $0 == (9, 30) })
        XCTAssertTrue(hours.contains { $0 == (18, 0) })
        XCTAssertTrue(hours.contains { $0 == (18, 30) })
    }

    func testDoesNotRunAtLoad() {
        let plist = LaunchAgentPlist.make(settings: settings, bundleID: "com.xue.daka")
        XCTAssertFalse(plist.contains("RunAtLoad"))
    }

    func testInvalidTimeStringsAreSkipped() {
        let bad = Settings(morningWindowStart: "oops", morningDeadline: "09:30",
                           eveningWindowStart: "18:00", eveningDeadline: "18:30")
        let plist = LaunchAgentPlist.make(settings: bad, bundleID: "com.xue.daka")
        XCTAssertEqual(timePairs(in: plist).count, 3)
    }

    /// 从 plist 文本里提取所有 (Hour, Minute) 对，按出现顺序。
    private func timePairs(in plist: String) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        let lines = plist.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var i = 0
        while i < lines.count {
            if lines[i].contains("<key>Hour</key>"),
               i + 2 < lines.count, lines[i + 1].contains("<integer>"),
               lines[i + 2].contains("<key>Minute</key>"),
               i + 3 < lines.count, lines[i + 3].contains("<integer>") {
                let hour = Int(lines[i + 1].replacingOccurrences(of: "<integer>", with: "")
                    .replacingOccurrences(of: "</integer>", with: "")) ?? -1
                let minute = Int(lines[i + 3].replacingOccurrences(of: "<integer>", with: "")
                    .replacingOccurrences(of: "</integer>", with: "")) ?? -1
                result.append((hour, minute))
                i += 4
                continue
            }
            i += 1
        }
        return result
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

Run: `swift test --filter LaunchAgentPlistTests`
Expected: 编译失败，`cannot find 'LaunchAgentPlist' in scope`。

- [ ] **Step 3: 实现 `Sources/DakaCore/LaunchAgentPlist.swift`**

```swift
import Foundation

/// 生成定点启动用的 launchd LaunchAgent plist 文本。
public enum LaunchAgentPlist {
    public static let label = "com.xue.daka.schedule"

    public static func make(settings: Settings, bundleID: String) -> String {
        let times: [(hour: Int, minute: Int)] = [
            settings.morningWindowStart,
            settings.morningDeadline,
            settings.eveningWindowStart,
            settings.eveningDeadline
        ].compactMap { DakaDate.timeComponents($0).map { (hour: $0.hour, minute: $0.minute) } }

        var intervals = ""
        for time in times {
            intervals += "        <dict>\n"
            intervals += "            <key>Hour</key>\n"
            intervals += "            <integer>\(time.hour)</integer>\n"
            intervals += "            <key>Minute</key>\n"
            intervals += "            <integer>\(time.minute)</integer>\n"
            intervals += "        </dict>\n"
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/open</string>
                <string>-b</string>
                <string>\(bundleID)</string>
            </array>
            <key>StartCalendarInterval</key>
            <array>
        \(intervals)    </array>
        </dict>
        </plist>
        """
    }
}
```

> 注意：`timePairs` 依赖 `<key>Hour</key>` 后紧跟 `<integer>`、再 `<key>Minute</key>`、再 `<integer>` 的四行结构；上面的缩进必须保持每行一个标签。

- [ ] **Step 4: 运行测试确认通过**

Run: `swift test --filter LaunchAgentPlistTests`
Expected: 全部 PASS（4 个测试）。

- [ ] **Step 5: 提交**

```bash
git add Sources/DakaCore/LaunchAgentPlist.swift Tests/DakaCoreTests/LaunchAgentPlistTests.swift
git commit -m "feat: add LaunchAgentPlist generator for scheduled launch"
```

---

## Task 2: 核心排期 v2 + 应用编译适配

**Files:**
- Modify: `Sources/DakaCore/Models.swift`
- Modify: `Sources/DakaCore/ScheduleEvaluator.swift`
- Modify: `Sources/DakaCore/Scheduler.swift`
- Modify: `Sources/Daka/ReminderController.swift`, `Sources/Daka/OverlayView.swift`, `Sources/Daka/AppModel.swift`, `Sources/Daka/MenuBarView.swift`, `Sources/Daka/AppDelegate.swift`, `Sources/Daka/DakaApp.swift`（最小适配，保证编译）
- Rewrite: `Tests/DakaCoreTests/ScheduleEvaluatorTests.swift`, `Tests/DakaCoreTests/SchedulerTests.swift`
- Create: `Tests/DakaCoreTests/SettingsTests.swift`

> 该任务较大但内聚：删除 `launchForced` 机制，引入两级等级，并把所有引用新 API 的地方一次性改到能编译、能过测。应用层行为增强在 Task 3。

- [ ] **Step 1: 修改 `Models.swift`——新增等级类型、`Settings` 四时间与兼容解码**

在 `PunchTask` 之后加入：

```swift
public enum ReminderLevel: String, Codable, Equatable, Sendable {
    case gentle
    case hard
}

public struct PendingReminder: Equatable, Sendable {
    public let task: PunchTask
    public let level: ReminderLevel

    public init(task: PunchTask, level: ReminderLevel) {
        self.task = task
        self.level = level
    }
}

public struct ReminderState: Equatable, Sendable {
    public var gentle: [PunchTask]
    public var hard: [PunchTask]

    public init(gentle: [PunchTask] = [], hard: [PunchTask] = []) {
        self.gentle = gentle
        self.hard = hard
    }

    public var isEmpty: Bool { gentle.isEmpty && hard.isEmpty }
}
```

把整个 `Settings` 结构体替换为：

```swift
public struct Settings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var workdays: Set<Int>          // Sun=1 ... Sat=7，默认 Mon..Fri
    public var morningWindowStart: String  // "HH:mm"
    public var morningDeadline: String
    public var eveningWindowStart: String
    public var eveningDeadline: String
    public var reminderIntervalSeconds: TimeInterval

    public init(enabled: Bool = true,
                workdays: Set<Int> = [2, 3, 4, 5, 6],
                morningWindowStart: String = "09:00",
                morningDeadline: String = "09:30",
                eveningWindowStart: String = "18:00",
                eveningDeadline: String = "18:30",
                reminderIntervalSeconds: TimeInterval = 120) {
        self.enabled = enabled
        self.workdays = workdays
        self.morningWindowStart = morningWindowStart
        self.morningDeadline = morningDeadline
        self.eveningWindowStart = eveningWindowStart
        self.eveningDeadline = eveningDeadline
        self.reminderIntervalSeconds = reminderIntervalSeconds
    }

    public static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case enabled, workdays
        case morningWindowStart, morningDeadline
        case eveningWindowStart, eveningDeadline
        case reminderIntervalSeconds
    }

    /// 逐字段 decodeIfPresent，旧版本 data.json（含 morningTime/eveningTime 等旧键）可平滑升级为新默认值。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        self.workdays = try c.decodeIfPresent(Set<Int>.self, forKey: .workdays) ?? d.workdays
        self.morningWindowStart = try c.decodeIfPresent(String.self, forKey: .morningWindowStart) ?? d.morningWindowStart
        self.morningDeadline = try c.decodeIfPresent(String.self, forKey: .morningDeadline) ?? d.morningDeadline
        self.eveningWindowStart = try c.decodeIfPresent(String.self, forKey: .eveningWindowStart) ?? d.eveningWindowStart
        self.eveningDeadline = try c.decodeIfPresent(String.self, forKey: .eveningDeadline) ?? d.eveningDeadline
        self.reminderIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .reminderIntervalSeconds) ?? d.reminderIntervalSeconds
    }
}
```

`DayRecord` 与 `DakaData` 保持不变。

- [ ] **Step 2: 替换 `Sources/DakaCore/ScheduleEvaluator.swift`**

```swift
import Foundation

public struct ScheduleEvaluator {
    public init() {}

    /// 返回当前应提醒的项及其等级：窗口内为 .gentle，过截止为 .hard。
    public func pendingReminders(now: Date,
                                 settings: Settings,
                                 record: DayRecord,
                                 calendar: Calendar = .current) -> [PendingReminder] {
        guard settings.enabled, !record.skipped else { return [] }
        guard settings.workdays.contains(DakaDate.weekday(of: now, calendar: calendar)) else { return [] }

        var reminders: [PendingReminder] = []

        if let level = level(now: now,
                             start: settings.morningWindowStart,
                             deadline: settings.morningDeadline,
                             done: record.morningDone,
                             calendar: calendar) {
            reminders.append(PendingReminder(task: .morning, level: level))
        }
        if let level = level(now: now,
                             start: settings.eveningWindowStart,
                             deadline: settings.eveningDeadline,
                             done: record.eveningDone,
                             calendar: calendar) {
            reminders.append(PendingReminder(task: .evening, level: level))
        }
        return reminders
    }

    private func level(now: Date,
                       start: String,
                       deadline: String,
                       done: Bool,
                       calendar: Calendar) -> ReminderLevel? {
        guard !done else { return nil }
        if let deadlineDate = DakaDate.date(on: now, at: deadline, calendar: calendar), now >= deadlineDate {
            return .hard
        }
        if let startDate = DakaDate.date(on: now, at: start, calendar: calendar), now >= startDate {
            return .gentle
        }
        return nil
    }
}
```

- [ ] **Step 3: 替换 `Sources/DakaCore/Scheduler.swift`**

```swift
import Foundation

/// UI 侧实现：强制（全屏）/温和（菜单栏+通知）/刷新/隐藏。
public protocol ReminderPresenting: AnyObject {
    func showHard(tasks: [PunchTask], settings: Settings, now: Date)
    func showGentle(tasks: [PunchTask], settings: Settings, now: Date)
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
        let reminders = evaluator.pendingReminders(now: now, settings: settings, record: record,
                                                   calendar: calendar)

        var newState = ReminderState()
        for reminder in reminders {
            switch reminder.level {
            case .hard: newState.hard.append(reminder.task)
            case .gentle: newState.gentle.append(reminder.task)
            }
        }
        apply(state: newState, settings: settings, now: now, dayChanged: dayChanged)
    }

    private func apply(state newState: ReminderState, settings: Settings, now: Date, dayChanged: Bool) {
        state = newState
        let changed = newState != lastState
        if changed {
            lastState = newState
            if !newState.hard.isEmpty {
                presenter?.showHard(tasks: newState.hard, settings: settings, now: now)
            } else if !newState.gentle.isEmpty {
                presenter?.showGentle(tasks: newState.gentle, settings: settings, now: now)
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

- [ ] **Step 4: 重写 `Tests/DakaCoreTests/ScheduleEvaluatorTests.swift`**

```swift
import XCTest
@testable import DakaCore

final class ScheduleEvaluatorTests: XCTestCase {
    private let evaluator = ScheduleEvaluator()
    private let cal = TestTime.calendar

    private func reminders(_ date: Date,
                           settings: Settings = .default,
                           record: DayRecord = DayRecord()) -> [PendingReminder] {
        evaluator.pendingReminders(now: date, settings: settings, record: record, calendar: cal)
    }

    func testBeforeMorningWindowHasNoReminders() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 8, 59)), [])
    }

    func testAtMorningWindowStartIsGentle() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 0)),
                       [PendingReminder(task: .morning, level: .gentle)])
    }

    func testWithinMorningWindowIsGentle() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 29)),
                       [PendingReminder(task: .morning, level: .gentle)])
    }

    func testAtMorningDeadlineIsHard() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 30)),
                       [PendingReminder(task: .morning, level: .hard)])
    }

    func testAfterMorningDeadlineIsHard() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 31)),
                       [PendingReminder(task: .morning, level: .hard)])
    }

    func testBeforeEveningWindowOnlyMorningRelevant() {
        // 17:59，上班未做 -> morning hard；下班未做 -> 无
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 17, 59)),
                       [PendingReminder(task: .morning, level: .hard)])
    }

    func testAtEveningWindowStartMorningHardEveningGentle() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 0)),
                       [PendingReminder(task: .morning, level: .hard),
                        PendingReminder(task: .evening, level: .gentle)])
    }

    func testAtEveningDeadlineBothHard() {
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 30)),
                       [PendingReminder(task: .morning, level: .hard),
                        PendingReminder(task: .evening, level: .hard)])
    }

    func testMorningDoneOnlyEvening() {
        var record = DayRecord()
        record.morningDone = true
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 10), record: record),
                       [PendingReminder(task: .evening, level: .gentle)])
    }

    func testBothDoneNoReminders() {
        var record = DayRecord()
        record.morningDone = true
        record.eveningDone = true
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 23, 0), record: record), [])
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
        var record = DayRecord()
        record.skipped = true
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), record: record), [])
    }
}
```

- [ ] **Step 5: 重写 `Tests/DakaCoreTests/SchedulerTests.swift`**

```swift
import XCTest
@testable import DakaCore

final class SpyPresenter: ReminderPresenting {
    var lastHard: [PunchTask]?
    var lastGentle: [PunchTask]?
    var hideCount = 0
    var refreshCount = 0

    func showHard(tasks: [PunchTask], settings: Settings, now: Date) { lastHard = tasks; lastGentle = nil }
    func showGentle(tasks: [PunchTask], settings: Settings, now: Date) { lastGentle = tasks; lastHard = nil }
    func refresh(settings: Settings, now: Date) { refreshCount += 1 }
    func hide() { lastHard = nil; lastGentle = nil; hideCount += 1 }
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
        XCTAssertNil(presenter.lastGentle)
        XCTAssertEqual(presenter.hideCount, 1)
    }

    func testWindowStartShowsGentle() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
        scheduler.tick()
        XCTAssertEqual(presenter.lastGentle, [.morning])
        XCTAssertNil(presenter.lastHard)
    }

    func testDeadlineShowsHard() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 30))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])
        XCTAssertNil(presenter.lastGentle)
    }

    func testGentleToHardTransitionOnTicks() {
        let (scheduler, clock, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 29))
        scheduler.tick()
        XCTAssertEqual(presenter.lastGentle, [.morning])

        clock.now = TestTime.date(2026, 9, 14, 9, 30)
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])
        XCTAssertNil(presenter.lastGentle)
    }

    func testHardTakesPriorityOverGentle() {
        // 18:10 上班未做(hard) + 下班未做(gentle) -> 只展示 hard
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 18, 10))
        scheduler.tick()
        XCTAssertEqual(presenter.lastHard, [.morning])
        XCTAssertNil(presenter.lastGentle)
    }

    func testHidesAfterPunch() throws {
        let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 35))
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
        XCTAssertEqual(observed, [ReminderState(gentle: [.morning], hard: [])])
        XCTAssertEqual(scheduler.state, ReminderState(gentle: [.morning], hard: []))
    }

    func testDayRolloverFiresCallback() {
        let (scheduler, clock, _, _) = makeScheduler(now: TestTime.date(2026, 9, 14, 8, 0))
        var observed: [ReminderState] = []
        scheduler.onStateChange = { observed.append($0) }
        scheduler.tick()
        clock.now = TestTime.date(2026, 9, 15, 8, 0)
        scheduler.tick()
        XCTAssertEqual(observed.count, 2)
    }

    func testWeekendNeverShows() {
        let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 19, 10, 0))
        scheduler.tick()
        XCTAssertNil(presenter.lastHard)
        XCTAssertNil(presenter.lastGentle)
    }
}
```

- [ ] **Step 6: 新建 `Tests/DakaCoreTests/SettingsTests.swift`**

```swift
import XCTest
@testable import DakaCore

final class SettingsTests: XCTestCase {
    func testDefaults() {
        let s = Settings.default
        XCTAssertEqual(s.morningWindowStart, "09:00")
        XCTAssertEqual(s.morningDeadline, "09:30")
        XCTAssertEqual(s.eveningWindowStart, "18:00")
        XCTAssertEqual(s.eveningDeadline, "18:30")
        XCTAssertEqual(s.reminderIntervalSeconds, 120)
    }

    func testRoundTrip() throws {
        var s = Settings.default
        s.morningDeadline = "09:45"
        s.enabled = false
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testLegacyJSONUpgradesToDefaults() throws {
        // 旧版 Settings 的 JSON（含 morningTime/eveningTime/launchPromptEarliest）。
        let legacy = """
        {
          "enabled": true,
          "workdays": [2,3,4,5,6],
          "morningTime": "07:00",
          "eveningTime": "17:00",
          "launchPromptEarliest": "06:00",
          "reminderIntervalSeconds": 60
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: legacy)
        XCTAssertEqual(decoded.morningWindowStart, "09:00")
        XCTAssertEqual(decoded.morningDeadline, "09:30")
        XCTAssertEqual(decoded.eveningWindowStart, "18:00")
        XCTAssertEqual(decoded.eveningDeadline, "18:30")
        XCTAssertEqual(decoded.reminderIntervalSeconds, 60) // 已有字段保留
    }

    func testPartialJSONUsesDefaultsForMissing() throws {
        let partial = #"{"enabled": false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: partial)
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.morningWindowStart, "09:00")
    }
}
```

- [ ] **Step 7: 最小适配应用层（保证编译；行为增强在 Task 3）**

`Sources/Daka/ReminderController.swift`：把 `ReminderController` 的 `show`/`refresh` 改为新协议（`Settings` 用 `DakaCore.Settings` 限定）：
- `func showHard(tasks: [PunchTask], settings: DakaCore.Settings, now: Date)` —— 方法体沿用原 `show`（全屏）。
- `func showGentle(tasks: [PunchTask], settings: DakaCore.Settings, now: Date)` —— 暂时 `overlayModel.settings = settings`（Task 3 加通知）。
- `func refresh(settings: DakaCore.Settings, now: Date)` —— 原 `refresh` 基础上赋 `settings`。

`Sources/Daka/OverlayView.swift`：`OverlayModel.settings` 类型保持 `DakaCore.Settings`。

`Sources/Daka/AppModel.swift`：
- 用 `@Published private(set) var reminderState = ReminderState()` 取代 `hasPendingTasks`。
- `var hasPendingTasks: Bool { !reminderState.isEmpty }`、`var hasHardTasks: Bool { !reminderState.hard.isEmpty }`。
- `start()` 去掉 `launchForced: true`。
- `onStateChange = { [weak self] state in guard let self else { return }; self.reminderState = state; self.refreshRecord() }`。
- 设置写入方法改为 `updateMorningStart/updateMorningDeadline/updateEveningStart/updateEveningDeadline`。
- 其余（`punch`/`setSkipped`/时钟调试/`quit`）不变。

`Sources/Daka/MenuBarView.swift`：
- 4 个 `DatePicker` 绑定到新字段（用 `DakaDate.timeComponents`/格式化 helper 转换 `HH:mm`）。
- `statusRow` 的 `due` 说明改为「窗口 start–deadline」。
- 其余暂时保留。

`Sources/Daka/AppDelegate.swift`：退出拦截改为
```swift
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let hard = MainActor.assumeIsolated { AppModel.shared.hasHardTasks }
        return hard ? .terminateCancel : .terminateNow
    }
```

`Sources/Daka/DakaApp.swift`：图标暂用 `model.hasPendingTasks`（三态在 Task 3）。

- [ ] **Step 8: 构建与全量测试**

Run: `swift build && swift test`
Expected: 构建成功；测试全绿（Task 1 的 4 个 + ScheduleEvaluator 13 + Scheduler 10 + Settings 4 + DakaDate 6 + PunchStore 11 = 48）。

- [ ] **Step 9: 提交**

```bash
git add Sources/DakaCore/Models.swift Sources/DakaCore/ScheduleEvaluator.swift Sources/DakaCore/Scheduler.swift Tests/DakaCoreTests Sources/Daka
git commit -m "refactor: two-level reminder windows in core with app adaptation"
```

---

## Task 3: 应用层两级提醒（温和通知 + 菜单三态 + 4 时间设置）

**Files:**
- Modify: `Sources/Daka/ReminderController.swift`
- Create: `Sources/Daka/GentleNotifier.swift`
- Modify: `Sources/Daka/MenuBarView.swift`
- Modify: `Sources/Daka/AppModel.swift`
- Modify: `Sources/Daka/DakaApp.swift`

- [ ] **Step 1: 新建 `Sources/Daka/GentleNotifier.swift`**

```swift
import Foundation
import UserNotifications

/// 温和提醒通道：本地通知。首次使用时请求授权；未授权则静默（菜单栏仍会警示）。
final class GentleNotifier {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorizationIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(tasks: [PunchTask]) {
        guard let task = tasks.first else { return }
        let content = UNMutableNotificationContent()
        content.title = "打卡提醒"
        content.body = tasks.count > 1
            ? "\(tasks.map(\.title).joined(separator: "、")) 都还没完成，别忘了打卡。"
            : "\(task.title)：还在打卡窗口内，记得完成。"
        content.sound = .default
        let request = UNNotificationRequest(identifier: "daka.gentle",
                                            content: content,
                                            trigger: nil)
        center.add(request)
    }
}
```

> 需要 `import DakaCore` 才能用 `PunchTask`；在该文件顶部补上 `import DakaCore`。

- [ ] **Step 2: 在 `ReminderController` 接入温和通道与节流**

在 `ReminderController` 中：
- 新增 `private let notifier = GentleNotifier()`、`private var currentLevel: ReminderLevel?`、`private var gentleTasks: [PunchTask] = []`、`private var lastNotifyAt: Date?`。
  - 注意：`currentTasks` 只表示**全屏**正在展示的任务；温和态的待办放在 `gentleTasks`，否则 `rebuildWindowsIfNeeded()` 会因为 `currentTasks` 非空而在温和态误把全屏窗口置前。
- `init` 里调用 `notifier.requestAuthorizationIfNeeded()`。
- 实现：

```swift
    func showGentle(tasks: [PunchTask], settings: DakaCore.Settings, now: Date) {
        currentLevel = .gentle
        gentleTasks = tasks
        currentTasks = []
        overlayModel.tasks = tasks
        overlayModel.settings = settings
        overlayModel.now = now
        stopReassertTimer()
        hideOverlayWindows()
        notifier.notify(tasks: tasks)
        lastNotifyAt = now
    }

    func showHard(tasks: [PunchTask], settings: DakaCore.Settings, now: Date) {
        currentLevel = .hard
        gentleTasks = []
        currentTasks = tasks
        overlayModel.tasks = tasks
        overlayModel.settings = settings
        overlayModel.now = now
        rebuildWindowsIfNeeded()
        for w in windows { w.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        startReassertTimer()
    }

    func refresh(settings: DakaCore.Settings, now: Date) {
        overlayModel.settings = settings
        overlayModel.now = now
        switch currentLevel {
        case .hard:
            rebuildWindowsIfNeeded()
        case .gentle:
            if let last = lastNotifyAt, now.timeIntervalSince(last) >= settings.reminderIntervalSeconds {
                notifier.notify(tasks: gentleTasks)
                lastNotifyAt = now
            }
        case .none:
            break
        }
    }

    func hide() {
        stopReassertTimer()
        currentLevel = nil
        gentleTasks = []
        currentTasks = []
        lastNotifyAt = nil
        hideOverlayWindows()
    }

    private func hideOverlayWindows() {
        for w in windows { w.orderOut(nil) }
    }
```

（原 `show`/`hide` 的窗口部分合并进上面。）

- [ ] **Step 3: `DakaApp` 菜单栏图标三态**

```swift
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Image(systemName: iconName)
        }
        .menuBarExtraStyle(.window)
```

并加：

```swift
    private var iconName: String {
        if !model.reminderState.hard.isEmpty { return "exclamationmark.triangle.fill" }
        if !model.reminderState.gentle.isEmpty { return "bell.badge" }
        return "checkmark.seal"
    }
```

- [ ] **Step 4: `MenuBarView` 展示等级与 4 个时间**

- 顶部状态行标注：上班「09:00–09:30」、下班「18:00–18:30」（取 `model.settings` 字段）；未完成且在 hard 时标红、gentle 时标橙、窗口外/今日不提醒标灰。
- 4 个 `DatePicker`：上班窗口开始、上班截止、下班窗口开始、下班截止。
- 手动打卡按钮、「今天不打卡」、自启状态、调试按钮保持。

- [ ] **Step 5: 构建与全量测试**

Run: `swift build && swift test`
Expected: 构建成功，测试全绿（48）。

- [ ] **Step 6: 提交**

```bash
git add Sources/Daka
git commit -m "feat: gentle notification channel and three-state menu bar"
```

---

## Task 4: 定点启动 + 单实例保护

**Files:**
- Create: `Sources/Daka/ScheduledLaunchManager.swift`
- Modify: `Sources/Daka/AppModel.swift`
- Modify: `Sources/Daka/MenuBarView.swift`
- Modify: `Sources/Daka/AppDelegate.swift`

- [ ] **Step 1: 新建 `Sources/Daka/ScheduledLaunchManager.swift`**

```swift
import Foundation
import DakaCore

/// 管理 ~/Library/LaunchAgents/com.xue.daka.schedule.plist：到窗口时间用 `open -b` 拉起应用。
enum ScheduledLaunchManager {
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(LaunchAgentPlist.label).plist")
    }

    @discardableResult
    static func install(settings: DakaCore.Settings) -> String? {
        guard Bundle.main.bundlePath.hasSuffix(".app") else { return nil }
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }

        let plist = LaunchAgentPlist.make(settings: settings, bundleID: bundleID)
        do {
            try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try plist.write(to: plistURL, atomically: true, encoding: .utf8)
        } catch {
            return "定点启动写入失败：\(error.localizedDescription)"
        }

        let uid = getuid()
        runLaunchctl(["bootout", "gui/\(uid)/\(LaunchAgentPlist.label)"])
        let bootstrap = runLaunchctl(["bootstrap", "gui/\(uid)", plistURL.path])
        if bootstrap != 0 {
            return "定点启动加载失败（launchctl bootstrap 退出码 \(bootstrap)）"
        }
        return nil
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    @discardableResult
    private static func runLaunchctl(_ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}
```

- [ ] **Step 2: `AppModel` 接入定点启动**

- `start()` 中，在创建 `Scheduler` 后调用：
```swift
        scheduledLaunchWarning = ScheduledLaunchManager.install(settings: store.data.settings)
```
（新增 `@Published var scheduledLaunchWarning: String?`。）
- `updateSettings(...)` 成功后，重新安装：
```swift
        scheduledLaunchWarning = ScheduledLaunchManager.install(settings: store.data.settings)
```

- [ ] **Step 3: `MenuBarView` 增加「定点启动」状态行**

在自启状态行下方加一行：`ScheduledLaunchManager.isInstalled ? "定点启动已启用" : "定点启动未启用"`，并显示 `model.scheduledLaunchWarning`（若存在）。

- [ ] **Step 4: `AppDelegate` 单实例保护**

在 `applicationWillFinishLaunching` 中：

```swift
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [])
            exit(0)
        }
    }
```

- [ ] **Step 5: 构建 + 手动验证 launchctl（不启动应用）**

Run: `swift build && swift test`（期望 48 全绿）。
然后 dry-run 校验 plist 生成（不实际加载）：运行一个临时 swift 片段或直接 `make app` 后检查逻辑；`launchctl` 的真实加载在 Task 5 手动验证中进行（注意：加载后到点会真的拉起应用）。

- [ ] **Step 6: 提交**

```bash
git add Sources/Daka
git commit -m "feat: scheduled launch agent and single-instance guard"
```

---

## Task 5: 文档更新与端到端验证

**Files:**
- Modify: `docs/verification.md`
- Modify: `docs/superpowers/specs/2026-09-14-mac-daka-design.md`（标注被 v2 取代）

- [ ] **Step 1: 重写 `docs/verification.md`** 覆盖新规则：
  - 08:59 无提示；09:00 菜单栏橙色 + 通知（温和）；09:30 变红色全屏；打卡后消失。
  - 18:00 下班温和；18:30 全屏；两项都欠时全屏显示两个按钮。
  - 窗口内可正常退出；到 hard 阶段退出被拦截。
  - 长按/休眠唤醒后等级正确；改系统时间跨越 09:00/09:30/18:00/18:30 等级随之变化。
  - 通知权限允许/拒绝两种表现（拒绝时仅菜单栏）。
  - 定点启动：`launchctl print gui/$(id -u)/com.xue.daka.schedule` 能看到四个时间；到点会拉起应用。
  - 单实例：再次启动不会出现第二个菜单栏图标。
  - `~/Library/LaunchAgents/com.xue.daka.schedule.plist` 内容正确。

- [ ] **Step 2: 在旧 spec 顶部加一行**：`> 注意：打卡时间与提醒规则已被 2026-09-15-daka-schedule-v2-design.md 取代。`

- [ ] **Step 3: `make install` 并手动逐项验证。**

- [ ] **Step 4: 提交**

```bash
git add docs
git commit -m "docs: update verification for schedule v2"
```

---

## 完成标准

- `swift test` 全绿（≥48）。
- `make app` / `make install` 成功。
- 窗口内温和（菜单栏 + 通知）、过截止全屏、每 2 分钟重弹。
- 定点启动 LaunchAgent 已安装且含 09:00/09:30/18:00/18:30。
- 单实例；仅 hard 阶段拦截退出。
- `docs/verification.md` 条目通过。
