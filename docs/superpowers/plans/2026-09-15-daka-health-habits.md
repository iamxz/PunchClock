# Health Habits (Water + Movement) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `喝水` (water) and `久坐/走动` (movement) desktop-pet health tools: manual logging, interval reminders following work hours, pet face + speech-bubble reactions, and 7/14/30-day statistics.

**Architecture:** Pure logic and persistence live in `DakaCore` (`HealthModels`, `HealthRules`, `HealthStore`, `HealthStatistics`) fully unit-testable with an injected calendar/clock. The AppKit/SwiftUI layer in `Daka` wires an independent `HealthReminderController` timer to `AppModel`, `GentleNotifier`, a floating `PetSpeechBubble` window, and two tool detail views in the control center. Punch behavior and `data.json` are untouched.

**Tech Stack:** Swift 5.10, SwiftUI, Swift Charts, AppKit, XCTest, SwiftPM (`swift test`).

---

## File Structure

**Create (DakaCore — pure logic):**
- `Sources/DakaCore/HealthModels.swift` — `HealthSettings`, `DayHealthRecord`, `HealthData`, `HealthLogKind`
- `Sources/DakaCore/HealthRules.swift` — `HealthStatus`, `HealthRules.status(...)`
- `Sources/DakaCore/HealthStore.swift` — atomic persistence of `health.json`
- `Sources/DakaCore/HealthStatistics.swift` — range aggregation + streaks

**Create (Daka — app/UI):**
- `Sources/Daka/HealthReminderController.swift` — timer, notifications, pet speech triggers
- `Sources/Daka/HealthToolViews.swift` — `WaterToolView`, `MovementToolView`, shared metric card/chart
- `Sources/Daka/PetSpeechBubble.swift` — bubble SwiftUI view

**Create (tests):**
- `Tests/DakaCoreTests/HealthRulesTests.swift`
- `Tests/DakaCoreTests/HealthStoreTests.swift`
- `Tests/DakaCoreTests/HealthStatisticsTests.swift`

**Modify:**
- `Sources/DakaCore/PetMood.swift` — add `.thirsty`/`.restless`, `health` param
- `Tests/DakaCoreTests/PetMoodTests.swift` — add health-mood tests
- `Sources/Daka/GentleNotifier.swift` — generic `notify(id:title:body:)`
- `Sources/Daka/AppModel.swift` — health store state, log/settings methods, `petSpeech`, start controller
- `Sources/Daka/PetWindowController.swift` — speech-bubble window
- `Sources/Daka/PetView.swift` — health-aware mood
- `Sources/Daka/ControlCenterView.swift` — route `.water`/`.sedentary`, sidebar summaries
- `Sources/Daka/ToolPanelView.swift` — real summaries + quick log buttons
- `README.md`, `docs/verification.md` — docs

Note: `ToolID.sedentary` keeps its raw value and title "久坐"; the UI copy for it is "走动".

---

### Task 1: Health data models

**Files:**
- Create: `Sources/DakaCore/HealthModels.swift`
- Test: `Tests/DakaCoreTests/HealthStoreTests.swift` (created for real in Task 3; this task is validated by `swift build` and by the decoding behavior used in later tasks)

- [ ] **Step 1: Write the models**

Create `Sources/DakaCore/HealthModels.swift`:

```swift
import Foundation

public struct HealthSettings: Codable, Equatable, Sendable {
    public var waterEnabled: Bool
    public var waterGoalCups: Int
    public var waterIntervalMinutes: Int
    public var movementEnabled: Bool
    public var movementGoalCount: Int
    public var movementIntervalMinutes: Int

    public init(waterEnabled: Bool = true,
                waterGoalCups: Int = 8,
                waterIntervalMinutes: Int = 60,
                movementEnabled: Bool = true,
                movementGoalCount: Int = 8,
                movementIntervalMinutes: Int = 60) {
        self.waterEnabled = waterEnabled
        self.waterGoalCups = waterGoalCups
        self.waterIntervalMinutes = waterIntervalMinutes
        self.movementEnabled = movementEnabled
        self.movementGoalCount = movementGoalCount
        self.movementIntervalMinutes = movementIntervalMinutes
    }

    public static let `default` = HealthSettings()

    /// 间隔下限 15 分钟，避免异常配置刷屏。
    public var effectiveWaterIntervalMinutes: Int { max(15, waterIntervalMinutes) }
    public var effectiveMovementIntervalMinutes: Int { max(15, movementIntervalMinutes) }

    private enum CodingKeys: String, CodingKey {
        case waterEnabled, waterGoalCups, waterIntervalMinutes
        case movementEnabled, movementGoalCount, movementIntervalMinutes
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HealthSettings.default
        self.waterEnabled = try c.decodeIfPresent(Bool.self, forKey: .waterEnabled) ?? d.waterEnabled
        self.waterGoalCups = try c.decodeIfPresent(Int.self, forKey: .waterGoalCups) ?? d.waterGoalCups
        self.waterIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .waterIntervalMinutes) ?? d.waterIntervalMinutes
        self.movementEnabled = try c.decodeIfPresent(Bool.self, forKey: .movementEnabled) ?? d.movementEnabled
        self.movementGoalCount = try c.decodeIfPresent(Int.self, forKey: .movementGoalCount) ?? d.movementGoalCount
        self.movementIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .movementIntervalMinutes) ?? d.movementIntervalMinutes
    }
}

public struct DayHealthRecord: Codable, Equatable, Sendable {
    public var drinks: [Date]
    public var stands: [Date]

    public init(drinks: [Date] = [], stands: [Date] = []) {
        self.drinks = drinks
        self.stands = stands
    }

    public var cups: Int { drinks.count }
    public var standCount: Int { stands.count }
    public var lastDrinkAt: Date? { drinks.max() }
    public var lastStandAt: Date? { stands.max() }
}

public struct HealthData: Codable, Equatable, Sendable {
    public var settings: HealthSettings
    public var records: [String: DayHealthRecord]

    public init(settings: HealthSettings = .default,
                records: [String: DayHealthRecord] = [:]) {
        self.settings = settings
        self.records = records
    }
}

public enum HealthLogKind: String, Codable, Sendable {
    case water
    case movement
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds (no new tests yet; models compile).

- [ ] **Step 3: Commit**

```bash
git add Sources/DakaCore/HealthModels.swift
git commit -m "feat: add health habit data models"
```

---

### Task 2: Health rules (pure evaluation)

**Files:**
- Create: `Sources/DakaCore/HealthRules.swift`
- Test: `Tests/DakaCoreTests/HealthRulesTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/DakaCoreTests/HealthRulesTests.swift`:

```swift
import XCTest
@testable import DakaCore

final class HealthRulesTests: XCTestCase {
    private let cal = TestTime.calendar

