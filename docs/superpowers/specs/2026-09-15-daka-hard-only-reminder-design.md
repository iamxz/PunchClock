# Daka v12：单一强提醒 + 可配置重复间隔设计

日期：2026-09-15
状态：已确认（待实现）
在 v2（`2026-09-15-daka-schedule-v2-design.md`）「时间窗口 + 两级提醒」基础上，**删除轻提示**，改为「进入窗口即全屏强提醒，按可配置间隔重复，直到完成」。v3 统计口径、v4 多条打卡、v11 今日补卡均不变。

## 1. 目标

- **删除两级提醒机制**：不再有「温和提醒（系统通知 + 菜单栏铃铛）」与「强制提醒」之分。
- 进入上班 / 下班窗口的**开始时间**立即触发**全屏强提醒**。
- 强提醒按**可配置间隔**重复置顶弹出，**直到该任务完成**才停止。
- 截止时间不再决定提醒级别，仅保留用于统计「缺卡」。

## 2. 提醒判定（`ScheduleEvaluator`）

对每个任务（上班 / 下班）独立判定是否「待打卡」：

```
待打卡 = settings.enabled
      && 工作日(now)
      && !record.skipped
      && 该任务未完成
      && now >= 该任务窗口开始时间
```

- 上班完成 = `record.morningDone`（至少一条上班卡）。
- 下班完成 = `PunchRules.isEveningComplete`（满足最少工时的下班卡）。
- 不再需要窗口截止时间（`morningDeadline` / `eveningDeadline`）参与判定；时间无法解析时视为该任务不提醒。
- API 由返回 `[PendingReminder]` 改为返回待打卡任务列表：

```swift
public func pendingReminders(now: Date,
                             settings: Settings,
                             record: DayRecord,
                             calendar: Calendar = .current) -> [PunchTask]
```

## 3. 模型精简

- 删除 `ReminderLevel` 枚举。
- 删除 `PendingReminder` 结构体。
- `ReminderState` 简化为待打卡任务集合：

```swift
public struct ReminderState: Equatable, Sendable {
    public var pending: [PunchTask]
    public init(pending: [PunchTask] = [])
    public var isEmpty: Bool { pending.isEmpty }
    public func contains(_ task: PunchTask) -> Bool
}
```

## 4. 调度（`Scheduler`）

- `tick` 取 `pendingReminders`，构造 `ReminderState(pending:)`。
- `apply`：非空 → `presenter.showHard(tasks:)`；空 → `presenter.hide()`；稳定态 → `presenter.refresh(...)`。
- 删除 gentle 分支与 `showGentle`。状态变化 / 跨天仍触发 `onStateChange`。

## 5. 呈现（`ReminderController`）

- `ReminderPresenting` 协议删除 `showGentle`。
- `ReminderController` 删除 `showGentle`、`gentleTasks`、`lastNotifyAt` 与通知逻辑；删除对 `GentleNotifier` 的依赖。
- `showHard`：全屏遮罩窗口置顶 + 启动「置顶重弹」计时器。
- **间隔即时生效**：`refresh(settings:now:)` 中，若 `settings.effectiveReminderIntervalSeconds` 与当前计时器间隔不同，则重启计时器。
- `hide` 停止计时器、隐藏窗口。
- 删除 `Sources/Daka/GentleNotifier.swift`。

## 6. 设置与模型（`Settings` / `AppModel`）

- 保留 `Settings.reminderIntervalSeconds`（内部以秒存储，默认 120）。
- 「打卡时间」设置页新增「重复提醒」项：`Stepper` 分钟数 **1–60，默认 2 分钟**，写入 `reminderIntervalSeconds = minutes * 60`。
- `AppModel` 新增：

```swift
func setReminderIntervalMinutes(_ minutes: Int)   // 钳制 1...60，写秒
```

- 「窗口截止」字段保留（用于缺卡统计），在设置页加以说明。

## 7. 界面联动

- 菜单栏图标改为两态（`DakaApp`）：有待打卡 → `exclamationmark.triangle.fill`；否则 `checkmark.seal`。去掉 `bell.badge`。
- 菜单栏面板状态行（`MenuBarView`）：窗口内显示「待打卡 start–deadline」，过截止显示红色「已过截止 deadline」；两者都是强提醒。去掉 gentle 分支。
- 桌宠表情（`PetMood`）：`gentlePending` / `hardPending` 合并为单一 `punchPending`（😰）；`resolve` 只要 `!pending.isEmpty` 即返回 `.punchPending`。

## 8. 边界

- 任务完成即 `hide`；另一任务到其窗口开始再弹。
- 休假 / 禁用 / 非工作日不提醒。
- 当天不完成会一直重复，直到跨天自动重置（与现有 hard 行为一致）。
- 「定点拉起」「开机自启」触发的首次 tick 若处于窗口内，会直接显示全屏强提醒，符合预期。

## 9. 测试

- `ScheduleEvaluator`：窗口开始即待打卡；未到开始无；完成 / 休假 / 禁用 / 非工作日无；过截止仍待打卡（不再区分级别）。
- `Scheduler`：窗口开始 `showHard`、完成后 `hide`、稳定 `refresh`、跨天回调。
- `PetMood`：pending 覆盖时间与健康。
- 更新所有引用 `ReminderLevel` / `gentle` 的现有测试与 `SpyPresenter`。

## 10. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`README.md`（去掉轻提示、菜单栏铃铛、系统通知描述）、`docs/verification.md`。
