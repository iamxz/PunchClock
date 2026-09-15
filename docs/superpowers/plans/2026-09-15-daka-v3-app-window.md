# Daka v3（应用主窗口 + 统计 + 精简状态栏）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把应用改为「Dock 图标 + 主窗口（统计 / 设置）」的常规应用，状态栏精简为「今日状态 + 打卡按钮 + 打开主界面」。

**Architecture:** 统计计算作为纯函数放进 `DakaCore`（可测）；应用层新增自管理的 `MainWindowController`（hosting `MainWindowView`，关闭即隐藏）与 `StatisticsView`/`SettingsView`；`MenuBarView` 精简；`DakaApp` 保留 `MenuBarExtra`；`AppDelegate` 负责常规激活策略、窗口生命周期与后台启动抑制。

**Tech Stack:** Swift 5.10、SwiftUI、AppKit、Swift Charts、SwiftPM、XCTest。

**Spec:** `docs/superpowers/specs/2026-09-15-daka-app-window-stats-design.md`

---

## 文件结构（变更）

```
Sources/DakaCore/
├── Statistics.swift        # 新增：DailyStat / StatisticsSummary / Statistics.compute
└── LaunchAgentPlist.swift  # 改：ProgramArguments 增加 --args --background

Sources/Daka/
├── MainWindowController.swift  # 新增：自管理主窗口（关闭隐藏）
├── MainWindowView.swift        # 新增：TabView（统计 / 设置）
├── StatisticsView.swift        # 新增：指标卡 + Charts 柱状图 + 范围切换
├── SettingsView.swift          # 新增：设置页（从 MenuBarView 迁入）
├── MenuBarView.swift           # 改：精简为 状态 + 打卡 + 打开 + 退出
├── AppModel.swift              # 改：openMainWindow / statistics / setWorkdays / mainWindow
├── AppDelegate.swift           # 改：.regular、窗口生命周期、reopen、后台启动抑制
└── DakaApp.swift               # 改：保留 MenuBarExtra（主窗口由 controller 管理）

Resources/Info.plist            # 改：移除 LSUIElement（改为常规应用）

Tests/DakaCoreTests/
├── StatisticsTests.swift       # 新增
└── LaunchAgentPlistTests.swift # 改：断言 --background
```

---

## Task 1: `Statistics`（纯函数，独立）

**Files:**
- Create: `Sources/DakaCore/Statistics.swift`
- Create: `Tests/DakaCoreTests/StatisticsTests.swift`

- [ ] **Step 1: 写失败测试 `Tests/DakaCoreTests/StatisticsTests.swift`**

