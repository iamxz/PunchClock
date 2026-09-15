# Daka v6（休假日期标记）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans.

**Goal:** 主窗口新增「休假」标签页，按月列出每天并逐天标记休假（可补标过去、预标未来），效果为不提醒/不计缺卡/不断连续。

**Architecture:** `DakaCore` 新增纯函数 `LeaveCalendar.monthDays` 生成 `DayInfo`；`PunchStore.setSkipped(_:on:)` 已支持任意日期；应用层新增 `LeaveDaysView` 与 `AppModel.monthDays/setSkipped(_:on:)`。

**Spec:** `docs/superpowers/specs/2026-09-15-daka-leave-days-design.md`

---

## Task 1: 核心 —— 月度日期列表

**Files:**
- Create: `Sources/DakaCore/LeaveCalendar.swift`
- Create: `Tests/DakaCoreTests/LeaveCalendarTests.swift`
- Modify: `Tests/DakaCoreTests/PunchStoreTests.swift`（跨月 setSkipped）

### 1.1 新增 `Sources/DakaCore/LeaveCalendar.swift`

```swift
import Foundation

public struct DayInfo: Equatable, Sendable, Identifiable {
    public let dateKey: String
    public let date: Date
    public let isWorkday: Bool
    public let skipped: Bool
    public let completedBoth: Bool
    public let isFuture: Bool

    public var id: String { dateKey }

    public init(dateKey: String, date: Date, isWorkday: Bool,
                skipped: Bool, completedBoth: Bool, isFuture: Bool) {
        self.dateKey = dateKey
        self.date = date
        self.isWorkday = isWorkday
        self.skipped = skipped
        self.completedBoth = completedBoth
        self.isFuture = isFuture
    }
}

public enum LeaveCalendar {
    public static func monthDays(containing month: Date,
                                 records: [String: DayRecord],
                                 settings: Settings,
                                 now: Date,
                                 calendar: Calendar = .current) -> [DayInfo] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return []
        }
        let startOfToday = calendar.startOfDay(for: now)
        var result: [DayInfo] = []
        for offset in range {
            guard let day = calendar.date(byAdding: .day, value: offset - 1, to: first) else { continue }
            let key = DakaDate.key(for: day, calendar: calendar)
            let record = records[key] ?? DayRecord()
            let isWorkday = settings.workdays.contains(DakaDate.weekday(of: day, calendar: calendar))
            let completedBoth = record.morningDone
                && PunchRules.isEveningComplete(record, minWorkDuration: settings.minWorkDuration)
            result.append(DayInfo(dateKey: key,
                                  date: day,
                                  isWorkday: isWorkday,
                                  skipped: record.skipped,
                                  completedBoth: completedBoth,
                                  isFuture: calendar.startOfDay(for: day) > startOfToday))
        }
        return result
    }
}
```

### 1.2 测试 `Tests/DakaCoreTests/LeaveCalendarTests.swift`

```swift
import XCTest
@testable import DakaCore

final class LeaveCalendarTests: XCTestCase {
    private let cal = TestTime.calendar
    private var now: Date { TestTime.date(2026, 9, 16, 10, 0) }
    private var sept: Date { TestTime.date(2026, 9, 1, 0, 0) }

    private func days(records: [String: DayRecord] = [:]) -> [DayInfo] {
        LeaveCalendar.monthDays(containing: sept, records: records, settings: .default, now: now, calendar: cal)
    }

    func testSeptemberHas30DaysAscending() {
        let result = days()
        XCTAssertEqual(result.count, 30)
        XCTAssertEqual(result.first?.dateKey, "2026-09-01")
        XCTAssertEqual(result.last?.dateKey, "2026-09-30")
    }

    func testWorkdayFlags() {
        let result = days()
        XCTAssertEqual(result.first { $0.dateKey == "2026-09-14" }?.isWorkday, true)  // 周一
        XCTAssertEqual(result.first { $0.dateKey == "2026-09-12" }?.isWorkday, false) // 周六
    }

    func testFutureFlag() {
        let result = days()
        XCTAssertEqual(result.first { $0.dateKey == "2026-09-15" }?.isFuture, false)
        XCTAssertEqual(result.first { $0.dateKey == "2026-09-17" }?.isFuture, true)
    }

    func testSkippedAndCompleted() {
        let key = "2026-09-14"
        var record = DayRecord()
        record.skipped = true
        let result = days(records: [key: record])
        XCTAssertEqual(result.first { $0.dateKey == key }?.skipped, true)
        XCTAssertEqual(result.first { $0.dateKey == key }?.completedBoth, false)
    }

    func testCompletedNeedMinimumWork() {
        let key = "2026-09-14"
        let complete = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                                 eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let short = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                              eveningPunches: [TestTime.date(2026, 9, 14, 15, 0)])
        XCTAssertEqual(days(records: [key: complete]).first { $0.dateKey == key }?.completedBoth, true)
        XCTAssertEqual(days(records: [key: short]).first { $0.dateKey == key }?.completedBoth, false)
    }
}
```

