# Daka: 考勤参数化动态下班时间 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将打卡窗口与考勤规则合并，用 workStartTime / workDurationHours / flexMinutes 三个参数推导动态下班时间，取代固定窗口。

**Architecture:** 新增 AttendanceRule 纯函数推导有效上班时间、应下班时间与下班完成判定；Settings 新增考勤三参数并做旧字段迁移解码；ScheduleEvaluator 等 DakaCore 消费者全部改用推导函数；Daka 应用层更新 UI 与定时报时。PunchRules 删除，职责并入 AttendanceRule。

**Tech Stack:** Swift 5.10 / SwiftUI / macOS 14+ / SPM

> **注意：** Task 1–6 仅涉及 DakaCore，`swift test` 仅编译测试目标。Daka 应用层在 Task 7 统一适配。Task 1–4 期间旧字段仍在 Settings 中保留，确保模块编译通过。

---

### Task 1: Settings 新增考勤参数与迁移解码

**Files:**
- Modify: `Sources/DakaCore/Models.swift`
- Modify: `Tests/DakaCoreTests/SettingsTests.swift`

- [ ] **Step 1: 更新测试（failing）**

```swift
// Tests/DakaCoreTests/SettingsTests.swift
import XCTest
@testable import DakaCore

final class SettingsTests: XCTestCase {
    func testDefaults() {
        let s = Settings.default
        XCTAssertEqual(s.workStartTime, "09:00")
        XCTAssertEqual(s.workDurationHours, 9)
        XCTAssertEqual(s.flexMinutes, 30)
        XCTAssertEqual(s.reminderIntervalSeconds, 120)
        XCTAssertEqual(s.workDuration, 9 * 3600)
        XCTAssertEqual(s.flexDuration, 30 * 60)
    }

    func testRoundTrip() throws {
        var s = Settings.default
        s.workStartTime = "08:30"
        s.workDurationHours = 8.5
        s.flexMinutes = 15
        s.enabled = false
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Settings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testLegacyJSONMigratesOldKeys() throws {
        let legacy = """
        {
          "enabled": true,
          "workdays": [2,3,4,5,6],
          "morningWindowStart": "09:00",
          "morningDeadline": "09:40",
          "minWorkDurationHours": 8,
          "reminderIntervalSeconds": 60
        }
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: legacy)
        XCTAssertEqual(decoded.workStartTime, "09:00")
        XCTAssertEqual(decoded.flexMinutes, 40)
        XCTAssertEqual(decoded.workDurationHours, 8)
        XCTAssertEqual(decoded.reminderIntervalSeconds, 60)
    }

    func testVeryOldJSONUsesDefaults() throws {
        let legacy = #"{"enabled": false, "morningTime": "07:00"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: legacy)
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.workStartTime, "09:00")
        XCTAssertEqual(decoded.flexMinutes, 30)
        XCTAssertEqual(decoded.workDurationHours, 9)
    }

    func testPartialJSONUsesDefaultsForMissing() throws {
        let partial = #"{"enabled": false}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(Settings.self, from: partial)
        XCTAssertFalse(decoded.enabled)
        XCTAssertEqual(decoded.workStartTime, "09:00")
    }

    func testReminderIntervalIsClamped() {
        var s = Settings.default
        s.reminderIntervalSeconds = 0
        XCTAssertEqual(s.effectiveReminderIntervalSeconds, 30)
        s.reminderIntervalSeconds = 120
        XCTAssertEqual(s.effectiveReminderIntervalSeconds, 120)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
swift test --filter SettingsTests
```

- [ ] **Step 3: 实现 Settings 新字段**

在 `Sources/DakaCore/Models.swift` 的 `Settings` 中新增：

```swift
public struct Settings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var workdays: Set<Int>
    // 考勤参数（新）
    public var workStartTime: String
    public var workDurationHours: Double
    public var flexMinutes: Int
    // 旧字段（过渡期保留）
    public var morningWindowStart: String
    public var morningDeadline: String
    public var eveningWindowStart: String
    public var eveningDeadline: String
    public var minWorkDurationHours: Double
    public var reminderIntervalSeconds: TimeInterval

    public init(enabled: Bool = true,
                workdays: Set<Int> = [2, 3, 4, 5, 6],
                workStartTime: String = "09:00",
                workDurationHours: Double = 9,
                flexMinutes: Int = 30,
                morningWindowStart: String = "09:00",
                morningDeadline: String = "09:30",
                eveningWindowStart: String = "18:00",
                eveningDeadline: String = "18:30",
                minWorkDurationHours: Double = 8,
                reminderIntervalSeconds: TimeInterval = 120) {
        self.enabled = enabled
        self.workdays = workdays
        self.workStartTime = workStartTime
        self.workDurationHours = workDurationHours
        self.flexMinutes = flexMinutes
        self.morningWindowStart = morningWindowStart
        self.morningDeadline = morningDeadline
        self.eveningWindowStart = eveningWindowStart
        self.eveningDeadline = eveningDeadline
        self.minWorkDurationHours = minWorkDurationHours
        self.reminderIntervalSeconds = reminderIntervalSeconds
    }

    public var effectiveReminderIntervalSeconds: TimeInterval {
        max(30, reminderIntervalSeconds)
    }

    public var workDuration: TimeInterval { max(0.5, workDurationHours) * 3600 }
    public var flexDuration: TimeInterval { TimeInterval(max(0, flexMinutes) * 60) }

    public static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case enabled, workdays
        case workStartTime, workDurationHours, flexMinutes
        case morningWindowStart, morningDeadline
        case eveningWindowStart, eveningDeadline
        case minWorkDurationHours
        case reminderIntervalSeconds
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        self.workdays = try c.decodeIfPresent(Set<Int>.self, forKey: .workdays) ?? d.workdays

        if let v = try c.decodeIfPresent(String.self, forKey: .workStartTime) {
            self.workStartTime = v
        } else if let old = try c.decodeIfPresent(String.self, forKey: .morningWindowStart) {
            self.workStartTime = old
        } else {
            self.workStartTime = d.workStartTime
        }
        if let v = try c.decodeIfPresent(Double.self, forKey: .workDurationHours) {
            self.workDurationHours = v
        } else if let old = try c.decodeIfPresent(Double.self, forKey: .minWorkDurationHours) {
            self.workDurationHours = old
        } else {
            self.workDurationHours = d.workDurationHours
        }
        if let v = try c.decodeIfPresent(Int.self, forKey: .flexMinutes) {
            self.flexMinutes = v
        } else if let s = try c.decodeIfPresent(String.self, forKey: .morningWindowStart),
                  let e = try c.decodeIfPresent(String.self, forKey: .morningDeadline),
                  let sc = DakaDate.timeComponents(s),
                  let ec = DakaDate.timeComponents(e) {
            self.flexMinutes = max(0, (ec.hour * 60 + ec.minute) - (sc.hour * 60 + sc.minute))
        } else {
            self.flexMinutes = d.flexMinutes
        }

        self.morningWindowStart = try c.decodeIfPresent(String.self, forKey: .morningWindowStart) ?? d.morningWindowStart
        self.morningDeadline = try c.decodeIfPresent(String.self, forKey: .morningDeadline) ?? d.morningDeadline
        self.eveningWindowStart = try c.decodeIfPresent(String.self, forKey: .eveningWindowStart) ?? d.eveningWindowStart
        self.eveningDeadline = try c.decodeIfPresent(String.self, forKey: .eveningDeadline) ?? d.eveningDeadline
        self.minWorkDurationHours = try c.decodeIfPresent(Double.self, forKey: .minWorkDurationHours) ?? d.minWorkDurationHours
        self.reminderIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .reminderIntervalSeconds) ?? d.reminderIntervalSeconds
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
swift test --filter SettingsTests
```