```swift
import XCTest
@testable import DakaCore

final class StatisticsTests: XCTestCase {
    private let cal = TestTime.calendar
    // 2026-09-14 周一 ... 09-18 周五；09-12/13 周末
    private var now: Date { TestTime.date(2026, 9, 16, 10, 0) } // 周三

    private func records(_ items: [(Date, Bool, Bool, Date?, Date?, Bool)]) -> [String: DayRecord] {
        var result: [String: DayRecord] = [:]
        for (day, morning, evening, mat, eat, skipped) in items {
            let key = DakaDate.key(for: day, calendar: cal)
            var r = DayRecord()
            r.morningDone = morning
            r.eveningDone = evening
            r.morningDoneAt = mat
            r.eveningDoneAt = eat
            r.skipped = skipped
            result[key] = r
        }
        return result
    }

    private func stat(_ summary: StatisticsSummary, _ key: String) -> DailyStat? {
        summary.days.first { $0.dateKey == key }
    }

    func testRangeLengthAndAscendingOrder() {
        let s = Statistics.compute(records: [:], settings: .default, now: now, rangeDays: 7, calendar: cal)
        XCTAssertEqual(s.days.count, 7)
        XCTAssertEqual(s.days.first?.dateKey, "2026-09-10")
        XCTAssertEqual(s.days.last?.dateKey, "2026-09-16")
    }

    func testWorkDurationAndAverage() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, TestTime.date(2026, 9, 14, 9, 0), TestTime.date(2026, 9, 14, 18, 10), false),
            (TestTime.date(2026, 9, 15), true, true, TestTime.date(2026, 9, 15, 9, 5), TestTime.date(2026, 9, 15, 18, 0), false)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: now, rangeDays: 7, calendar: cal)
        XCTAssertEqual(stat(s, "2026-09-14")?.workDuration, 33000)
        XCTAssertEqual(stat(s, "2026-09-15")?.workDuration, 32100)
        XCTAssertEqual(s.averageWorkDuration ?? 0, 32550, accuracy: 0.5)
    }

    func testEveningBeforeMorningYieldsNilDuration() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, TestTime.date(2026, 9, 14, 18, 0), TestTime.date(2026, 9, 14, 9, 0), false)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: now, rangeDays: 3, calendar: cal)
        XCTAssertNil(stat(s, "2026-09-14")?.workDuration)
        XCTAssertNil(s.averageWorkDuration)
    }

    func testWeekendNeverMissed() {
        let s = Statistics.compute(records: [:], settings: .default, now: now, rangeDays: 7, calendar: cal)
        // 09-10,11,14,15,16 为工作日=5；其中今天(09-16)未到截止不算缺卡 -> 4
        XCTAssertEqual(s.missedDays, 4)
        XCTAssertEqual(stat(s, "2026-09-12")?.isWorkday, false)
    }

    func testSkippedNotMissedAndKeepsStreak() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, TestTime.date(2026, 9, 14, 9, 0), TestTime.date(2026, 9, 14, 18, 0), false),
            (TestTime.date(2026, 9, 15), false, false, nil, nil, true)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: now, rangeDays: 7, calendar: cal)
        XCTAssertEqual(stat(s, "2026-09-15")?.skipped, true)
        // 缺卡：09-10(四), 09-11(五) 未完成 = 2；09-14 完成；09-15 跳过；09-16 今天未到期
        XCTAssertEqual(s.missedDays, 2)
        // 连续：今天(09-16)进行中 -> 从昨天起：09-15 跳过跨过 -> 09-14 完成 -> +1；09-11 未完成 -> 停
        XCTAssertEqual(s.currentStreak, 1)
    }

    func testStreakCountsConsecutiveWorkdays() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, nil, nil, false),
            (TestTime.date(2026, 9, 15), true, true, nil, nil, false)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: now, rangeDays: 14, calendar: cal)
        XCTAssertEqual(s.currentStreak, 2)
    }

    func testTodayIncompleteAfterDeadlineBreaksStreakAndCountsMissed() {
        let lateNow = TestTime.date(2026, 9, 16, 19, 0)
        let recs = records([
            (TestTime.date(2026, 9, 15), true, true, nil, nil, false)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: lateNow, rangeDays: 7, calendar: cal)
        // 今天已过下班截止且未完成 -> 断连中，连续为 0
        XCTAssertEqual(s.currentStreak, 0)
        XCTAssertTrue(s.missedDays >= 1)
    }

    func testMonthPunchDays() {
        let recs = records([
            (TestTime.date(2026, 9, 14), true, true, nil, nil, false),
            (TestTime.date(2026, 9, 15), true, true, nil, nil, false),
            (TestTime.date(2026, 8, 31), true, true, nil, nil, false)
        ])
        let s = Statistics.compute(records: recs, settings: .default, now: now, rangeDays: 30, calendar: cal)
        // 仅 9 月的工作日两次完成：09-14, 09-15 = 2
        XCTAssertEqual(s.monthPunchDays, 2)
    }
}
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter StatisticsTests`
Expected: 编译失败，`cannot find 'Statistics' in scope`。

- [ ] **Step 3: 实现 `Sources/DakaCore/Statistics.swift`**

