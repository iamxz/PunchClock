# Daka v6：休假日期标记（任意日期）设计

日期：2026-09-15
状态：已确认（待实现）
在 v5 基础上增加「按月列出每天、逐天标记休假」。其余（窗口/两级提醒、主窗口统计、重复打卡、最少工时）不变。

## 1. 问题

「今天不打卡」只能在**当天**、且电脑开着时标记。但休假当天通常不开电脑，无法标记；只能在事后（上班时）补标。需要一个能标记**任意日期**的入口。

## 2. 目标

- 可对**过去**的日期补标「休假」；可对**未来**的日期预标「休假」。
- 标记后：该天**不提醒、不计缺卡、不打断连续打卡**（沿用 `DayRecord.skipped` 语义，`ScheduleEvaluator`/`Statistics` 已支持）。
- 不依赖当天电脑开机——标记的是日期，不是「今天」这个按钮。

## 3. 界面

主窗口新增第三个标签页 **「休假」**：

- 顶部：`‹ 2026 年 9 月 ›` 月份切换（默认当前月）。
- 列表：该月每一天一行。
  - 左侧：`09-15 周二`
  - 中间状态：`休假` / `非工作日` / `已完成` / `缺卡` / `待打卡（未来）`
  - 右侧：`Toggle`（休假开关）。
- 逐天勾选 → 立即写入该日期的 `skipped`。
- 保留设置页原有的「今天不打卡」快捷开关。

## 4. 核心逻辑（`DakaCore`，可测）

```swift
public struct DayInfo: Equatable, Sendable, Identifiable {
    public let dateKey: String
    public let date: Date
    public let isWorkday: Bool
    public let skipped: Bool
    public let completedBoth: Bool
    public let isFuture: Bool
    public var id: String { dateKey }
}

public enum LeaveCalendar {
    public static func monthDays(containing month: Date,
                                 records: [String: DayRecord],
                                 settings: Settings,
                                 now: Date,
                                 calendar: Calendar = .current) -> [DayInfo]
}
```

- 枚举该自然月每一天，`isWorkday = settings.workdays.contains(weekday)`。
- `completedBoth = record.morningDone && PunchRules.isEveningComplete(record, minWorkDuration: settings.minWorkDuration)`。
- `isFuture`：当天晚于 `now` 的自然日。
- 顺序按日期升序。

## 5. 应用层

- `AppModel`：
  - `func monthDays(containing:) -> [DayInfo]`（委托 `LeaveCalendar`）。
  - `func setSkipped(_ skipped: Bool, on date: Date)`（任意日期）；现有 `setSkipped(_:)` 改为调用它并传 `clock.now`。
- 新增 `Sources/Daka/LeaveDaysView.swift`：月份切换 + 逐天 Toggle。
- `MainWindowView` 增加第三个标签页（`calendar` 图标）。

## 6. 边界

- 周末等非工作日仍可切换（无影响）；状态显示「非工作日」。
- 未来日期标休假：当天到来时 `skipped` 已为 true → 不提醒。
- 清除休假：再次关闭开关即可（`skipped = false`）。

## 7. 测试

- `LeaveCalendar.monthDays`：
  - 返回该月天数、升序、`dateKey` 正确。
  - 工作日/非工作日标记正确。
  - 已休假 → `skipped == true`；已完成（含最少工时合格）→ `completedBoth == true`；仅上班未合格下班 → false。
  - 未来日期 `isFuture == true`。
- `PunchStore.setSkipped(_:on:)` 已有测试；补一个跨月日期的写入/读取。

## 8. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`docs/verification.md`。