    private var schedule: Settings {
        Settings(enabled: true, workdays: [2, 3, 4, 5, 6],
                 morningWindowStart: "09:00", morningDeadline: "09:30",
                 eveningWindowStart: "18:00", eveningDeadline: "18:30")
    }

    private func status(now: Date,
                        record: DayHealthRecord = DayHealthRecord(),
                        health: HealthSettings = .default,
                        skipped: Bool = false) -> HealthStatus {
        HealthRules.status(health: health, schedule: schedule, record: record,
                           skipped: skipped, now: now, calendar: cal)
    }

    // 2026-09-14 为周一
    func testDueAfterIntervalWithinWorkWindow() {
        let s = status(now: TestTime.date(2026, 9, 14, 10, 30))
        XCTAssertTrue(s.active)
        XCTAssertTrue(s.waterDue)      // 09:00 起 90 分钟 >= 60
        XCTAssertTrue(s.movementDue)
        XCTAssertEqual(s.minutesSinceDrink, 90)
    }

    func testNotDueBeforeInterval() {
        let s = status(now: TestTime.date(2026, 9, 14, 9, 30))
        XCTAssertTrue(s.active)
        XCTAssertFalse(s.waterDue)     // 30 分钟 < 60
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
        XCTAssertFalse(s.waterDue)
        XCTAssertFalse(s.movementDue)
    }

    func testWeekendInactive() {
        let s = status(now: TestTime.date(2026, 9, 19, 10, 30)) // 周六
        XCTAssertFalse(s.active)
        XCTAssertFalse(s.waterDue)
    }

    func testSkippedInactive() {
        let s = status(now: TestTime.date(2026, 9, 14, 10, 30), skipped: true)
        XCTAssertFalse(s.active)
        XCTAssertFalse(s.waterDue)
    }

    func testDisabledToolDoesNotRemind() {
        var health = HealthSettings.default
        health.waterEnabled = false
        let s = status(now: TestTime.date(2026, 9, 14, 10, 30), health: health)
        XCTAssertFalse(s.waterDue)
        XCTAssertTrue(s.movementDue)
    }

    func testCustomInterval() {
        var health = HealthSettings.default
        health.waterIntervalMinutes = 30
        let s = status(now: TestTime.date(2026, 9, 14, 9, 30), health: health)
        XCTAssertTrue(s.waterDue)      // 30 分钟 >= 30
    }