- [ ] **Step 5: 提交**

```bash
git add Sources/DakaCore/Models.swift Tests/DakaCoreTests/SettingsTests.swift
git commit -m "refactor: add workStartTime/workDurationHours/flexMinutes with migration"
```

---

### Task 2: AttendanceRule 纯函数

**Files:**
- Create: `Sources/DakaCore/AttendanceRule.swift`
- Create: `Tests/DakaCoreTests/AttendanceRuleTests.swift`

- [ ] **Step 1: 写测试**

```swift
// Tests/DakaCoreTests/AttendanceRuleTests.swift
import XCTest
@testable import DakaCore

final class AttendanceRuleTests: XCTestCase {
    private let cal = TestTime.calendar
    private let settings = Settings.default

    private func leave(_ record: DayRecord, on day: Date) -> Date? {
        AttendanceRule.expectedLeave(record, settings: settings, on: day, calendar: cal)
    }
    private func complete(_ record: DayRecord, on day: Date) -> Bool {
        AttendanceRule.isEveningComplete(record, settings: settings, on: day, calendar: cal)
    }

    func testNoMorningPunchYieldsNil() {
        let day = TestTime.date(2026, 9, 14, 18, 0)
        let record = DayRecord(eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        XCTAssertNil(AttendanceRule.effectiveStart(record, settings: settings, on: day, calendar: cal))
        XCTAssertNil(leave(record, on: day))
        XCTAssertFalse(complete(record, on: day))
    }

    func testEarlyPunchCountsAsWorkStart() {
        let day = TestTime.date(2026, 9, 14, 8, 40)
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 8, 40)])
        XCTAssertEqual(AttendanceRule.effectiveStart(record, settings: settings, on: day, calendar: cal),
                       TestTime.date(2026, 9, 14, 9, 0))
        XCTAssertEqual(leave(record, on: day), TestTime.date(2026, 9, 14, 18, 0))
    }

    func testPunchWithinFlexShiftsLeave() {
        let day = TestTime.date(2026, 9, 14, 9, 16)
        let record = DayRecord(morningPunches: [day])
        XCTAssertEqual(leave(record, on: day), TestTime.date(2026, 9, 14, 18, 16))
    }

    func testLatePunchNoUpperBound() {
        let day = TestTime.date(2026, 9, 14, 10, 0)
        let record = DayRecord(morningPunches: [day])
        XCTAssertEqual(leave(record, on: day), TestTime.date(2026, 9, 14, 19, 0))
    }

    func testEarliestMorningPunchUsed() {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 30),
                                                 TestTime.date(2026, 9, 14, 8, 50)])
        XCTAssertEqual(AttendanceRule.effectiveStart(record, settings: settings, on: day, calendar: cal),
                       TestTime.date(2026, 9, 14, 9, 0))
    }

    func testEarlyEveningPunchDoesNotComplete() {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [day],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 10)])
        XCTAssertFalse(complete(record, on: day))
    }

    func testQualifyingEveningPunchCompletes() {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [day],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        XCTAssertTrue(complete(record, on: day))
    }

    func testLatestQualifyingPunchWins() {
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [day],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0),
                                                TestTime.date(2026, 9, 14, 19, 0)])
        XCTAssertEqual(AttendanceRule.effectiveEveningPunch(record, settings: settings, on: day, calendar: cal),
                       TestTime.date(2026, 9, 14, 19, 0))
    }

    func testCustomWorkDuration() {
        var s = Settings.default
        s.workDurationHours = 8
        let day = TestTime.date(2026, 9, 14, 9, 0)
        let record = DayRecord(morningPunches: [day])
        XCTAssertEqual(AttendanceRule.expectedLeave(record, settings: s, on: day, calendar: cal),
                       TestTime.date(2026, 9, 14, 17, 0))
    }

    func testWindows() {
        XCTAssertEqual(AttendanceRule.windowStart(settings, on: TestTime.monday, calendar: cal),
                       TestTime.date(2026, 9, 14, 9, 0))
        XCTAssertEqual(AttendanceRule.windowEnd(settings, on: TestTime.monday, calendar: cal),
                       TestTime.date(2026, 9, 14, 9, 30))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
swift test --filter AttendanceRuleTests
```

- [ ] **Step 3: 实现 AttendanceRule**

```swift
// Sources/DakaCore/AttendanceRule.swift
import Foundation

public enum AttendanceRule {
    public static func windowStart(_ settings: Settings,
                                   on day: Date,
                                   calendar: Calendar = .current) -> Date? {
        DakaDate.date(on: day, at: settings.workStartTime, calendar: calendar)
    }

    public static func windowEnd(_ settings: Settings,
                                 on day: Date,
                                 calendar: Calendar = .current) -> Date? {
        windowStart(settings, on: day, calendar: calendar)?.addingTimeInterval(settings.flexDuration)
    }

    public static func effectiveStart(_ record: DayRecord,
                                      settings: Settings,
                                      on day: Date,
                                      calendar: Calendar = .current) -> Date? {
        guard let morning = record.morningDoneAt else { return nil }
        guard let start = windowStart(settings, on: day, calendar: calendar) else { return nil }
        return max(start, morning)
    }

    public static func expectedLeave(_ record: DayRecord,
                                     settings: Settings,
                                     on day: Date,
                                     calendar: Calendar = .current) -> Date? {
        effectiveStart(record, settings: settings, on: day, calendar: calendar)?
            .addingTimeInterval(settings.workDuration)
    }

    public static func effectiveEveningPunch(_ record: DayRecord,
                                             settings: Settings,
                                             on day: Date,
                                             calendar: Calendar = .current) -> Date? {
        guard let leave = expectedLeave(record, settings: settings, on: day, calendar: calendar) else { return nil }
        return record.eveningPunches.filter { $0 >= leave }.max()
    }

    public static func isEveningComplete(_ record: DayRecord,
                                         settings: Settings,
                                         on day: Date,
                                         calendar: Calendar = .current) -> Bool {
        effectiveEveningPunch(record, settings: settings, on: day, calendar: calendar) != nil
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
swift test --filter AttendanceRuleTests
```