```swift
import Foundation

public struct DailyStat: Equatable, Sendable {
    public let dateKey: String
    public let weekday: Int
    public let isWorkday: Bool
    public let completedBoth: Bool
    public let skipped: Bool
    public let morningDoneAt: Date?
    public let eveningDoneAt: Date?
    public let workDuration: TimeInterval?

    public init(dateKey: String,
                weekday: Int,
                isWorkday: Bool,
                completedBoth: Bool,
                skipped: Bool,
                morningDoneAt: Date?,
                eveningDoneAt: Date?,
                workDuration: TimeInterval?) {
        self.dateKey = dateKey
        self.weekday = weekday
        self.isWorkday = isWorkday
        self.completedBoth = completedBoth
        self.skipped = skipped
        self.morningDoneAt = morningDoneAt
        self.eveningDoneAt = eveningDoneAt
        self.workDuration = workDuration
    }
}

public struct StatisticsSummary: Equatable, Sendable {
    public var days: [DailyStat]
    public var rangeDays: Int
    public var monthPunchDays: Int
    public var currentStreak: Int
    public var averageWorkDuration: TimeInterval?
    public var missedDays: Int

    public init(days: [DailyStat] = [],
                rangeDays: Int = 0,
                monthPunchDays: Int = 0,
                currentStreak: Int = 0,
                averageWorkDuration: TimeInterval? = nil,
                missedDays: Int = 0) {
        self.days = days
        self.rangeDays = rangeDays
        self.monthPunchDays = monthPunchDays
        self.currentStreak = currentStreak
        self.averageWorkDuration = averageWorkDuration
        self.missedDays = missedDays
    }
}

public enum Statistics {
    public static func compute(records: [String: DayRecord],
                               settings: Settings,
                               now: Date,
                               rangeDays: Int,
                               calendar: Calendar = .current) -> StatisticsSummary {
        let range = max(1, rangeDays)
        let nowMonth = calendar.dateComponents([.year, .month], from: now)
        let eveningDeadlineToday = DakaDate.date(on: now, at: settings.eveningDeadline, calendar: calendar)

        var days: [DailyStat] = []
        var durations: [TimeInterval] = []
        var monthPunch = 0
        var missed = 0

        for offset in stride(from: range - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = DakaDate.key(for: day, calendar: calendar)
            let record = records[key] ?? DayRecord()
            let weekday = DakaDate.weekday(of: day, calendar: calendar)
            let isWorkday = settings.workdays.contains(weekday)
            let completedBoth = record.morningDone && record.eveningDone

            var duration: TimeInterval?
            if let morning = record.morningDoneAt, let evening = record.eveningDoneAt, evening >= morning {
                duration = evening.timeIntervalSince(morning)
            }
            if let duration { durations.append(duration) }

            days.append(DailyStat(dateKey: key, weekday: weekday, isWorkday: isWorkday,
                                  completedBoth: completedBoth, skipped: record.skipped,
                                  morningDoneAt: record.morningDoneAt,
                                  eveningDoneAt: record.eveningDoneAt,
                                  workDuration: duration))

            if isWorkday && completedBoth {
                let dayMonth = calendar.dateComponents([.year, .month], from: day)
                if dayMonth.year == nowMonth.year && dayMonth.month == nowMonth.month {
                    monthPunch += 1
                }
            }

            if isWorkday && !record.skipped && !completedBoth {
                let isToday = calendar.isDate(day, inSameDayAs: now)
                let expired = !isToday || (eveningDeadlineToday.map { now >= $0 } ?? false)
                if expired { missed += 1 }
            }
        }

        let average = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)

        let todayKey = DakaDate.key(for: now, calendar: calendar)
        let todayRecord = records[todayKey] ?? DayRecord()
        let todayCompleted = todayRecord.morningDone && todayRecord.eveningDone
        let todayIsWorkday = settings.workdays.contains(DakaDate.weekday(of: now, calendar: calendar))
        let todayInProgress = todayIsWorkday && !todayRecord.skipped && !todayCompleted
            && (eveningDeadlineToday.map { now < $0 } ?? true)

        var cursor = calendar.startOfDay(for: now)
        if todayInProgress, let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) {
            cursor = yesterday
        }
        var streak = 0
        for _ in 0..<400 {
            let key = DakaDate.key(for: cursor, calendar: calendar)
            let record = records[key] ?? DayRecord()
            let isWorkday = settings.workdays.contains(DakaDate.weekday(of: cursor, calendar: calendar))
            if isWorkday && !record.skipped {
                if record.morningDone && record.eveningDone {
                    streak += 1
                } else {
                    break
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return StatisticsSummary(days: days, rangeDays: range,
                                 monthPunchDays: monthPunch, currentStreak: streak,
                                 averageWorkDuration: average, missedDays: missed)
    }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `swift test --filter StatisticsTests`
Expected: 全部 PASS（8 个测试）。若个别断言与实现口径不符，以 §5 口径为准修正**测试或实现**并说明。

- [ ] **Step 5: 全量测试 + 提交**

Run: `swift test`（期望 54 + 8 = 62）

```bash
git add Sources/DakaCore/Statistics.swift Tests/DakaCoreTests/StatisticsTests.swift
git commit -m "feat: add Statistics computation in core"
```

---

## Task 2: 定点启动后台参数

**Files:**
- Modify: `Sources/DakaCore/LaunchAgentPlist.swift`
- Modify: `Tests/DakaCoreTests/LaunchAgentPlistTests.swift`

- [ ] **Step 1: 更新测试**

在 `Tests/DakaCoreTests/LaunchAgentPlistTests.swift` 的 `testLabelAndProgramArguments` 中，把 `ProgramArguments` 断言改为：

```swift
        XCTAssertEqual(dict["ProgramArguments"] as? [String],
                       ["/usr/bin/open", "-b", "com.xue.daka", "--args", "--background"])