    func testEffectiveIntervalFloor() {
        var health = HealthSettings.default
        health.waterIntervalMinutes = 1
        XCTAssertEqual(health.effectiveWaterIntervalMinutes, 15)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HealthRulesTests`
Expected: FAIL — `cannot find 'HealthRules'` / `cannot find 'HealthStatus'`.

- [ ] **Step 3: Write the implementation**

Create `Sources/DakaCore/HealthRules.swift`:

```swift
import Foundation

public struct HealthStatus: Equatable, Sendable {
    public let cups: Int
    public let stands: Int
    public let minutesSinceDrink: Int?
    public let minutesSinceStand: Int?
    public let waterDue: Bool
    public let movementDue: Bool
    public let active: Bool

    public init(cups: Int,
                stands: Int,
                minutesSinceDrink: Int?,
                minutesSinceStand: Int?,
                waterDue: Bool,
                movementDue: Bool,
                active: Bool) {
        self.cups = cups
        self.stands = stands
        self.minutesSinceDrink = minutesSinceDrink
        self.minutesSinceStand = minutesSinceStand
        self.waterDue = waterDue
        self.movementDue = movementDue
        self.active = active
    }

    public static let idle = HealthStatus(cups: 0, stands: 0,
                                          minutesSinceDrink: nil, minutesSinceStand: nil,
                                          waterDue: false, movementDue: false, active: false)
}

public enum HealthRules {
    public static func status(health: HealthSettings,
                              schedule: Settings,
                              record: DayHealthRecord,
                              skipped: Bool,
                              now: Date,
                              calendar: Calendar = .current) -> HealthStatus {
        let weekday = DakaDate.weekday(of: now, calendar: calendar)
        let windowStart = DakaDate.date(on: now, at: schedule.morningWindowStart, calendar: calendar)
        let windowEnd = DakaDate.date(on: now, at: schedule.eveningDeadline, calendar: calendar)

        let inWindow: Bool
        switch (windowStart, windowEnd) {
        case let (start?, end?): inWindow = now >= start && now <= end
        default: inWindow = true
        }

        let active = schedule.enabled
            && !skipped
            && schedule.workdays.contains(weekday)
            && inWindow

        let drinkBase = record.lastDrinkAt ?? windowStart ?? now
        let standBase = record.lastStandAt ?? windowStart ?? now
        let drinkMinutes = max(0, Int(now.timeIntervalSince(drinkBase) / 60))
        let standMinutes = max(0, Int(now.timeIntervalSince(standBase) / 60))

        let waterDue = active
            && health.waterEnabled
            && drinkMinutes >= health.effectiveWaterIntervalMinutes
        let movementDue = active
            && health.movementEnabled
            && standMinutes >= health.effectiveMovementIntervalMinutes

        return HealthStatus(cups: record.cups,
                            stands: record.standCount,
                            minutesSinceDrink: drinkMinutes,
                            minutesSinceStand: standMinutes,
                            waterDue: waterDue,
                            movementDue: movementDue,
                            active: active)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HealthRulesTests`
Expected: PASS (9 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DakaCore/HealthRules.swift Tests/DakaCoreTests/HealthRulesTests.swift
git commit -m "feat: add health rule evaluation"
```

---

### Task 3: Health persistence store

**Files:**
- Create: `Sources/DakaCore/HealthStore.swift`
- Test: `Tests/DakaCoreTests/HealthStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/DakaCoreTests/HealthStoreTests.swift`:

```swift
import XCTest
@testable import DakaCore

final class HealthStoreTests: XCTestCase {
    private let cal = TestTime.calendar
    private var url: URL!
    private var store: HealthStore!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("health-\(UUID().uuidString).json")
        store = HealthStore(fileURL: url)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    func testLogAndReload() throws {
        let t = TestTime.date(2026, 9, 14, 9, 10)
        try store.log(.water, at: t, calendar: cal)
        try store.log(.water, at: t.addingTimeInterval(3600), calendar: cal)
        try store.log(.movement, at: t, calendar: cal)

        let reloaded = HealthStore(fileURL: url)
        let rec = reloaded.record(for: t, calendar: cal)
        XCTAssertEqual(rec.cups, 2)
        XCTAssertEqual(rec.standCount, 1)
    }

    func testUpdateSettings() throws {
        var s = HealthSettings.default
        s.waterGoalCups = 10
        try store.updateSettings(s)
        XCTAssertEqual(HealthStore(fileURL: url).data.settings.waterGoalCups, 10)
    }

    func testCorruptionRecovers() throws {
        try Data("not json".utf8).write(to: url)
        let recovered = HealthStore(fileURL: url)
        XCTAssertTrue(recovered.didRecoverFromCorruption)
        XCTAssertEqual(recovered.data.settings, .default)
        XCTAssertTrue(recovered.data.records.isEmpty)
    }

    func testMissingFileStartsEmpty() {
        XCTAssertFalse(store.didRecoverFromCorruption)
        XCTAssertTrue(store.data.records.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HealthStoreTests`
Expected: FAIL — `cannot find 'HealthStore'`.

- [ ] **Step 3: Write the implementation**

Create `Sources/DakaCore/HealthStore.swift`:

```swift
import Foundation

public final class HealthStore {
    public private(set) var data: HealthData
    public private(set) var didRecoverFromCorruption: Bool
    public private(set) var corruptionBackupURL: URL?
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        let loaded = HealthStore.load(from: fileURL)
        self.data = loaded.data
        self.didRecoverFromCorruption = loaded.recovered
        self.corruptionBackupURL = loaded.backupURL
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Daka/health.json")
    }

    public func record(for date: Date, calendar: Calendar = .current) -> DayHealthRecord {
        let key = DakaDate.key(for: date, calendar: calendar)
        return data.records[key] ?? DayHealthRecord()
    }

    public func log(_ kind: HealthLogKind, at date: Date, calendar: Calendar = .current) throws {
        let key = DakaDate.key(for: date, calendar: calendar)
        let previous = data.records[key]
        var rec = previous ?? DayHealthRecord()
        switch kind {
        case .water: rec.drinks.append(date)
        case .movement: rec.stands.append(date)
        }
        data.records[key] = rec
        try persist(rollingBack: { self.data.records[key] = previous })
    }

    public func updateSettings(_ settings: HealthSettings) throws {
        let previous = data.settings
        data.settings = settings
        try persist(rollingBack: { self.data.settings = previous })
    }

    private func persist(rollingBack rollback: () -> Void) throws {
        do {
            try persist()
        } catch {
            rollback()
            throw error
        }
    }

    private func persist() throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let out = try encoder.encode(data)
        try out.write(to: fileURL, options: .atomic)
    }

    private struct LoadResult {
        var data: HealthData
        var recovered: Bool
        var backupURL: URL?
    }

    private static func load(from url: URL) -> LoadResult {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return LoadResult(data: HealthData(), recovered: false, backupURL: nil)
        }
        guard let raw = try? Data(contentsOf: url) else {
            let backup = makeBackupURL(for: url)
            let moved = (try? fileManager.moveItem(at: url, to: backup)) != nil
            return LoadResult(data: HealthData(), recovered: true, backupURL: moved ? backup : nil)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return LoadResult(data: try decoder.decode(HealthData.self, from: raw),
                              recovered: false, backupURL: nil)
        } catch {
            let backup = makeBackupURL(for: url)
            let moved = (try? fileManager.moveItem(at: url, to: backup)) != nil
            return LoadResult(data: HealthData(), recovered: true, backupURL: moved ? backup : nil)
        }
    }

    private static func makeBackupURL(for url: URL) -> URL {
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let suffix = UUID().uuidString.prefix(8)
        return url.deletingLastPathComponent()
            .appendingPathComponent("health.json.corrupt-\(stamp)-\(suffix)")
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HealthStoreTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DakaCore/HealthStore.swift Tests/DakaCoreTests/HealthStoreTests.swift
git commit -m "feat: add health persistence store"
```

---

### Task 4: Health statistics

**Files:**
- Create: `Sources/DakaCore/HealthStatistics.swift`
- Test: `Tests/DakaCoreTests/HealthStatisticsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/DakaCoreTests/HealthStatisticsTests.swift`:

```swift
import XCTest
@testable import DakaCore

final class HealthStatisticsTests: XCTestCase {
    private let cal = TestTime.calendar

    private var schedule: Settings {
        Settings(workdays: [2, 3, 4, 5, 6])
    }

    private func record(cups: Int, stands: Int = 0, on day: Date) -> (String, DayHealthRecord) {
        let drinks = (0..<cups).map { day.addingTimeInterval(TimeInterval($0 * 3600)) }
        let moves = (0..<stands).map { day.addingTimeInterval(TimeInterval($0 * 3600)) }
        return (DakaDate.key(for: day, calendar: cal),
                DayHealthRecord(drinks: drinks, stands: moves))
    }

    func testDailyAggregation() {
        let now = TestTime.date(2026, 9, 14, 10, 0) // 周一
        var records: [String: DayHealthRecord] = [:]
        let (k1, r1) = record(cups: 8, stands: 3, on: TestTime.date(2026, 9, 14))
        let (k2, r2) = record(cups: 4, stands: 1, on: TestTime.date(2026, 9, 13)) // 周日
        records[k1] = r1
        records[k2] = r2

        let summary = HealthStatistics.compute(records: records, settings: .default,
                                               schedule: schedule, now: now,
                                               rangeDays: 7, calendar: cal)
        XCTAssertEqual(summary.days.count, 7)
        XCTAssertEqual(summary.days.last?.cups, 8)
        XCTAssertEqual(summary.averageCups, 12.0 / 7.0, accuracy: 0.001)
        XCTAssertEqual(summary.waterGoalDays, 1)     // 仅周一达标（周日非工作日）
        XCTAssertEqual(summary.movementGoalDays, 0)
    }

    func testStreakSkipsWeekendAndCountsConsecutiveWorkdays() {
        let now = TestTime.date(2026, 9, 14, 10, 0) // 周一
        var records: [String: DayHealthRecord] = [:]
        records[record(cups: 8, on: TestTime.date(2026, 9, 14)).0] = record(cups: 8, on: TestTime.date(2026, 9, 14)).1
        records[record(cups: 8, on: TestTime.date(2026, 9, 11)).0] = record(cups: 8, on: TestTime.date(2026, 9, 11)).1 // 周五
        records[record(cups: 8, on: TestTime.date(2026, 9, 10)).0] = record(cups: 8, on: TestTime.date(2026, 9, 10)).1 // 周四

        let summary = HealthStatistics.compute(records: records, settings: .default,
                                               schedule: schedule, now: now,
                                               rangeDays: 14, calendar: cal)
        XCTAssertEqual(summary.waterStreak, 3) // 周一 + 周五 + 周四，跳过周末
    }

    func testUnmetTodayDoesNotBreakStreak() {
        let now = TestTime.date(2026, 9, 14, 10, 0) // 周一，今天还没达标
        var records: [String: DayHealthRecord] = [:]
        records[record(cups: 8, on: TestTime.date(2026, 9, 11)).0] = record(cups: 8, on: TestTime.date(2026, 9, 11)).1
        let summary = HealthStatistics.compute(records: records, settings: .default,
                                               schedule: schedule, now: now,
                                               rangeDays: 14, calendar: cal)
        XCTAssertEqual(summary.waterStreak, 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HealthStatisticsTests`
Expected: FAIL — `cannot find 'HealthStatistics'`.

- [ ] **Step 3: Write the implementation**

Create `Sources/DakaCore/HealthStatistics.swift`:

```swift
import Foundation

public struct HealthDayStat: Equatable, Sendable {
    public let dateKey: String
    public let cups: Int
    public let stands: Int
    public let isWorkday: Bool

    public init(dateKey: String, cups: Int, stands: Int, isWorkday: Bool) {
        self.dateKey = dateKey
        self.cups = cups
        self.stands = stands
        self.isWorkday = isWorkday
    }
}

public struct HealthSummary: Equatable, Sendable {
    public var days: [HealthDayStat]
    public var rangeDays: Int
    public var waterGoalDays: Int
    public var movementGoalDays: Int
    public var averageCups: Double
    public var averageStands: Double
    public var waterStreak: Int
    public var movementStreak: Int

    public init(days: [HealthDayStat] = [],
                rangeDays: Int = 0,
                waterGoalDays: Int = 0,
                movementGoalDays: Int = 0,
                averageCups: Double = 0,
                averageStands: Double = 0,
                waterStreak: Int = 0,
                movementStreak: Int = 0) {
        self.days = days
        self.rangeDays = rangeDays
        self.waterGoalDays = waterGoalDays
        self.movementGoalDays = movementGoalDays
        self.averageCups = averageCups
        self.averageStands = averageStands
        self.waterStreak = waterStreak
        self.movementStreak = movementStreak
    }
}

public enum HealthStatistics {
    private enum Metric { case water, movement }

    public static func compute(records: [String: DayHealthRecord],
                               settings: HealthSettings,
                               schedule: Settings,
                               now: Date,
                               rangeDays: Int,
                               calendar: Calendar = .current) -> HealthSummary {
        let range = max(1, rangeDays)
        var days: [HealthDayStat] = []
        var totalCups = 0
        var totalStands = 0
        var waterGoalDays = 0
        var movementGoalDays = 0

        for offset in stride(from: range - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let key = DakaDate.key(for: day, calendar: calendar)
            let rec = records[key] ?? DayHealthRecord()
            let isWorkday = schedule.workdays.contains(DakaDate.weekday(of: day, calendar: calendar))
            days.append(HealthDayStat(dateKey: key, cups: rec.cups,
                                      stands: rec.standCount, isWorkday: isWorkday))
            totalCups += rec.cups
            totalStands += rec.standCount
            if isWorkday && rec.cups >= settings.waterGoalCups { waterGoalDays += 1 }
            if isWorkday && rec.standCount >= settings.movementGoalCount { movementGoalDays += 1 }
        }

        let count = max(1, days.count)
        return HealthSummary(days: days,
                             rangeDays: range,
                             waterGoalDays: waterGoalDays,
                             movementGoalDays: movementGoalDays,
                             averageCups: Double(totalCups) / Double(count),
                             averageStands: Double(totalStands) / Double(count),
                             waterStreak: streak(records: records, settings: settings,
                                                 schedule: schedule, now: now,
                                                 metric: .water, calendar: calendar),
                             movementStreak: streak(records: records, settings: settings,
                                                    schedule: schedule, now: now,
                                                    metric: .movement, calendar: calendar))
    }

    private static func streak(records: [String: DayHealthRecord],
                               settings: HealthSettings,
                               schedule: Settings,
                               now: Date,
                               metric: Metric,
                               calendar: Calendar) -> Int {
        var cursor = calendar.startOfDay(for: now)
        var count = 0
        for _ in 0..<400 {
            let key = DakaDate.key(for: cursor, calendar: calendar)
            let rec = records[key] ?? DayHealthRecord()
            let isWorkday = schedule.workdays.contains(DakaDate.weekday(of: cursor, calendar: calendar))
            if isWorkday {
                let met = metric == .water
                    ? rec.cups >= settings.waterGoalCups
                    : rec.standCount >= settings.movementGoalCount
                let isToday = calendar.isDate(cursor, inSameDayAs: now)
                if met {
                    count += 1
                } else if !isToday {
                    break
                }
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HealthStatisticsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DakaCore/HealthStatistics.swift Tests/DakaCoreTests/HealthStatisticsTests.swift
git commit -m "feat: add health statistics aggregation"
```

---

### Task 5: Pet mood reflects hydration and movement

**Files:**
- Modify: `Sources/DakaCore/PetMood.swift`
- Test: `Tests/DakaCoreTests/PetMoodTests.swift`

- [ ] **Step 1: Add failing tests**

Append these cases to `Tests/DakaCoreTests/PetMoodTests.swift` (inside the class, before the closing brace):

```swift
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
        let mood = PetMood.resolve(reminderState: ReminderState(gentle: [.morning]),
                                   now: TestTime.date(2026, 9, 14, 10, 0),
                                   health: status, calendar: cal)
        XCTAssertEqual(mood, .gentlePending)
    }

    func testIdleHealthStatusKeepsTimeMood() {
        let mood = PetMood.resolve(reminderState: ReminderState(),
                                   now: TestTime.date(2026, 9, 14, 10, 0),
                                   health: .idle, calendar: cal)
        XCTAssertEqual(mood, .cheerful)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PetMoodTests`
Expected: FAIL — `extra argument 'health'` / `type 'PetMood' has no member 'thirsty'`.

- [ ] **Step 3: Update the implementation**

Replace the contents of `Sources/DakaCore/PetMood.swift` with:

```swift
import Foundation

public enum PetMood: String, CaseIterable, Sendable {
    case cheerful       // 上午
    case lunch          // 午间
    case focused        // 下午
    case relaxed        // 傍晚
    case sleepy         // 夜间/深夜
    case gentlePending  // 打卡窗口内未完成
    case hardPending    // 已过截止未完成
    case thirsty        // 该喝水了
    case restless       // 该起身走动了

    public var emoji: String {
        switch self {
        case .cheerful: return "🌞"
        case .lunch: return "😋"
        case .focused: return "💪"
        case .relaxed: return "😌"
        case .sleepy: return "😴"
        case .gentlePending: return "🤔"
        case .hardPending: return "😰"
        case .thirsty: return "🥵"
        case .restless: return "😤"
        }
    }

    /// 状态覆盖时间：打卡 hard > 打卡 gentle > 健康（喝水 > 走动）> 时间。
    public static func resolve(reminderState: ReminderState,
                               now: Date,
                               health: HealthStatus? = nil,
                               calendar: Calendar = .current) -> PetMood {
        if !reminderState.hard.isEmpty { return .hardPending }
        if !reminderState.gentle.isEmpty { return .gentlePending }
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

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter PetMoodTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/DakaCore/PetMood.swift Tests/DakaCoreTests/PetMoodTests.swift
git commit -m "feat: pet mood reflects hydration and movement"
```

---

### Task 6: Generic notification method

**Files:**
- Modify: `Sources/Daka/GentleNotifier.swift`

No unit tests (UNUserNotificationCenter is not testable in SwiftPM); validated by `swift build` in Step 3 and by manual verification later.

- [ ] **Step 1: Refactor `GentleNotifier`**

Replace the `notify(tasks:)` method and add an overload. The full file becomes:

```swift
import Foundation
import UserNotifications
import DakaCore

/// 温和提醒通道：本地通知。未打包运行或无权限时静默（菜单栏警示仍在）。
final class GentleNotifier {
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    func requestAuthorizationIfNeeded() {
        guard let center else { return }
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(tasks: [PunchTask]) {
        guard !tasks.isEmpty else { return }
        let body: String
        if tasks.count > 1 {
            body = "\(tasks.map(\.title).joined(separator: "、")) 都还没完成，记得在窗口内打卡。"
        } else {
            body = "\(tasks[0].title)：还在打卡窗口内，记得完成。"
        }
        notify(id: "daka.gentle", title: "打卡提醒", body: body)
    }

    func notify(id: String, title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Daka/GentleNotifier.swift
git commit -m "refactor: add generic notification method"
```

---

### Task 7: Health reminder controller

**Files:**
- Create: `Sources/Daka/HealthReminderController.swift`

No unit tests (timers/notifications are app-layer); validated by `swift build` and manual verification.

- [ ] **Step 1: Write the controller**

Create `Sources/Daka/HealthReminderController.swift`:

```swift
import Foundation
import DakaCore

/// 独立的健康提醒调度：按工作时段评估喝水/走动，到点发通知并驱动桌宠气泡。
@MainActor
final class HealthReminderController {
    var onSpeak: ((String) -> Void)?

    private let clock: DakaClock
    private let healthStore: HealthStore
    private let scheduleStore: PunchStore
    private let notifier = GentleNotifier()
    private let interval: TimeInterval

    private var timer: Timer?
    private var lastWaterNoticeAt: Date?
    private var lastMovementNoticeAt: Date?

    init(clock: DakaClock,
         healthStore: HealthStore,
         scheduleStore: PunchStore,
         interval: TimeInterval = 30) {
        self.clock = clock
        self.healthStore = healthStore
        self.scheduleStore = scheduleStore
        self.interval = interval
        notifier.requestAuthorizationIfNeeded()
    }

    func start() {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    func tick() {
        let now = clock.now
        let health = healthStore.data.settings
        let schedule = scheduleStore.data.settings
        let record = healthStore.record(for: now)
        let skipped = scheduleStore.record(for: now).skipped
        let status = HealthRules.status(health: health, schedule: schedule,
                                        record: record, skipped: skipped, now: now)

        if status.waterDue {
            let every = TimeInterval(health.effectiveWaterIntervalMinutes * 60)
            if lastWaterNoticeAt.map({ now.timeIntervalSince($0) >= every }) ?? true {
                lastWaterNoticeAt = now
                let minutes = status.minutesSinceDrink ?? health.effectiveWaterIntervalMinutes
                notifier.notify(id: "daka.water",
                                title: "该喝水啦 💧",
                                body: "已经 \(minutes) 分钟没喝水了，起来接杯水吧。")
                onSpeak?("该喝水啦～💧")
            }
        }

        if status.movementDue {
            let every = TimeInterval(health.effectiveMovementIntervalMinutes * 60)
            if lastMovementNoticeAt.map({ now.timeIntervalSince($0) >= every }) ?? true {
                lastMovementNoticeAt = now
                let minutes = status.minutesSinceStand ?? health.effectiveMovementIntervalMinutes
                notifier.notify(id: "daka.movement",
                                title: "起来走两步 🚶",
                                body: "坐了 \(minutes) 分钟，活动一下肩颈和腿吧。")
                onSpeak?("坐太久啦，起来走两步 🚶")
            }
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Daka/HealthReminderController.swift
git commit -m "feat: add health reminder controller"
```

---

### Task 8: AppModel health integration

**Files:**
- Modify: `Sources/Daka/AppModel.swift`

No unit tests (`AppModel` is app-layer); validated by `swift build` and later manual verification.

- [ ] **Step 1: Add published health state and dependencies**

In `Sources/Daka/AppModel.swift`, add these properties after the existing `@Published var selectedSidebar` / `let tools` declarations (after line 23):

```swift
    @Published private(set) var healthSettings: HealthSettings
    @Published private(set) var healthRecord: DayHealthRecord
    @Published var petSpeech: String?
```

Add these private fields next to `private let store: PunchStore` (around line 49):

```swift
    private let healthStore: HealthStore
    private var healthReminder: HealthReminderController?
    private var speechClearTimer: Timer?
```

- [ ] **Step 2: Initialize the health store**

Replace the `init` body (currently lines 54-61) with:

```swift
    init(clock: AdjustableClock = AdjustableClock(),
         store: PunchStore? = nil,
         healthStore: HealthStore? = nil) {
        let resolvedStore = store ?? PunchStore(fileURL: PunchStore.defaultFileURL())
        let resolvedHealth = healthStore ?? HealthStore(fileURL: HealthStore.defaultFileURL())
        self.clock = clock
        self.store = resolvedStore
        self.healthStore = resolvedHealth
        self.settings = resolvedStore.data.settings
        self.record = resolvedStore.record(for: clock.now)
        self.healthSettings = resolvedHealth.data.settings
        self.healthRecord = resolvedHealth.record(for: clock.now)
        self.petVisible = UserDefaults.standard.object(forKey: "pet.visible") as? Bool ?? true
    }
```

- [ ] **Step 3: Add computed status and mutation methods**

Add these methods after the existing `func refreshRecord()` block (after line 123):

```swift
    var healthStatus: HealthStatus {
        HealthRules.status(health: healthSettings,
                           schedule: settings,
                           record: healthRecord,
                           skipped: record.skipped,
                           now: clock.now)
    }

    func refreshHealth() {
        healthRecord = healthStore.record(for: clock.now)
        healthSettings = healthStore.data.settings
    }

    func drinkWater() {
        do {
            try logHealth(.water)
            say("咕嘟咕嘟，+1 杯！")
        } catch {}
    }

    func standUp() {
        do {
            try logHealth(.movement)
            say("走一走真舒服～")
        } catch {}
    }

    private func logHealth(_ kind: HealthLogKind) throws {
        errorMessage = nil
        do {
            try healthStore.log(kind, at: clock.now)
            refreshHealth()
            scheduler?.tick()
        } catch {
            errorMessage = "记录失败：\(error.localizedDescription)"
            throw error
        }
    }

    func healthStatistics(rangeDays: Int) -> HealthSummary {
        HealthStatistics.compute(records: healthStore.data.records,
                                 settings: healthStore.data.settings,
                                 schedule: settings,
                                 now: clock.now,
                                 rangeDays: rangeDays)
    }

    func updateHealthSettings(_ mutate: (inout HealthSettings) -> Void) {
        errorMessage = nil
        var s = healthStore.data.settings
        mutate(&s)
        do {
            try healthStore.updateSettings(s)
            refreshHealth()
            healthReminder?.tick()
        } catch {
            errorMessage = "设置保存失败：\(error.localizedDescription)"
        }
    }

    func setWaterEnabled(_ on: Bool) { updateHealthSettings { $0.waterEnabled = on } }
    func setWaterGoalCups(_ n: Int) { updateHealthSettings { $0.waterGoalCups = max(1, n) } }
    func setWaterIntervalMinutes(_ n: Int) { updateHealthSettings { $0.waterIntervalMinutes = max(15, n) } }
    func setMovementEnabled(_ on: Bool) { updateHealthSettings { $0.movementEnabled = on } }
    func setMovementGoalCount(_ n: Int) { updateHealthSettings { $0.movementGoalCount = max(1, n) } }
    func setMovementIntervalMinutes(_ n: Int) { updateHealthSettings { $0.movementIntervalMinutes = max(15, n) } }

    func say(_ text: String) {
        petSpeech = text
        petWindow?.showSpeech(text)
        speechClearTimer?.invalidate()
        let t = Timer(timeInterval: 6, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.petSpeech = nil
                self?.petWindow?.hideSpeech()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        speechClearTimer = t
    }
```

- [ ] **Step 4: Wire startup, corruption warning, and day refresh**

In `start()`, after the existing `if store.didRecoverFromCorruption { ... }` warning block, add:

```swift
        if healthStore.didRecoverFromCorruption {
            warnings.append("健康记录文件损坏，已备份并重置。" +
                (healthStore.corruptionBackupURL.map { "备份：\($0.lastPathComponent)" } ?? ""))
        }
```

In the existing `scheduler.onStateChange` closure, add a health refresh so the day rolls over. The closure currently reads:

```swift
        scheduler.onStateChange = { [weak self] state in
            guard let self else { return }
            self.reminderState = state
            self.refreshRecord()
        }
```

Change it to:

```swift
        scheduler.onStateChange = { [weak self] state in
            guard let self else { return }
            self.reminderState = state
            self.refreshRecord()
            self.refreshHealth()
        }
```

After `self.scheduler = scheduler` (before `installScheduledLaunch()`), add:

```swift
        let healthReminder = HealthReminderController(clock: clock,
                                                      healthStore: healthStore,
                                                      scheduleStore: store)
        healthReminder.onSpeak = { [weak self] text in self?.say(text) }
        self.healthReminder = healthReminder
        healthReminder.start()
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: FAIL initially if `PetWindowController.showSpeech` does not exist yet (`value of type 'PetWindowController' has no member 'showSpeech'`).

This task intentionally depends on Task 9. If you are executing tasks strictly in order, create the stub methods now in `Sources/Daka/PetWindowController.swift` and replace them fully in Task 9:

```swift
    func showSpeech(_ text: String) {}
    func hideSpeech() {}
```

Then run `swift build` again.
Expected: build succeeds.

- [ ] **Step 6: Run all tests**

Run: `swift test`
Expected: all existing tests + new Health tests PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/Daka/AppModel.swift Sources/Daka/PetWindowController.swift
git commit -m "feat: integrate health tools into app model"
```

---

### Task 9: Pet speech bubble window

**Files:**
- Create: `Sources/Daka/PetSpeechBubble.swift`
- Modify: `Sources/Daka/PetWindowController.swift`

- [ ] **Step 1: Create the bubble view**

Create `Sources/Daka/PetSpeechBubble.swift`:

```swift
import SwiftUI

struct PetSpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: 220, height: 52)
            .background(Color(nsColor: .controlBackgroundColor),
                       in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.black.opacity(0.12))
            )
    }
}
```

- [ ] **Step 2: Add the bubble window to `PetWindowController`**

In `Sources/Daka/PetWindowController.swift`, add a stored property next to `private var popover: NSPopover?`:

```swift
    private var bubbleWindow: NSWindow?
```

If you added the stub methods in Task 8, replace them. Add these methods after `hide()`:

```swift
    func showSpeech(_ text: String) {
        guard !text.isEmpty, let window, window.isVisible else { return }
        let size = NSSize(width: 220, height: 52)
        let panel = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless],
                             backing: .buffered,
                             defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PetSpeechBubble(text: text))

        let petFrame = window.frame
        let origin = NSPoint(x: petFrame.midX - size.width / 2,
                             y: petFrame.maxY + 6)
        panel.setFrameOrigin(origin)

        bubbleWindow?.orderOut(nil)
        panel.orderFrontRegardless()
        bubbleWindow = panel
    }

    func hideSpeech() {
        bubbleWindow?.orderOut(nil)
        bubbleWindow = nil
    }
```

Also extend `hide()` to dismiss the bubble. Change:

```swift
    func hide() {
        popover?.close()
        window?.orderOut(nil)
    }
```

to:

```swift
    func hide() {
        popover?.close()
        hideSpeech()
        window?.orderOut(nil)
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/Daka/PetSpeechBubble.swift Sources/Daka/PetWindowController.swift
git commit -m "feat: add pet speech bubble window"
```

---

### Task 10: Pet face uses health status

**Files:**
- Modify: `Sources/Daka/PetView.swift`

- [ ] **Step 1: Pass health status to mood resolution**

In `Sources/Daka/PetView.swift`, replace the `mood` computed property (lines 10-12):

```swift
    private var mood: PetMood {
        PetMood.resolve(reminderState: model.reminderState, now: model.now)
    }
```

with:

```swift
    private var mood: PetMood {
        PetMood.resolve(reminderState: model.reminderState,
                        now: model.now,
                        health: model.healthStatus)
    }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Daka/PetView.swift
git commit -m "feat: pet face reflects health status"
```

---

### Task 11: Health tool views and control center wiring

**Files:**
- Create: `Sources/Daka/HealthToolViews.swift`
- Modify: `Sources/Daka/ControlCenterView.swift`

- [ ] **Step 1: Create the tool views**

Create `Sources/Daka/HealthToolViews.swift`:

```swift
import SwiftUI
import Charts
import DakaCore

struct WaterToolView: View {
    @ObservedObject var model: AppModel
    @State private var rangeDays = 14

    private var status: HealthStatus { model.healthStatus }
    private var summary: HealthSummary { model.healthStatistics(rangeDays: rangeDays) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    HealthMetricCard(title: "今日喝水",
                                     value: "\(status.cups)/\(model.healthSettings.waterGoalCups) 杯",
                                     symbol: "drop.fill")
                    HealthMetricCard(title: "连续达标",
                                     value: "\(summary.waterStreak) 天",
                                     symbol: "flame")
                    HealthMetricCard(title: "平均每日",
                                     value: String(format: "%.1f 杯", summary.averageCups),
                                     symbol: "chart.bar")
                    HealthMetricCard(title: "距上次喝水",
                                     value: HealthFormat.minutes(status.minutesSinceDrink),
                                     symbol: "clock")
                }

                Button {
                    model.drinkWater()
                } label: {
                    Label("喝了一杯水", systemImage: "drop.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("每日喝水").font(.headline)
                        Spacer()
                        rangePicker
                    }
                    Chart {
                        ForEach(summary.days, id: \.dateKey) { day in
                            BarMark(x: .value("日期", String(day.dateKey.suffix(5))),
                                    y: .value("杯", day.cups))
                                .foregroundStyle(Color.blue)
                        }
                        RuleMark(y: .value("目标", model.healthSettings.waterGoalCups))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartYAxisLabel("杯")
                    .frame(height: 220)
                }

                Form {
                    Section("喝水设置") {
                        Toggle("启用提醒", isOn: Binding(
                            get: { model.healthSettings.waterEnabled },
                            set: { model.setWaterEnabled($0) }))
                        Stepper("每日目标：\(model.healthSettings.waterGoalCups) 杯",
                                value: Binding(
                                    get: { model.healthSettings.waterGoalCups },
                                    set: { model.setWaterGoalCups($0) }),
                                in: 1...20)
                        Stepper("提醒间隔：\(model.healthSettings.waterIntervalMinutes) 分钟",
                                value: Binding(
                                    get: { model.healthSettings.waterIntervalMinutes },
                                    set: { model.setWaterIntervalMinutes($0) }),
                                in: 15...240, step: 15)
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    private var rangePicker: some View {
        Picker("范围", selection: $rangeDays) {
            Text("7 天").tag(7)
            Text("14 天").tag(14)
            Text("30 天").tag(30)
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
    }
}

struct MovementToolView: View {
    @ObservedObject var model: AppModel
    @State private var rangeDays = 14

    private var status: HealthStatus { model.healthStatus }
    private var summary: HealthSummary { model.healthStatistics(rangeDays: rangeDays) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    HealthMetricCard(title: "今日起身",
                                     value: "\(status.stands)/\(model.healthSettings.movementGoalCount) 次",
                                     symbol: "figure.walk")
                    HealthMetricCard(title: "连续达标",
                                     value: "\(summary.movementStreak) 天",
                                     symbol: "flame")
                    HealthMetricCard(title: "平均每日",
                                     value: String(format: "%.1f 次", summary.averageStands),
                                     symbol: "chart.bar")
                    HealthMetricCard(title: "距上次起身",
                                     value: HealthFormat.minutes(status.minutesSinceStand),
                                     symbol: "clock")
                }

                Button {
                    model.standUp()
                } label: {
                    Label("起来走走", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("每日起身次数").font(.headline)
                        Spacer()
                        rangePicker
                    }
                    Chart {
                        ForEach(summary.days, id: \.dateKey) { day in
                            BarMark(x: .value("日期", String(day.dateKey.suffix(5))),
                                    y: .value("次", day.stands))
                                .foregroundStyle(Color.green)
                        }
                        RuleMark(y: .value("目标", model.healthSettings.movementGoalCount))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartYAxisLabel("次")
                    .frame(height: 220)
                }

                Form {
                    Section("走动设置") {
                        Toggle("启用提醒", isOn: Binding(
                            get: { model.healthSettings.movementEnabled },
                            set: { model.setMovementEnabled($0) }))
                        Stepper("每日目标：\(model.healthSettings.movementGoalCount) 次",
                                value: Binding(
                                    get: { model.healthSettings.movementGoalCount },
                                    set: { model.setMovementGoalCount($0) }),
                                in: 1...20)
                        Stepper("提醒间隔：\(model.healthSettings.movementIntervalMinutes) 分钟",
                                value: Binding(
                                    get: { model.healthSettings.movementIntervalMinutes },
                                    set: { model.setMovementIntervalMinutes($0) }),
                                in: 15...240, step: 15)
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    private var rangePicker: some View {
        Picker("范围", selection: $rangeDays) {
            Text("7 天").tag(7)
            Text("14 天").tag(14)
            Text("30 天").tag(30)
        }
        .pickerStyle(.segmented)
        .frame(width: 220)
    }
}

struct HealthMetricCard: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
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

enum HealthFormat {
    static func minutes(_ value: Int?) -> String {
        guard let value else { return "—" }
        if value < 60 { return "\(value) 分钟" }
        return "\(value / 60) 小时 \(value % 60) 分"
    }
}
```

- [ ] **Step 2: Route the tools in `ControlCenterView`**

In `Sources/Daka/ControlCenterView.swift`, update `summary(for:)`. Replace:

```swift
        case .punch:
            let morning = model.record.morningDone ? "上班已完成" : "上班待打卡"
            let evening = model.isEveningComplete ? "下班已完成" : "下班待打卡"
            return "\(morning) · \(evening)"
        default:
            return "即将推出"
```

with:

```swift
        case .punch:
            let morning = model.record.morningDone ? "上班已完成" : "上班待打卡"
            let evening = model.isEveningComplete ? "下班已完成" : "下班待打卡"
            return "\(morning) · \(evening)"
        case .water:
            return "今日 \(model.healthStatus.cups)/\(model.healthSettings.waterGoalCups) 杯"
        case .sedentary:
            return "已起身 \(model.healthStatus.stands) 次"
        case .eye:
            return "即将推出"
```

Update `detail(for:)`. Replace:

```swift
        case .tool(.punch):
            PunchToolView(model: model)
        case .tool(let id):
            ComingSoonView(metadata: ToolCatalog.metadata(for: id))
```

with:

```swift
        case .tool(.punch):
            PunchToolView(model: model)
        case .tool(.water):
            WaterToolView(model: model)
        case .tool(.sedentary):
            MovementToolView(model: model)
        case .tool(.eye):
            ComingSoonView(metadata: ToolCatalog.metadata(for: .eye))
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add Sources/Daka/HealthToolViews.swift Sources/Daka/ControlCenterView.swift
git commit -m "feat: add water and movement tool views"
```

---

### Task 12: Pet panel summaries and quick log buttons

**Files:**
- Modify: `Sources/Daka/ToolPanelView.swift`

- [ ] **Step 1: Show real health data and quick actions**

In `Sources/Daka/ToolPanelView.swift`, replace the summary block:

```swift
            VStack(alignment: .leading, spacing: 4) {
                summaryRow("打卡", punchSummary, "checkmark.seal")
                summaryRow("喝水", "即将推出", "drop")
                summaryRow("护眼", "即将推出", "eye")
                summaryRow("久坐", "即将推出", "figure.walk")
            }
            .font(.caption)

            Divider()
```

with:

```swift
            VStack(alignment: .leading, spacing: 4) {
                summaryRow("打卡", punchSummary, "checkmark.seal")
                summaryRow("喝水", "\(model.healthStatus.cups)/\(model.healthSettings.waterGoalCups) 杯", "drop")
                summaryRow("走动", "已起身 \(model.healthStatus.stands) 次", "figure.walk")
            }
            .font(.caption)

            HStack {
                Button {
                    model.drinkWater()
                } label: {
                    Label("喝水", systemImage: "drop.fill")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    model.standUp()
                } label: {
                    Label("走动", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
            }

            Divider()
```

Add `model` is already available via `@ObservedObject var model: AppModel`, so no new wiring.

- [ ] **Step 2: Build**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/Daka/ToolPanelView.swift
git commit -m "feat: show health data in pet panel"
```

---

### Task 13: Documentation and verification checklist

**Files:**
- Modify: `README.md`
- Modify: `docs/verification.md`

- [ ] **Step 1: Update the README feature list**

In `README.md`, in the `## 功能特性` list, add after the `**打卡统计**` bullet:

```markdown
- **喝水 / 走动**：桌宠会定时提醒你喝水、起身活动；点一下即可记录一杯水 / 一次起身，桌宠表情和气泡会回应。提醒只在工作日、打卡工作时段内生效。
- **健康统计**：控制中心「喝水」「久坐」页展示今日进度、连续达标、平均每日与 7 / 14 / 30 天柱状图（含目标线）。
```

In the `## 数据存储` section, after the existing JSON code block and its explanation, add the following text (keep the jsonc fence below exactly):

健康习惯记录单独保存在 `~/Library/Application Support/Daka/health.json`，结构如下：

```jsonc
{
  "settings": {
    "waterEnabled": true,
    "waterGoalCups": 8,
    "waterIntervalMinutes": 60,
    "movementEnabled": true,
    "movementGoalCount": 8,
    "movementIntervalMinutes": 60
  },
  "records": {
    "2026-09-14": {
      "drinks": ["2026-09-14T09:12:00+08:00"],
      "stands": ["2026-09-14T10:30:00+08:00"]
    }
  }
}
```

Then add the line:

损坏时同样备份为 `health.json.corrupt-<时间戳>-*` 并重建。

- [ ] **Step 2: Append the verification section**

Append to the end of `docs/verification.md`:

```markdown
## v11：健康习惯（喝水 / 走动）

- [ ] 控制中心左侧「喝水」「久坐」不再显示「即将推出」，进入后有指标卡、记录按钮、设置与柱状图。
- [ ] 点「喝了一杯水」→ 今日杯数 +1、柱状图当天柱升高、桌宠头顶弹出「咕嘟咕嘟，+1 杯！」，约 6 秒后消失。
- [ ] 点「起来走走」→ 今日起身次数 +1，桌宠弹出「走一走真舒服～」。
- [ ] 桌宠面板「今日概览」显示实时杯数/起身次数，并有「喝水」「走动」快捷按钮。
- [ ] 控制中心侧栏「喝水」摘要显示「今日 X/Y 杯」，「久坐」显示「已起身 X 次」。
- [ ] 在工作日、打卡工作时段内，距上次记录超过间隔后收到系统通知，桌宠表情变为 🥵（该喝水）/ 😤（该起身）。
- [ ] 记录后对应表情恢复；关闭「启用提醒」后不再提醒。
- [ ] 非工作日 / 休假 / 工作时段外不提醒。
- [ ] 修改目标或间隔后立即生效并写入 `health.json`；重启应用后保留。
- [ ] 删除或损坏 `health.json` → 重启后自动备份并重建，打卡数据不受影响。
- [ ] 打卡全部既有行为无回归。
```

- [ ] **Step 3: Commit**

```bash
git add README.md docs/verification.md
git commit -m "docs: document health habit tools"
```

---

### Task 14: Full verification

- [ ] **Step 1: Run the complete test suite**

Run: `swift test`
Expected: all tests PASS (existing suite + `HealthRulesTests`, `HealthStoreTests`, `HealthStatisticsTests`, expanded `PetMoodTests`).

- [ ] **Step 2: Release build**

Run: `make build`
Expected: release build succeeds.

- [ ] **Step 3: Assemble the app**

Run: `make app`
Expected: `build/Daka.app` is produced and signed.

- [ ] **Step 4: Manual smoke test**

Run: `make install` then launch `/Applications/Daka.app`.
Expected: the checks in `docs/verification.md` → `v11：健康习惯` pass. (If `make install` needs permission or is not desired, run `open build/Daka.app` instead and perform the same checks.)

- [ ] **Step 5: Final commit (only if Step 4 produced fixes)**

```bash
git add -A
git commit -m "fix: address health habit verification feedback"
```

---

## Self-Review

**Spec coverage:**
- Data models (`HealthSettings`/`DayHealthRecord`/`HealthData`) → Task 1.
- `HealthRules.status` with workday/window/skipped/interval logic → Task 2.
- `HealthStore` with atomic write + corruption recovery → Task 3.
- `HealthStatistics` + streaks → Task 4.
- `PetMood` `.thirsty`/`.restless`, priority hard > gentle > health > time → Task 5.
- Generic `GentleNotifier.notify(id:title:body:)` → Task 6.
- `HealthReminderController` interval reminders → Task 7.
- `AppModel` state, log/settings methods, `petSpeech`, startup wiring, corruption warning → Task 8.
- Pet speech bubble (separate click-through floating window) + hide on pet hide → Task 9.
- Pet face reflects health → Task 10.
- `WaterToolView`/`MovementToolView` + charts + goal lines + settings → Task 11.
- Sidebar summaries + panel summaries + quick buttons → Tasks 11-12.
- Tests + docs → Tasks 2-5, 13, 14.

**Placeholder scan:** No TBD/TODO; every code step contains complete code.

**Type consistency:** `HealthStatus` fields (`cups`, `stands`, `minutesSinceDrink`, `minutesSinceStand`, `waterDue`, `movementDue`, `active`) and `.idle` are used consistently in Tasks 5, 8, 10, 11. `HealthSettings` field/method names (`effectiveWaterIntervalMinutes`, `setWaterGoalCups`, etc.) match across Tasks 2, 8, 11. `HealthStore.log(_:at:calendar:)` and `HealthLogKind` match Tasks 3 and 8. `HealthSummary` fields match Tasks 4 and 11. `PetWindowController.showSpeech`/`hideSpeech` match Tasks 8, 9, 10.