- [ ] **Step 5: 提交**

```bash
git add Sources/DakaCore/AttendanceRule.swift Tests/DakaCoreTests/AttendanceRuleTests.swift
git commit -m "feat: add AttendanceRule pure functions for dynamic leave time"
```

---

### Task 3: 切换 ScheduleEvaluator 到 AttendanceRule

**Files:**
- Modify: `Sources/DakaCore/ScheduleEvaluator.swift`
- Modify: `Tests/DakaCoreTests/ScheduleEvaluatorTests.swift`

- [ ] **Step 1: 更新测试**

```swift
// Tests/DakaCoreTests/ScheduleEvaluatorTests.swift
import XCTest
@testable import DakaCore

final class ScheduleEvaluatorTests: XCTestCase {
    private let evaluator = ScheduleEvaluator()
    private let cal = TestTime.calendar

    private func reminders(_ date: Date, settings: Settings = .default, record: DayRecord = DayRecord()) -> [PunchTask] {
        evaluator.pendingReminders(now: date, settings: settings, record: record, calendar: cal)
    }

    func testBeforeMorningWindowNoReminders() { XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 8, 59)), []) }
    func testAtMorningWindowStartPending() { XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 0)), [.morning]) }
    func testWithinMorningWindowPending() { XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 29)), [.morning]) }
    func testAfterWindowStartStillPending() { XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 9, 31)), [.morning]) }

    func testNoMorningNoEveningEvenAtNight() { XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 20, 0)), [.morning]) }

    func testMorningDoneEveningNotYetAtLeave() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 17, 59), record: record), [])
    }

    func testMorningDoneAtLeaveEveningPending() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 0), record: record), [.evening])
    }

    func testLatePunchPushesEveningLeave() {
        var settings = Settings.default
        settings.workDurationHours = 9
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 16)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 15), settings: settings, record: record), [])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 16), settings: settings, record: record), [.evening])
    }

    func testEarlyEveningPunchStillPending() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 17, 30)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 18, 10), record: record), [.evening])
    }

    func testBothDoneNoReminders() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 23, 0), record: record), [])
    }

    func testWeekendNoReminders() { XCTAssertEqual(reminders(TestTime.date(2026, 9, 19, 10, 0)), []) }
    func testDisabledNoReminders() { var s = Settings.default; s.enabled = false; XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), settings: s), []) }
    func testSkippedNoReminders() { XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), record: DayRecord(skipped: true)), []) }

    func testInvalidWorkStartTimeYieldsNoReminder() {
        var settings = Settings.default
        settings.workStartTime = "oops"
        XCTAssertEqual(reminders(TestTime.date(2026, 9, 14, 10, 0), settings: settings), [])
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
swift test --filter ScheduleEvaluatorTests
```

- [ ] **Step 3: 实现 ScheduleEvaluator**

```swift
// Sources/DakaCore/ScheduleEvaluator.swift
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

        if pending(start: settings.workStartTime,
                   done: record.morningDone,
                   now: now,
                   calendar: calendar) {
            tasks.append(.morning)
        }
        if let leave = AttendanceRule.expectedLeave(record, settings: settings, on: now, calendar: calendar),
           !AttendanceRule.isEveningComplete(record, settings: settings, on: now, calendar: calendar),
           now >= leave {
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

- [ ] **Step 4: 运行测试确认通过**

```bash
swift test --filter ScheduleEvaluatorTests
```

- [ ] **Step 5: 提交**

```bash
git add Sources/DakaCore/ScheduleEvaluator.swift Tests/DakaCoreTests/ScheduleEvaluatorTests.swift
git commit -m "refactor: ScheduleEvaluator uses AttendanceRule for evening start"
```

---

### Task 4: 切换 WorkProgress / Statistics / HealthRules / PunchTarget / PunchFeedback

**Files:**
- Modify: `Sources/DakaCore/WorkProgress.swift`
- Modify: `Tests/DakaCoreTests/WorkProgressTests.swift`
- Modify: `Sources/DakaCore/Statistics.swift`
- Modify: `Tests/DakaCoreTests/StatisticsTests.swift`
- Modify: `Sources/DakaCore/HealthRules.swift`
- Modify: `Tests/DakaCoreTests/HealthRulesTests.swift`
- Modify: `Sources/DakaCore/PunchTarget.swift`
- Modify: `Tests/DakaCoreTests/PunchTargetTests.swift`
- Modify: `Sources/DakaCore/PunchFeedback.swift`
- Modify: `Tests/DakaCoreTests/PunchFeedbackTests.swift`

- [ ] **Step 1: 更新 WorkProgressTests（failing）**

```swift
// Tests/DakaCoreTests/WorkProgressTests.swift
import XCTest
@testable import DakaCore

final class WorkProgressTests: XCTestCase {
    private let cal = TestTime.calendar
    private let settings = Settings.default

    private func elapsed(_ record: DayRecord, now: Date) -> TimeInterval? {
        WorkProgress.elapsed(record, now: now, settings: settings, calendar: cal)
    }
    private func fraction(_ record: DayRecord, now: Date) -> Double {
        WorkProgress.fraction(record, now: now, settings: settings, calendar: cal)
    }

    func testNoMorningPunchHasNoElapsedAndZeroFraction() {
        let record = DayRecord(eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 18, 0)
        XCTAssertNil(elapsed(record, now: now))
        XCTAssertEqual(fraction(record, now: now), 0)
    }

    func testFourOfNineHoursIsFourNinths() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 13, 0)
        XCTAssertEqual(elapsed(record, now: now), 4 * 3600)
        XCTAssertEqual(fraction(record, now: now), 4.0 / 9.0, accuracy: 1e-9)
    }

    func testOvertimeIsCappedAtOne() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)])
        let now = TestTime.date(2026, 9, 14, 20, 0)
        XCTAssertEqual(fraction(record, now: now), 1)
    }

    func testCompletionUsesQualifyingEveningPunch() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 20, 0)
        XCTAssertEqual(elapsed(record, now: now), 9 * 3600)
        XCTAssertEqual(fraction(record, now: now), 1)
    }

    func testIgnoresNonQualifyingEveningPunch() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 14, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 14, 16, 0),
                                                TestTime.date(2026, 9, 14, 18, 0)])
        let now = TestTime.date(2026, 9, 14, 21, 0)
        XCTAssertEqual(elapsed(record, now: now), 9 * 3600)
    }

    func testHoursTextUnderOneHourShowsMinutes() { XCTAssertEqual(WorkProgress.hoursText(45 * 60), "45m") }
    func testHoursTextWholeHours() { XCTAssertEqual(WorkProgress.hoursText(4 * 3600), "4h") }
    func testHoursTextHalfHour() { XCTAssertEqual(WorkProgress.hoursText(4.5 * 3600), "4.5h") }
    func testHoursTextNegativeIsZero() { XCTAssertEqual(WorkProgress.hoursText(-60), "0m") }
}
```

- [ ] **Step 2: 实现 WorkProgress**

```swift
// Sources/DakaCore/WorkProgress.swift
import Foundation