```

- [ ] **Step 2: 运行确认失败**

Run: `swift test --filter LaunchAgentPlistTests`
Expected: `testLabelAndProgramArguments` 失败（当前数组不含 `--args --background`）。

- [ ] **Step 3: 改实现**

`Sources/DakaCore/LaunchAgentPlist.swift` 中把：

```swift
            "ProgramArguments": ["/usr/bin/open", "-b", bundleID]
```

改为：

```swift
            "ProgramArguments": ["/usr/bin/open", "-b", bundleID, "--args", "--background"]
```

- [ ] **Step 4: 通过 + 提交**

Run: `swift test --filter LaunchAgentPlistTests`（期望 6/6）

```bash
git add Sources/DakaCore/LaunchAgentPlist.swift Tests/DakaCoreTests/LaunchAgentPlistTests.swift
git commit -m "feat: launch scheduled app in background"
```

---

## Task 3: 应用形态改造（常规应用 + 主窗口外壳 + 精简状态栏）

**Files:**
- Modify: `Resources/Info.plist`
- Create: `Sources/Daka/MainWindowController.swift`
- Create: `Sources/Daka/MainWindowView.swift`
- Create: `Sources/Daka/SettingsView.swift`
- Modify: `Sources/Daka/MenuBarView.swift`
- Modify: `Sources/Daka/AppModel.swift`
- Modify: `Sources/Daka/AppDelegate.swift`

- [ ] **Step 1: `Resources/Info.plist` 移除 `LSUIElement`**

删除：
```xml
    <key>LSUIElement</key>
    <true/>
```
（改为常规应用，有 Dock 图标。）

- [ ] **Step 2: 新增 `Sources/Daka/MainWindowController.swift`**

```swift
import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: MainWindowView(model: model))
            let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered,
                                   defer: false)
            created.title = "Daka"
            created.isReleasedWhenClosed = false
            created.contentView = hosting
            created.delegate = self
            created.setFrameAutosaveName("DakaMainWindow")
            created.center()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