### 1.3 `Tests/DakaCoreTests/PunchStoreTests.swift` 追加

```swift
    func testSetSkippedOnAnotherMonthDate() throws {
        let day = TestTime.date(2026, 10, 5, 12, 0)
        let store = PunchStore(fileURL: url)
        try store.setSkipped(true, on: day, calendar: TestTime.calendar)
        let reloaded = PunchStore(fileURL: url)
        XCTAssertTrue(reloaded.record(for: day, calendar: TestTime.calendar).skipped)
    }
```

### 1.4 验证

`swift build && swift test`（80 + 5 + 1 = 86）。提交：
`git commit -m "feat: LeaveCalendar month day list"`

---

## Task 2: 应用层 —— 休假标签页

**Files:**
- Modify: `Sources/Daka/AppModel.swift`
- Create: `Sources/Daka/LeaveDaysView.swift`
- Modify: `Sources/Daka/MainWindowView.swift`

### 2.1 `AppModel`

```swift
    func monthDays(containing month: Date) -> [DayInfo] {
        LeaveCalendar.monthDays(containing: month,
                                records: store.data.records,
                                settings: store.data.settings,
                                now: clock.now)
    }

    func setSkipped(_ skipped: Bool, on date: Date) {
        do {
            try store.setSkipped(skipped, on: date)
            refreshRecord()
            scheduler?.tick()
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }
```

并把现有 `setSkipped(_ skipped: Bool)` 改为 `setSkipped(skipped, on: clock.now)`。

### 2.2 新增 `Sources/Daka/LeaveDaysView.swift`

```swift
import SwiftUI
import DakaCore

struct LeaveDaysView: View {
    @ObservedObject var model: AppModel
    @State private var month: Date = Date()

    private var days: [DayInfo] { model.monthDays(containing: month) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                Text(monthTitle).font(.headline).frame(minWidth: 140)
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                Spacer()
                Text("勾选即标记该天休假（不提醒、不计缺卡）")
                    .font(.caption).foregroundStyle(.secondary)
            }

            List(days) { day in
                HStack {
                    Text(dayLabel(day.date)).monospacedDigit().frame(width: 110, alignment: .leading)
                    Text(statusText(day)).foregroundStyle(statusColor(day)).font(.caption)
                    Spacer()
                    Toggle("", isOn: skipBinding(day)).labelsHidden()
                }
            }
        }
        .padding(16)
    }

    private func shiftMonth(_ delta: Int) {
        if let next = Calendar.current.date(byAdding: .month, value: delta, to: month) {
            month = next
        }
    }

    private var monthTitle: String {
        let c = Calendar.current.dateComponents([.year, .month], from: month)
        return "\(c.year ?? 0) 年 \(c.month ?? 0) 月"
    }

    private func dayLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        let wf = DateFormatter()
        wf.locale = Locale(identifier: "zh_CN")
        wf.dateFormat = "EEE"
        return "\(f.string(from: date)) \(wf.string(from: date))"
    }

    private func statusText(_ day: DayInfo) -> String {
        if day.skipped { return "休假" }
        if !day.isWorkday { return "非工作日" }
        if day.completedBoth { return "已完成" }
        if day.isFuture { return "待打卡" }
        return "缺卡"
    }

    private func statusColor(_ day: DayInfo) -> Color {
        if day.skipped { return .secondary }
        if !day.isWorkday { return .secondary }
        if day.completedBoth { return .green }
        if day.isFuture { return .secondary }
        return .red
    }

    private func skipBinding(_ day: DayInfo) -> Binding<Bool> {
        Binding(get: { day.skipped },
                set: { model.setSkipped($0, on: day.date) })
    }
}
```

### 2.3 `MainWindowView` 增加第三个标签页

```swift
            LeaveDaysView(model: model)
                .tabItem { Label("休假", systemImage: "calendar") }
```

### 2.4 验证

`swift build && swift test`（86）；`make install`。提交：
`git commit -m "feat: leave-days tab in main window"`

---

## Task 3: 文档

- `docs/verification.md` 增加 v6 条目：休假标签页可逐天标记过去/未来；标记后不提醒、不计缺卡、不断连续；周末显示非工作日。
- `make install`。

提交 `docs: verify leave days`。

---

## 完成标准

- `swift test` 全绿（≥86）。
- 主窗口「休假」页可对任意日期勾选休假并持久化。
- 休假当天不提醒、统计不计缺卡、不断连续。