public enum WorkProgress {
    public static func elapsed(_ record: DayRecord,
                               now: Date,
                               settings: Settings,
                               calendar: Calendar = .current) -> TimeInterval? {
        guard let morning = record.morningDoneAt else { return nil }
        let end = AttendanceRule.effectiveEveningPunch(record, settings: settings, on: now, calendar: calendar) ?? now
        return max(0, end.timeIntervalSince(morning))
    }

    public static func fraction(_ record: DayRecord,
                                now: Date,
                                settings: Settings,
                                calendar: Calendar = .current) -> Double {
        guard let elapsed = elapsed(record, now: now, settings: settings, calendar: calendar) else { return 0 }
        let work = settings.workDuration
        guard work > 0 else { return 1 }
        return min(1, elapsed / work)
    }

    public static func hoursText(_ interval: TimeInterval) -> String {
        let totalMinutes = Int((max(0, interval) / 60).rounded(.down))
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let hours = Double(totalMinutes) / 60
        if hours == hours.rounded() { return "\(Int(hours))h" }
        return String(format: "%.1fh", hours)
    }
}
```

- [ ] **Step 3: 更新 HealthRulesTests**

```swift
// Tests/DakaCoreTests/HealthRulesTests.swift
import XCTest
@testable import DakaCore

final class HealthRulesTests: XCTestCase {
    private let cal = TestTime.calendar

    private var schedule: Settings {
        Settings(enabled: true, workdays: [2, 3, 4, 5, 6],
                 workStartTime: "09:00", workDurationHours: 9, flexMinutes: 30)
    }

    private func status(now: Date, record: DayHealthRecord = DayHealthRecord(),
                        health: HealthSettings = .default, skipped: Bool = false) -> HealthStatus {
        HealthRules.status(health: health, schedule: schedule, record: record,
                           skipped: skipped, now: now, calendar: cal)
    }

    func testDueAfterIntervalWithinWorkWindow() {
        let s = status(now: TestTime.date(2026, 9, 14, 10, 30))
        XCTAssertTrue(s.active)
        XCTAssertTrue(s.waterDue)
        XCTAssertTrue(s.movementDue)
        XCTAssertEqual(s.minutesSinceDrink, 90)
    }

    func testNotDueBeforeInterval() {
        let s = status(now: TestTime.date(2026, 9, 14, 9, 30))
        XCTAssertTrue(s.active)
        XCTAssertFalse(s.waterDue)
        XCTAssertFalse(s.movementDue)
    }

    func testDrinkingResetsTimer() {
        let record = DayHealthRecord(drinks: [TestTime.date(2026, 9, 14, 10, 15)])
        let s = status(now: TestTime.date(2026, 9, 14, 10, 30), record: record)
        XCTAssertEqual(s.cups, 1)
        XCTAssertEqual(s.minutesSinceDrink, 15)
        XCTAssertFalse(s.waterDue)
    }

    func testOutsideWindowInactive() {
        let s = status(now: TestTime.date(2026, 9, 14, 8, 0))
        XCTAssertFalse(s.active)
    }

    func testAfterWorkDurationInactive() {
        let s = status(now: TestTime.date(2026, 9, 14, 18, 30))
        XCTAssertFalse(s.active)
    }

    func testWeekendInactive() {
        let s = status(now: TestTime.date(2026, 9, 19, 10, 30))
        XCTAssertFalse(s.active)
    }

    func testSkippedInactive() {
        let s = status(now: TestTime.date(2026, 9, 14, 10, 30), skipped: true)
        XCTAssertFalse(s.active)
    }

    func testDisabledToolDoesNotRemind() {
        var health = HealthSettings.default
        health.waterEnabled = false
        let s = status(now: TestTime.date(2026, 9, 14, 10, 30), health: health)
        XCTAssertFalse(s.waterDue)
        XCTAssertTrue(s.movementDue)
    }

    func testInvalidTimesInactive() {
        var s = schedule
        s.workStartTime = "oops"
        let result = HealthRules.status(health: .default, schedule: s, record: DayHealthRecord(),
                                        skipped: false, now: TestTime.date(2026, 9, 14, 10, 30), calendar: cal)
        XCTAssertFalse(result.active)
    }
}
```

- [ ] **Step 4: 更新 HealthRules**

```swift
// Sources/DakaCore/HealthRules.swift
// 修改 windowStart/windowEnd 逻辑
let windowStart = DakaDate.date(on: now, at: schedule.workStartTime, calendar: calendar)
let windowEnd = windowStart?.addingTimeInterval(schedule.workDuration)
```

- [ ] **Step 5: 更新 PunchTargetTests**

```swift
// Tests/DakaCoreTests/PunchTargetTests.swift
import XCTest
@testable import DakaCore

final class PunchTargetTests: XCTestCase {
    private let cal = TestTime.calendar

    private func resolve(_ record: DayRecord, now: Date, settings: Settings = .default) -> PunchTask {
        PunchTarget.resolve(record: record, now: now, settings: settings, calendar: cal)
    }

    func testMorningNotDoneTargetsMorning() {
        XCTAssertEqual(resolve(DayRecord(), now: TestTime.date(2026, 9, 16, 9, 0)), .morning)
    }