```

- [ ] **Step 3: 新增 `Sources/Daka/MainWindowView.swift`**

```swift
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            StatisticsView(model: model)
                .tabItem { Label("统计", systemImage: "chart.bar") }
            SettingsView(model: model)
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 520)
    }
}
```

> Task 3 先放一个临时 `StatisticsView`（见 Step 4），Task 4 再换成带图表的版本。

- [ ] **Step 4: 新增 `Sources/Daka/StatisticsView.swift`（临时版，Task 4 替换）**

```swift
import SwiftUI
import DakaCore

struct StatisticsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let summary = model.statistics(rangeDays: 14)
        VStack(alignment: .leading, spacing: 12) {
            Text("本月打卡 \(summary.monthPunchDays) 天")
            Text("连续打卡 \(summary.currentStreak) 天")
            Text("缺卡 \(summary.missedDays) 天")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
```

- [ ] **Step 5: 新增 `Sources/Daka/SettingsView.swift`**

```swift
import SwiftUI
import DakaCore

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Toggle("启用提醒", isOn: Binding(get: { model.settings.enabled },
                                            set: { model.setEnabled($0) }))

            Section("打卡窗口") {
                DatePicker("上班窗口开始", selection: bound(\.morningWindowStart, model.updateMorningStart),
                           displayedComponents: .hourAndMinute)
                DatePicker("上班窗口截止", selection: bound(\.morningDeadline, model.updateMorningDeadline),
                           displayedComponents: .hourAndMinute)
                DatePicker("下班窗口开始", selection: bound(\.eveningWindowStart, model.updateEveningStart),
                           displayedComponents: .hourAndMinute)
                DatePicker("下班窗口截止", selection: bound(\.eveningDeadline, model.updateEveningDeadline),
                           displayedComponents: .hourAndMinute)
            }

            Section("工作日") {
                HStack {
                    ForEach(Self.weekdayOptions, id: \.value) { option in
                        Toggle(option.label, isOn: weekdayBinding(option.value))
                            .toggleStyle(.button)
                    }
                }
            }

            Section("今天") {
                if model.record.skipped {
                    Button("恢复打卡提醒") { model.setSkipped(false) }
                } else {
                    Button("标记今天不打卡（休假）") { model.setSkipped(true) }
                }
            }

            Section("自启与定点") {
                HStack {
                    Image(systemName: LoginItemManager.isEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(LoginItemManager.isEnabled ? Color.green : Color.orange)
                    Text(LoginItemManager.isEnabled ? "开机自启已启用"
                         : (LoginItemManager.requiresApproval ? "开机自启需在系统设置中允许" : "开机自启未启用"))
                    Spacer()
                    if LoginItemManager.requiresApproval {
                        Button("打开设置") { LoginItemManager.openSystemSettings() }
                    } else if !LoginItemManager.isEnabled {
                        Button("启用") { model.repairLoginItem() }
                    }
                }
                HStack {
                    Image(systemName: model.scheduledLaunchInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(model.scheduledLaunchInstalled ? Color.green : Color.orange)
                    Text(model.scheduledLaunchInstalled ? "定点启动已启用" : "定点启动未启用")
                }
            }

            Section("调试") {
                HStack {
                    Button("+10 分钟") { model.debugAdvanceClock(by: 600) }
                    Button("重置时间") { model.resetClock() }
                }
            }

            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            if let warning = model.startupWarning {
                Text(warning).foregroundStyle(.orange)
            }
            if let warning = model.scheduledLaunchWarning {
                Text(warning).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
    }

    private static let weekdayOptions: [(label: String, value: Int)] = [
        ("一", 2), ("二", 3), ("三", 4), ("四", 5), ("五", 6), ("六", 7), ("日", 1)
    ]

    private func weekdayBinding(_ value: Int) -> Binding<Bool> {
        Binding(get: { model.settings.workdays.contains(value) },
                set: { on in
                    var days = model.settings.workdays
                    if on { days.insert(value) } else { days.remove(value) }
                    model.setWorkdays(days)
                })
    }

    private func bound(_ keyPath: KeyPath<DakaCore.Settings, String>,
                       _ update: @escaping (String) -> Void) -> Binding<Date> {
        Binding(get: { Self.dateFrom(model.settings[keyPath: keyPath]) },
                set: { update(Self.hhmm(from: $0)) })
    }

    private static func dateFrom(_ hhmm: String) -> Date {
        DakaDate.date(on: Date(), at: hhmm) ?? Date()
    }

    private static func hhmm(from date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
```

- [ ] **Step 6: 精简 `Sources/Daka/MenuBarView.swift`**

整体替换为：

```swift
import SwiftUI
import DakaCore

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日打卡").font(.headline)

            statusRow(.morning, done: model.record.morningDone, at: model.record.morningDoneAt,
                      start: model.settings.morningWindowStart, deadline: model.settings.morningDeadline)
            statusRow(.evening, done: model.record.eveningDone, at: model.record.eveningDoneAt,
                      start: model.settings.eveningWindowStart, deadline: model.settings.eveningDeadline)

            Divider()

            HStack {
                Button("上班打卡") { model.punch(.morning) }
                    .disabled(model.record.morningDone)
                Button("下班打卡") { model.punch(.evening) }
                    .disabled(model.record.eveningDone)
            }

            Divider()

            Button("打开 Daka") { model.openMainWindow() }
            Button("退出 Daka") { model.quit() }
                .disabled(model.hasHardTasks)

            if let warning = model.scheduledLaunchWarning {
                Text(warning).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func statusRow(_ task: PunchTask, done: Bool, at: Date?, start: String, deadline: String) -> some View {
        HStack {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
            Text(task.title)
            Spacer()
            if done, let at {
                Text(Self.timeFormatter.string(from: at)).foregroundStyle(.secondary)
            } else if model.reminderState.hard.contains(task) {
                Text("已过截止 \(deadline)").foregroundStyle(.red)
            } else if model.reminderState.gentle.contains(task) {
                Text("窗口内 \(start)–\(deadline)").foregroundStyle(.orange)
            } else {
                Text("待打卡 \(start)–\(deadline)").foregroundStyle(.secondary)
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
```

- [ ] **Step 7: `AppModel` 增加主窗口与统计支持**

- 增加属性：
```swift
    weak var mainWindow: MainWindowController?
```
- 增加方法：
```swift
    func openMainWindow() {
        mainWindow?.show()
    }

    func statistics(rangeDays: Int) -> StatisticsSummary {
        Statistics.compute(records: store.data.records,
                           settings: store.data.settings,
                           now: clock.now,
                           rangeDays: rangeDays)
    }

    func setWorkdays(_ days: Set<Int>) {
        updateSettings { $0.workdays = days }
    }
```

- [ ] **Step 8: `AppDelegate` 改造**

整体替换为：

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [])
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let model = AppModel.shared
        let controller = MainWindowController(model: model)
        self.mainWindow = controller
        model.mainWindow = controller

        model.start()

        let isBackground = CommandLine.arguments.contains("--background")
        let launchKey = "NSApplicationLaunchIsDefaultLaunchKey"
        let isUserLaunch = (notification.userInfo?[launchKey] as? Bool) ?? true
        if !isBackground && isUserLaunch {
            controller.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow?.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let hard = MainActor.assumeIsolated { AppModel.shared.hasHardTasks }
        return hard ? .terminateCancel : .terminateNow
    }
}
```

- [ ] **Step 9: 构建**

Run: `swift build`
Expected: `Build complete!`（若 `MainWindowController` 的 `weak var mainWindow` 有问题，改为 `var` 并在 AppDelegate 持有强引用即可）。

- [ ] **Step 10: 测试 + 提交**

Run: `swift test`（期望 62，仅核心逻辑，无新增）

```bash
git add Resources/Info.plist Sources/Daka
git commit -m "feat: regular app with main window shell and simplified menu bar"
```

---

## Task 4: 统计页（指标卡 + Swift Charts）

**Files:**
- Modify: `Sources/Daka/StatisticsView.swift`

- [ ] **Step 1: 替换 `Sources/Daka/StatisticsView.swift` 为带指标的图表版**

```swift
import SwiftUI
import Charts
import DakaCore

struct StatisticsView: View {
    @ObservedObject var model: AppModel
    @State private var rangeDays = 14

    private var summary: StatisticsSummary {
        model.statistics(rangeDays: rangeDays)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    metricCard("本月打卡", "\(summary.monthPunchDays) 天", "calendar")
                    metricCard("连续打卡", "\(summary.currentStreak) 天", "flame")
                    metricCard("平均上班", averageText, "clock")
                    metricCard("缺卡", "\(summary.missedDays) 天", "exclamationmark.triangle")
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("每日上班时长").font(.headline)
                        Spacer()
                        Picker("范围", selection: $rangeDays) {
                            Text("7 天").tag(7)
                            Text("14 天").tag(14)
                            Text("30 天").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    let chartDays = summary.days.filter { $0.workDuration != nil }
                    if chartDays.isEmpty {
                        Text("还没有足够的打卡记录")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        Chart(chartDays, id: \.dateKey) { day in
                            BarMark(
                                x: .value("日期", String(day.dateKey.suffix(5))),
                                y: .value("小时", (day.workDuration ?? 0) / 3600)
                            )
                            .foregroundStyle(Color.accentColor)
                        }
                        .chartYAxisLabel("小时")
                        .frame(height: 240)
                    }
                }
            }
        }
    }

    private var averageText: String {
        guard let average = summary.averageWorkDuration else { return "—" }
        let hours = Int(average) / 3600
        let minutes = (Int(average) % 3600) / 60
        return "\(hours)h\(minutes)m"
    }

    private func metricCard(_ title: String, _ value: String, _ systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}
```

- [ ] **Step 2: 构建 + 测试**

Run: `swift build && swift test`
Expected: 构建成功；62 测试通过。

- [ ] **Step 3: 提交**

```bash
git add Sources/Daka/StatisticsView.swift
git commit -m "feat: statistics dashboard with work-duration chart"
```

---

## Task 5: 文档与安装

**Files:**
- Modify: `docs/verification.md`
- Modify: `Resources/Info.plist`（若 Task 3 已处理则跳过）

- [ ] **Step 1: 在 `docs/verification.md` 增加 v3 条目**

在文件末尾追加：

```markdown
## v3：应用主窗口与统计

- [ ] Dock 出现 Daka 图标；双击或点 Dock 图标会打开主窗口。
- [ ] 主窗口关闭后应用仍在后台提醒；再点 Dock 图标 / 菜单栏「打开 Daka」可重新打开。
- [ ] 主窗口「统计」页显示本月打卡、连续打卡、平均上班、缺卡四项；无数据时提示占位。
- [ ] 「统计」页柱状图显示每日上班时长，可切 7 / 14 / 30 天。
- [ ] 主窗口「设置」页可改启用、工作日、4 个时间、今天不打卡、查看自启与定点状态、调试时间。
- [ ] 状态栏面板只剩：今日状态、两个打卡按钮、「打开 Daka」、退出；不再有设置与统计。
- [ ] 登录/定点拉起（带 `--background`）时不弹主窗口。
- [ ] 图标三态（勾/铃铛/三角）仍正确。
```

- [ ] **Step 2: 安装**

Run: `make install`
Expected: `Installed to /Applications/Daka.app`。

- [ ] **Step 3: 提交**

```bash
git add docs/verification.md
git commit -m "docs: verify v3 app window and statistics"
```

---

## 完成标准

- `swift test` 全绿（≥62）。
- `make install` 成功；Dock 有图标，主窗口含统计与设置。
- 状态栏仅「状态 + 打卡 + 打开主界面 + 退出」。
- 后台启动（`--background` / 登录项）不弹窗。
- `docs/verification.md` 的 v3 条目通过。
