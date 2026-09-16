# Daka：菜单栏打卡圆环显示「已工作时长进度」设计

日期：2026-09-16
状态：已确认（待实现）

## 1. 目标

菜单栏下拉面板（及工具面板）里的圆形打卡按钮，默认态不再是一个空环，而是直接反映**今天已工作时长的进度**：例如最少工时 8 小时，上班打卡后已过 4 小时，圆环填充 50%，圆心显示 `4h`。长按 3 秒打卡的交互保持不变。

## 2. 现状

`Sources/Daka/PunchButton.swift`：

- `PunchPressModel` 用计时器在长按期间把 `progress` 从 0 填到 1（时长 3 秒），松开归零。
- 圆环 `trim(from: 0, to: press.progress)`，默认 `progress = 0`，即空闲时永远是空环。
- 圆心文字恒为任务标题（`上班` / `下班`）。
- 环色：`task == .morning` 绿，否则蓝。

`PunchButton` 同时被 `MenuBarView`（菜单栏下拉）和 `ToolPanelView`（工具面板）复用。

`Scheduler` 的 `onStateChange` 只在提醒状态变化或跨天时触发，无法驱动「随时间增长的进度」持续刷新。

## 3. 进度语义

定义「已工作时长」：

```
起点 = record.morningDoneAt              // 未打上班卡则无意义
终点 = PunchRules.effectiveEveningPunch(record, minWorkDuration) ?? now
已工作时长 = max(0, 终点 - 起点)
```

- 未打上班卡：进度 `0`，无专属时长。
- 已打上班卡、未完成下班：进度 = `min(1, 已工作时长 / minWorkDuration)`。
  - `minWorkDuration <= 0` 时视为 `1`（避免除零）。
- 下班打卡完成：进度 `1`。
  - 合格下班卡可能早于 `now`，所以完成态显示的是**实际总时长**（终点取合格下班卡），而非 `now - 起点`。

## 4. 圆环与圆心显示

| 状态 | 环进度 | 环色 | 圆心文字 |
|---|---|---|---|
| 未打上班卡 | 0 | 上班绿 | 任务标题（`上班`） |
| 已上班、未完成下班 | 已工作时长 / 最少工时（≤100%） | 下班蓝 | 已工作时长（`4h` / `4.5h` / `45m`） |
| 下班完成 | 100% | 绿 | 当天实际总工作时长 |

时长文案格式：

- `< 1 小时`：整数分钟 + `m`（如 `45m`）。
- `≥ 1 小时`：整点显示 `4h`，否则一位小数 `4.5h`。

## 5. 长按交互（不变）

- 按住：环从 0 重新填到 100%（3 秒进度），圆心切回任务标题（`上班` / `下班`），环色按任务（上班绿 / 下班蓝）。
- 松开：环与圆心恢复为空闲态（§4）。
- 完成 3 秒：照常触发对应打卡。

即：按压期间显示的是「3 秒按压进度」，空闲时显示「已工作时长进度」。

## 6. 刷新机制

圆环用 `TimelineView(.everyMinute)` 包裹，每分钟重算进度，保证小时数随时间走动。不改动 `AppModel` / `Scheduler` 的发布节奏。

- 用 `.everyMinute` 而非 `.periodic(from: .now, by: 60)`：后者会在每次外层视图重绘时以 `.now` 重新锚定，若有更短的无关发布（如 30 秒一次的健康状态）不断重绘，60 秒周期永远不到期、不会自行触发。`.everyMinute` 按墙上时钟对齐分钟边界，不受重绘影响。
- 由于 `TimelineView` 只重跑内容闭包、不会重建外层视图，传入的 `now` 值会过期；因此 `PunchButton` 取一个 `nowProvider: () -> Date`（调用点传 `{ model.now }`），在闭包内实时取值。
- 空闲态每次重算纯函数，开销可忽略。
- `MenuBarExtra` 面板打开时可见即刷新；关闭时不渲染，无需刷新。

## 7. 核心类型与 API（`DakaCore`，可测）

新增 `Sources/DakaCore/WorkProgress.swift`：

```swift
public enum WorkProgress {
    /// 实际工作时长；未打上班卡时 nil。
    /// 完成态取合格下班卡为终点，否则取 now。
    public static func elapsed(_ record: DayRecord,
                               now: Date,
                               minWorkDuration: TimeInterval) -> TimeInterval?

    /// 圆环进度 0...1；未打上班卡为 0，最少工时为 0 时视为 1。
    public static func fraction(_ record: DayRecord,
                                now: Date,
                                minWorkDuration: TimeInterval) -> Double

    /// 显示文案：`4h` / `4.5h` / `45m`。
    public static func hoursText(_ interval: TimeInterval) -> String
}
```

`elapsed` 复用 `PunchRules.effectiveEveningPunch`，不新增打卡规则。

## 8. 应用层改动

- `Sources/Daka/PunchButton.swift`（改）：
  - 新增空闲态计算：`WorkProgress.fraction` / `elapsed` / `hoursText`。
  - 圆环 `trim` 取 `press.progress`（按压中）或空闲进度。
  - 圆心文字：按压中 → 任务标题；空闲 → §4 规则。
  - 环色：按压中按任务；空闲完成态绿；空闲未完成按任务。
  - `TimelineView(.everyMinute)` 包裹圆环内容。
  - 下方说明文字 `长按 3 秒打卡（可重复）` 不变。
- `Sources/DakaCore/WorkProgress.swift`（新增）。
- `MenuBarView`、`ToolPanelView` 两个调用点补传 `record` / `nowProvider` / `minWorkDuration`（见 §8.1）。

### 8.1 `PunchButton` 接口调整

当前签名 `PunchButton(task:onComplete:)`，改为同时接收渲染所需数据：

```swift
struct PunchButton: View {
    let task: PunchTask
    let record: DayRecord
    let nowProvider: () -> Date
    let minWorkDuration: TimeInterval
    let onComplete: (PunchTask) -> Void
}
```

`MenuBarView` 与 `ToolPanelView` 两处调用点补传 `model.record` / `{ model.now }` / `model.minWorkDuration`。

## 9. 范围说明

`PunchButton` 为共享组件，菜单栏下拉与工具面板会得到一致行为。本设计按此实现；若后续只需菜单栏变化，再拆分为两个展示模式。

## 10. 测试

`Tests/DakaCoreTests/WorkProgressTests.swift`（新增）：

- 未打上班卡：`elapsed == nil`，`fraction == 0`。
- 上班后 now−start 为 4h、min 8h：`fraction == 0.5`。
- 超过最少工时（如 10h / 8h）：`fraction == 1`（封顶，不溢出）。
- 完成态：终点取合格下班卡，`elapsed` 为 morning→合格下班卡；`fraction == 1`。
- 多次下班卡、其中较晚一张才合格：取合格的那张。
- `minWorkDuration == 0`：`fraction == 1`。
- `hoursText`：`45m`、`4h`、`4.5h`；负值按 `0m`。

UI 行为（环色、按压切换、每分钟刷新）手动验证。

## 11. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`docs/verification.md`。