    func testMorningDoneEveningIncompleteTargetsEvening() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)])
        XCTAssertEqual(resolve(record, now: TestTime.date(2026, 9, 16, 9, 5)), .evening)
    }

    func testBothDoneBeforeNoonTargetsMorning() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 16, 18, 0)])
        XCTAssertEqual(resolve(record, now: TestTime.date(2026, 9, 16, 9, 30)), .morning)
    }

    func testBothDoneAtNoonTargetsEvening() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 16, 18, 0)])
        XCTAssertEqual(resolve(record, now: TestTime.date(2026, 9, 16, 12, 0)), .evening)
    }

    func testEarlyEveningPunchStillTargetsEvening() {
        let record = DayRecord(morningPunches: [TestTime.date(2026, 9, 16, 9, 0)],
                               eveningPunches: [TestTime.date(2026, 9, 16, 17, 0)])
        XCTAssertEqual(resolve(record, now: TestTime.date(2026, 9, 16, 18, 10)), .evening)
    }
}
```

- [ ] **Step 6: 更新 PunchTarget**

```swift
// Sources/DakaCore/PunchTarget.swift
public enum PunchTarget {
    public static func resolve(record: DayRecord,
                               now: Date,
                               settings: Settings,
                               calendar: Calendar = .current) -> PunchTask {
        if !record.morningDone { return .morning }
        if !AttendanceRule.isEveningComplete(record, settings: settings, on: now, calendar: calendar) { return .evening }
        let hour = calendar.component(.hour, from: now)
        return hour < 12 ? .morning : .evening
    }
}
```

- [ ] **Step 7: 更新 PunchFeedbackTests**

```swift
// Tests/DakaCoreTests/PunchFeedbackTests.swift
// 将 minWorkDurationHours=8 改为 workDurationHours=8
private func text(_ task: PunchTask, record: DayRecord, punchedAt: Date, hours: Double = 8) -> String? {
    var settings = Settings.default
    settings.workDurationHours = hours
    return PunchFeedback.text(task: task, record: record, settings: settings,
                              punchedAt: punchedAt, calendar: cal)
}
// 其余断言不变（contains("还差 1 小时"), contains("16:00")等）
```

- [ ] **Step 8: 更新 PunchFeedback**

```swift
// Sources/DakaCore/PunchFeedback.swift
import Foundation

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
            if AttendanceRule.isEveningComplete(record, settings: settings, on: punchedAt, calendar: calendar) {
                return nil
            }
            let time = timeText(punchedAt, calendar: calendar)
            guard let morning = record.morningDoneAt else {
                return "已记录 \(time)；今天还没有上班打卡，需先打上班卡，才能计算下班时间。"
            }
            guard let leave = AttendanceRule.expectedLeave(record, settings: settings, on: punchedAt, calendar: calendar) else {
                return "已记录 \(time)；无法计算应下班时间。"
            }
            let remaining = leave.timeIntervalSince(punchedAt)
            let hours = settings.workDurationHours
            return "已记录 \(time)；距上班满 \(hoursText(hours)) 小时（应 \(timeText(leave, calendar: calendar)) 下班）还差 \(remainingText(remaining))，满后自动完成。"
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
        if h > 0 { return m > 0 ? "\(h) 小时 \(m) 分钟" : "\(h) 小时" }
        return "\(m) 分钟"
    }

    private static func timeText(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
```

- [ ] **Step 9: 更新 StatisticsTests（今天无上班卡场景）**

```swift
// Tests/DakaCoreTests/StatisticsTests.swift
// 替换 testTodayIncompleteAfterDeadlineBreaksStreakAndCountsMissed 为：
func testTodayMorningDonePastLeaveIncomplete() {
    let lateNow = TestTime.date(2026, 9, 16, 19, 0)
    let recs = records([
        (TestTime.date(2026, 9, 15), true, true, nil, nil, false),
        (TestTime.date(2026, 9, 16), true, true,
         TestTime.date(2026, 9, 16, 9, 0), TestTime.date(2026, 9, 16, 17, 30), false)
    ])
    let s = Statistics.compute(records: recs, settings: .default, now: lateNow, rangeDays: 7, calendar: cal)
    XCTAssertEqual(s.currentStreak, 0)
    XCTAssertTrue(s.missedDays >= 1)
}

func testTodayWithoutMorningPunchIsInProgress() {
    let lateNow = TestTime.date(2026, 9, 16, 19, 0)
    let recs = records([
        (TestTime.date(2026, 9, 15), true, true, nil, nil, false)
    ])
    let s = Statistics.compute(records: recs, settings: .default, now: lateNow, rangeDays: 7, calendar: cal)
    XCTAssertEqual(s.currentStreak, 1)
    XCTAssertEqual(s.missedDays, 3)
}
```

- [ ] **Step 10: 更新 Statistics**

```swift
// Sources/DakaCore/Statistics.swift
// 替换完整 compute 函数，使用 AttendanceRule
```

完整 Statistics.swift 已在讨论中。关键变更点：
- `completed` 使用 `AttendanceRule.effectiveEveningPunch`
- `effectiveEvening` 使用 `AttendanceRule.effectiveEveningPunch`
- `todayInProgress` 使用 `AttendanceRule.expectedLeave`
- 缺卡逻辑：今天有上班卡但过 expectedLeave → 缺卡；今天无上班卡 → 进行中

- [ ] **Step 11: 运行全部 DakaCore 测试**

```bash
swift test
```

- [ ] **Step 12: 提交**

```bash
git add -A
git commit -m "refactor: switch DakaCore consumers to AttendanceRule"
```

---

### Task 5: 清理 Settings 旧字段 & 删除 PunchRules

**Files:**
- Modify: `Sources/DakaCore/Models.swift`
- Modify: `Tests/DakaCoreTests/SettingsTests.swift`
- Delete: `Sources/DakaCore/PunchRules.swift`
- Delete: `Tests/DakaCoreTests/PunchRulesTests.swift`

- [ ] **Step 1: 更新 SettingsTests**

在 SettingsTests 末尾追加：

```swift
func testEncodeWritesOnlyNewKeys() throws {
    let data = try JSONEncoder().encode(Settings.default)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    XCTAssertNil(json["morningWindowStart"])
    XCTAssertNil(json["eveningWindowStart"])
    XCTAssertNil(json["minWorkDurationHours"])
    XCTAssertNotNil(json["workStartTime"])
    XCTAssertNotNil(json["workDurationHours"])
    XCTAssertNotNil(json["flexMinutes"])
}
```

- [ ] **Step 2: 从 Settings 移除旧存储属性**

```swift
// Models.swift - Settings 最终形态
public struct Settings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var workdays: Set<Int>
    public var workStartTime: String
    public var workDurationHours: Double
    public var flexMinutes: Int
    public var reminderIntervalSeconds: TimeInterval

    public init(enabled: Bool = true,
                workdays: Set<Int> = [2, 3, 4, 5, 6],
                workStartTime: String = "09:00",
                workDurationHours: Double = 9,
                flexMinutes: Int = 30,
                reminderIntervalSeconds: TimeInterval = 120) {
        self.enabled = enabled
        self.workdays = workdays
        self.workStartTime = workStartTime
        self.workDurationHours = workDurationHours
        self.flexMinutes = flexMinutes
        self.reminderIntervalSeconds = reminderIntervalSeconds
    }

    public var effectiveReminderIntervalSeconds: TimeInterval { max(30, reminderIntervalSeconds) }
    public var workDuration: TimeInterval { max(0.5, workDurationHours) * 3600 }
    public var flexDuration: TimeInterval { TimeInterval(max(0, flexMinutes) * 60) }

    public static let `default` = Settings()

    private enum CodingKeys: String, CodingKey {
        case enabled, workdays, workStartTime, workDurationHours, flexMinutes, reminderIntervalSeconds
        case morningWindowStart, morningDeadline, minWorkDurationHours
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings.default
        self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        self.workdays = try c.decodeIfPresent(Set<Int>.self, forKey: .workdays) ?? d.workdays
        if let v = try c.decodeIfPresent(String.self, forKey: .workStartTime) {
            self.workStartTime = v
        } else if let old = try c.decodeIfPresent(String.self, forKey: .morningWindowStart) {
            self.workStartTime = old
        } else {
            self.workStartTime = d.workStartTime
        }
        if let v = try c.decodeIfPresent(Double.self, forKey: .workDurationHours) {
            self.workDurationHours = v
        } else if let old = try c.decodeIfPresent(Double.self, forKey: .minWorkDurationHours) {
            self.workDurationHours = old
        } else {
            self.workDurationHours = d.workDurationHours
        }
        if let v = try c.decodeIfPresent(Int.self, forKey: .flexMinutes) {
            self.flexMinutes = v
        } else if let s = try c.decodeIfPresent(String.self, forKey: .morningWindowStart),
                  let e = try c.decodeIfPresent(String.self, forKey: .morningDeadline),
                  let sc = DakaDate.timeComponents(s),
                  let ec = DakaDate.timeComponents(e) {
            self.flexMinutes = max(0, (ec.hour * 60 + ec.minute) - (sc.hour * 60 + sc.minute))
        } else {
            self.flexMinutes = d.flexMinutes
        }
        self.reminderIntervalSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .reminderIntervalSeconds) ?? d.reminderIntervalSeconds
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(workdays, forKey: .workdays)
        try c.encode(workStartTime, forKey: .workStartTime)
        try c.encode(workDurationHours, forKey: .workDurationHours)
        try c.encode(flexMinutes, forKey: .flexMinutes)
        try c.encode(reminderIntervalSeconds, forKey: .reminderIntervalSeconds)
    }
}
```

- [ ] **Step 3: 删除 PunchRules.swift**

```bash
rm Sources/DakaCore/PunchRules.swift
rm Tests/DakaCoreTests/PunchRulesTests.swift
```

- [ ] **Step 4: 运行测试**

```bash
swift test
```

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "refactor: remove old Settings fields and PunchRules"
```

---

### Task 6: Scheduler 交付 record + LaunchAgentPlist 3 时点

**Files:**
- Modify: `Sources/DakaCore/Scheduler.swift`
- Modify: `Sources/DakaCore/LaunchAgentPlist.swift`
- Modify: `Tests/DakaCoreTests/SchedulerTests.swift`
- Modify: `Tests/DakaCoreTests/LaunchAgentPlistTests.swift`

- [ ] **Step 1: 更新 ReminderPresenting 协议**

```swift
// Scheduler.swift
public protocol ReminderPresenting: AnyObject {
    func showHard(tasks: [PunchTask], settings: Settings, record: DayRecord, now: Date)
    func refresh(settings: Settings, record: DayRecord, now: Date)
    func hide()
}
```

- [ ] **Step 2: Scheduler.tick/apply 传递 record**

```swift
// Scheduler.swift - tick 修改
public func tick() {
    let now = clock.now
    let dayKey = DakaDate.key(for: now, calendar: calendar)
    let dayChanged = dayKey != lastDayKey
    lastDayKey = dayKey
    let settings = store.data.settings
    let record = store.record(for: now, calendar: calendar)
    let pending = evaluator.pendingReminders(now: now, settings: settings, record: record, calendar: calendar)
    apply(state: ReminderState(pending: pending), settings: settings, record: record, now: now, dayChanged: dayChanged)
}

private func apply(state newState: ReminderState, settings: Settings, record: DayRecord, now: Date, dayChanged: Bool) {
    state = newState
    let changed = newState != lastState
    if changed {
        lastState = newState
        if !newState.pending.isEmpty {
            presenter?.showHard(tasks: newState.pending, settings: settings, record: record, now: now)
        } else {
            presenter?.hide()
        }
    } else if !newState.isEmpty {
        presenter?.refresh(settings: settings, record: record, now: now)
    }
    if changed || dayChanged {
        onStateChange?(newState)
    }
}
```

- [ ] **Step 3: 更新 SchedulerTests SpyPresenter**

```swift
// SchedulerTests.swift
final class SpyPresenter: ReminderPresenting {
    var lastHard: [PunchTask]?
    var hideCount = 0
    var refreshCount = 0

    func showHard(tasks: [PunchTask], settings: Settings, record: DayRecord, now: Date) { lastHard = tasks }
    func refresh(settings: Settings, record: DayRecord, now: Date) { refreshCount += 1 }
    func hide() { lastHard = nil; hideCount += 1 }
}
```

- [ ] **Step 4: 重写 SchedulerTests evening 场景**

```swift
func testMorningPunchedShowsEveningOnlyAtLeave() throws {
    let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 0))
    try store.mark(.morning, at: TestTime.date(2026, 9, 14, 9, 0), calendar: TestTime.calendar)
    clock.now = TestTime.date(2026, 9, 14, 17, 59)
    scheduler.tick()
    XCTAssertNil(presenter.lastHard)
    clock.now = TestTime.date(2026, 9, 14, 18, 0)
    scheduler.tick()
    XCTAssertEqual(presenter.lastHard, [.evening])
}

func testLatePunchPushesEveningReminder() throws {
    let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 9, 16))
    try store.mark(.morning, at: TestTime.date(2026, 9, 14, 9, 16), calendar: TestTime.calendar)
    clock.now = TestTime.date(2026, 9, 14, 18, 10)
    scheduler.tick()
    XCTAssertNil(presenter.lastHard)
    clock.now = TestTime.date(2026, 9, 14, 18, 16)
    scheduler.tick()
    XCTAssertEqual(presenter.lastHard, [.evening])
}

func testNoMorningNeverPresentsEvening() {
    let (scheduler, _, _, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 20, 0))
    scheduler.tick()
    XCTAssertEqual(presenter.lastHard, [.morning])
}

func testEarlyEveningPunchKeepsReminding() throws {
    let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 18, 10))
    try store.mark(.morning, at: TestTime.date(2026, 9, 14, 9, 0), calendar: TestTime.calendar)
    try store.mark(.evening, at: TestTime.date(2026, 9, 14, 17, 30), calendar: TestTime.calendar)
    scheduler.tick()
    XCTAssertEqual(presenter.lastHard, [.evening])
}

func testQualifyingEveningPunchClearsReminder() throws {
    let (scheduler, clock, store, presenter) = makeScheduler(now: TestTime.date(2026, 9, 14, 18, 10))
    try store.mark(.morning, at: TestTime.date(2026, 9, 14, 9, 0), calendar: TestTime.calendar)
    try store.mark(.evening, at: TestTime.date(2026, 9, 14, 18, 10), calendar: TestTime.calendar)
    scheduler.tick()
    XCTAssertNil(presenter.lastHard)
}
```

- [ ] **Step 5: 更新 LaunchAgentPlist**

```swift
// LaunchAgentPlist.swift
public enum LaunchAgentPlist {
    public static let label = "com.xue.daka.schedule"

    public static func make(times: [String], bundleID: String) -> String {
        var intervals: [[String: Int]] = []
        for hhmm in times {
            guard let time = DakaDate.timeComponents(hhmm) else { continue }
            let entry = ["Hour": time.hour, "Minute": time.minute]
            if !intervals.contains(entry) { intervals.append(entry) }
        }
        var plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/sh", "-c",
                                 "/usr/bin/pgrep -u \"$(id -u)\" -x Daka >/dev/null 2>&1 || /usr/bin/open -b \(bundleID) --args --background"]
        ]
        if !intervals.isEmpty { plist["StartCalendarInterval"] = intervals }
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
              let xml = String(data: data, encoding: .utf8) else { return "" }
        return xml
    }
}
```

- [ ] **Step 6: 更新 LaunchAgentPlistTests**

```swift
private func makePlist(_ times: [String] = ["09:00", "09:30", "18:00"]) -> String {
    LaunchAgentPlist.make(times: times, bundleID: "com.xue.daka")
}

func testThreeCalendarTimes() throws {
    let entries = try intervals(makePlist())
    XCTAssertEqual(entries.count, 3)
    XCTAssertTrue(entries.contains(["Hour": 9, "Minute": 0]))
    XCTAssertTrue(entries.contains(["Hour": 9, "Minute": 30]))
    XCTAssertTrue(entries.contains(["Hour": 18, "Minute": 0]))
}

func testInvalidTimesAreSkipped() throws {
    XCTAssertEqual(try intervals(makePlist(["09:00", "oops"])).count, 2)
}
```

- [ ] **Step 7: 运行测试**

```bash
swift test
```

- [ ] **Step 8: 提交**

```bash
git add -A
git commit -m "refactor: Scheduler passes record to presenter; LaunchAgentPlist uses times array"
```

---

### Task 7: Daka 应用层适配

**Files:**
- Modify: `Sources/Daka/AppModel.swift`
- Modify: `Sources/Daka/MenuBarView.swift`
- Modify: `Sources/Daka/PunchButton.swift`
- Modify: `Sources/Daka/SettingsPages.swift`
- Modify: `Sources/Daka/SettingsPage.swift`
- Modify: `Sources/Daka/ControlCenterView.swift`
- Modify: `Sources/Daka/OverlayView.swift`
- Modify: `Sources/Daka/ReminderController.swift`
- Modify: `Sources/Daka/ScheduledLaunchManager.swift`

- [ ] **Step 1: SettingsPage 移除 .attendance**

```swift
// SettingsPage.swift
enum SettingsPage: String, CaseIterable, Identifiable {
    case schedule, workdays, system

    var title: String {
        switch self {
        case .schedule: return "考勤规则"
        case .workdays: return "工作日"
        case .system: return "系统与启动"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: return "clock"
        case .workdays: return "calendar"
        case .system: return "gearshape"
        }
    }
}
```

- [ ] **Step 2: ControlCenterView 移除 .attendance case**

```swift
// ControlCenterView.swift
case .settings(.schedule):
    ScheduleSettingsView(model: model)
case .settings(.workdays):
    WorkdaySettingsView(model: model)
case .settings(.system):
    SystemSettingsView(model: model)
```

- [ ] **Step 3: SettingsPages 重写 ScheduleSettingsView，删除 AttendanceSettingsView**

```swift
// SettingsPages.swift
struct ScheduleSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Toggle("启用提醒", isOn: Binding(get: { model.settings.enabled },
                                            set: { model.setEnabled($0) }))
            Section("考勤规则") {
                DatePicker("上班时间", selection: bound(\.workStartTime, model.updateWorkStart),
                           displayedComponents: .hourAndMinute)
                Stepper(value: Binding(get: { model.settings.flexMinutes },
                                       set: { model.setFlexMinutes($0) }),
                        in: 0...120, step: 5) {
                    Text("弹性时间：\(model.settings.flexMinutes) 分钟")
                }
                Stepper(value: Binding(get: { model.settings.workDurationHours },
                                       set: { model.setWorkDurationHours($0) }),
                        in: 0.5...12, step: 0.5) {
                    Text("工作时长：\(settingsHoursText(model.settings.workDurationHours)) 小时")
                }
                Text("下班提醒随上班卡时间浮动：早到按上班时间算，晚打顺延下班。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("重复提醒") {
                Stepper(value: Binding(get: { Int(model.settings.reminderIntervalSeconds / 60) },
                                       set: { model.setReminderIntervalMinutes($0) }),
                        in: 1...60) {
                    Text("每隔 \(Int(model.settings.reminderIntervalSeconds / 60)) 分钟重复提醒")
                }
                Text("进入打卡窗口即全屏提醒，完成对应打卡后停止。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func bound(_ keyPath: KeyPath<DakaCore.Settings, String>,
                       _ update: @escaping (String) -> Void) -> Binding<Date> {
        Binding(get: { settingsDateFrom(model.settings[keyPath: keyPath], now: model.now) },
                set: { update(settingsHHMM(from: $0)) })
    }
}

// 删除 AttendanceSettingsView
```

- [ ] **Step 4: AppModel 更新 setters**

```swift
// AppModel.swift
var isEveningComplete: Bool {
    AttendanceRule.isEveningComplete(record, settings: settings, on: now)
}

func updateWorkStart(_ hhmm: String) { updateSettings { $0.workStartTime = hhmm } }
func setFlexMinutes(_ minutes: Int) { updateSettings { $0.flexMinutes = max(0, minutes) } }
func setWorkDurationHours(_ hours: Double) { updateSettings { $0.workDurationHours = max(0.5, hours) } }
func setReminderIntervalMinutes(_ minutes: Int) {
    let clamped = min(60, max(1, minutes))
    updateSettings { $0.reminderIntervalSeconds = TimeInterval(clamped * 60) }
}
// 删除 updateMorningStart/Deadline/EveningStart/Deadline, setMinWorkHours
```

- [ ] **Step 5: MenuBarView 更新**

```swift
// MenuBarView.swift
PunchButton(task: PunchTarget.resolve(record: model.record, now: model.now, settings: model.settings),
            record: model.record,
            nowProvider: { model.now },
            settings: model.settings) { task in
    model.punch(task)
}
```

- [ ] **Step 6: PunchButton 替换 minWorkDuration 为 settings**

```swift
// PunchButton.swift
struct PunchButton: View {
    let task: PunchTask
    let record: DayRecord
    let nowProvider: () -> Date
    let settings: DakaCore.Settings
    let onComplete: (PunchTask) -> Void
    ...
    private var isEveningComplete: Bool {
        AttendanceRule.isEveningComplete(record, settings: settings, on: nowProvider())
    }
    private var ringFraction: CGFloat {
        if isPressing { return press.progress }
        return CGFloat(WorkProgress.fraction(record, now: nowProvider(), settings: settings))
    }
    private var centerLines: [String] {
        ...
        if let elapsed = WorkProgress.elapsed(record, now: nowProvider(), settings: settings) { ... }
        ...
    }
}
```

- [ ] **Step 7: OverlayView overdueText + OverlayModel**

```swift
// OverlayView.swift
@MainActor
final class OverlayModel: ObservableObject {
    @Published var tasks: [PunchTask] = []
    @Published var settings: DakaCore.Settings = .default
    @Published var record: DayRecord = DayRecord()
    @Published var now: Date = Date()
    @Published var message: String?
    @Published var healthAlerts: [HealthAlert] = []
    var onPunch: (PunchTask) -> Void = { _ in }
    var onWater: () -> Void = {}
    var onMovement: () -> Void = {}
}

private func overdueText(for task: PunchTask) -> String? {
    let due: Date?
    switch task {
    case .morning: due = AttendanceRule.windowEnd(model.settings, on: model.now)
    case .evening: due = AttendanceRule.expectedLeave(model.record, settings: model.settings, on: model.now)
    }
    guard let due, model.now > due else { return nil }
    let seconds = Int(model.now.timeIntervalSince(due))
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    if hours > 0 { return "已欠 \(hours) 小时 \(minutes) 分" }
    return "已欠 \(minutes) 分"
}
```

- [ ] **Step 8: ReminderController showHard/refresh 增加 record**

```swift
// ReminderController.swift
func showHard(tasks: [PunchTask], settings: DakaCore.Settings, record: DayRecord, now: Date) {
    ...
    currentTasks = tasks
    overlayModel.tasks = tasks
    overlayModel.settings = settings
    overlayModel.record = record
    overlayModel.now = now
    ...
}

func refresh(settings: DakaCore.Settings, record: DayRecord, now: Date) {
    overlayModel.settings = settings
    overlayModel.record = record
    overlayModel.now = now
    ...
}
```

- [ ] **Step 9: ScheduledLaunchManager**

```swift
// ScheduledLaunchManager.swift
private static func performInstall(settings: Settings) -> InstallResult {
    ...
    let base = DakaDate.timeComponents(settings.workStartTime)
    let baseMin = (base?.hour ?? 9) * 60 + (base?.minute ?? 0)
    let flexMin = baseMin + max(0, settings.flexMinutes)
    let leaveMin = baseMin + Int((settings.workDurationHours * 60).rounded())
    func hhmm(_ m: Int) -> String { String(format: "%02d:%02d", (m % 1440) / 60, (m % 1440) % 60) }
    let times = [settings.workStartTime, hhmm(flexMin), hhmm(leaveMin)]

    guard times.contains(where: { DakaDate.timeComponents($0) != nil }) else { return .skipped }

    let plist = LaunchAgentPlist.make(times: times, bundleID: bundleID)
    ...
}
```

- [ ] **Step 10: 编译检查**

```bash
swift build -c release
```

- [ ] **Step 11: 运行全部测试**

```bash
swift test
```

- [ ] **Step 12: 提交**

```bash
git add -A
git commit -m "refactor: adapt Daka app target to attendance-rule driven settings"
```

---

### Task 8: 文档与验证清单

**Files:**
- Modify: `docs/verification.md`
- Modify: `README.md`

- [ ] **Step 1: 更新 verification.md**

```markdown
# Daka 手动验证清单

## 基础
- [ ] 启动后菜单栏出现图标，Dock 也出现应用图标。
- [ ] 菜单栏面板：右上角有「控制中心」图标，下面是今日状态与打卡按钮。

## 考勤规则驱动动态下班时间
- [ ] 上班窗口：09:00 触发全屏提醒；08:59 不触发。
- [ ] 弹性时间：设置页「弹性时间」改为 15 分钟后，09:14 前上班卡正常，09:15 起推迟。
- [ ] 早到（如 08:40 打卡）→ 下班时间 18:00，18:00 开始提醒下班。
- [ ] 准点（09:00 打卡）→ 下班时间 18:00，18:00 开始提醒下班。
- [ ] 弹性内（09:16 打卡）→ 下班时间 18:16，18:16 开始提醒下班。
- [ ] 晚到（10:00 打卡）→ 下班时间 19:00，19:00 开始提醒下班。
- [ ] 提前下班（18:10 打卡 < 18:16）→ 下班未完成，继续提醒。
- [ ] 满足工时后下班 → 全屏消失。
- [ ] 未打上班卡 → 只催上班，不催下班。
- [ ] 「工作时长」stepper 改为 8 小时 → 下班时间相应提前。
- [ ] 设置页「考勤规则」含上班时间、弹性时间、工作时长三项。

## 定点启动
- [ ] `launchctl print gui/$(id -u)/com.xue.daka.schedule` 能看到三个 `StartCalendarInterval`（09:00 / 09:30 / 18:00）。

## 健康提醒
- [ ] 09:00–18:00 内喝水/走动到点触发全屏；18:01 不触发。
```

- [ ] **Step 2: 更新 README.md**

```markdown
- **考勤规则驱动**：上班时间 / 工作时长 / 弹性时间三参数配置，下班提醒随上班卡时间浮动。
- **默认时间**：上班时间 09:00，工作时长 9 小时，弹性 30 分钟（可在「设置 → 考勤规则」修改）。
```

更新 data.json 示例为新字段：

```jsonc
{
  "settings": {
    "enabled": true,
    "workdays": [2, 3, 4, 5, 6],
    "workStartTime": "09:00",
    "workDurationHours": 9,
    "flexMinutes": 30,
    "reminderIntervalSeconds": 120
  }
}
```

- [ ] **Step 3: 提交**

```bash
git add docs/verification.md README.md
git commit -m "docs: update verification and README for attendance-rule driven settings"
```
