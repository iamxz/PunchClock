# Daka 排期 v2：打卡窗口 + 温和/强制两级提醒 设计

日期：2026-09-15
状态：已确认（待实现）
取代：`2026-09-14-mac-daka-design.md` 中 §4（打卡规则）与 §8（菜单栏）中的时间相关部分；其余（§5 组件、§6 持久化、§9 限制）继续有效。

## 1. 目标变更

原来的模型是「09:00 / 18:30 到点即全屏」。新模型引入**打卡窗口**与**两级提醒**：

- 上班窗口：**09:00 – 09:30**
- 下班窗口：**18:00 – 18:30**

窗口内未打卡 → **温和提醒**（菜单栏警示 + 系统通知，每 2 分钟一次，不阻塞）。
窗口结束仍未打卡 → **全屏强制**，每 2 分钟重弹，直到打卡完成。

另新增：**定点启动**（到窗口时间自动拉起应用）与**单实例保护**。

## 2. 精确规则

设 `now`、`settings`、`record`（当日记录）。

**基础开关**（沿用 v1）：`!settings.enabled`、`record.skipped`、非工作日 → 当天不提醒。
工作日由 `settings.workdays`（Sun=1…Sat=7，默认 Mon–Fri）判断。

**两级待办**（`ScheduleEvaluator.pendingReminders`）：

对每个任务 `task ∈ {morning, evening}`，令窗口开始 `start`、截止 `deadline`：

- 若 `record.isDone(task)` → 无提醒。
- 否则若 `now >= deadline` → `PendingReminder(task, .hard)`。
- 否则若 `now >= start`（且 `< deadline`）→ `PendingReminder(task, .gentle)`。
- 否则（早于窗口）→ 无提醒。

返回 `[PendingReminder]`（可同时包含两个任务，等级可不同）。

**提醒通道优先级**（`Scheduler`）：

- `hard` 非空 → 全屏遮罩，只展示 hard 任务；不发送温和通知。
- 否则 `gentle` 非空 → 温和提醒（菜单栏 + 通知），每 `reminderIntervalSeconds`（默认 120s）一次。
- 否则 → 隐藏（关遮罩、清除菜单栏警示）。

**开机/登录**：不做特殊强弹。`Scheduler.start()` 立即评估一次：
- 早于窗口（如 08:00 开机且上班未打卡）→ **不弹窗**，仅菜单栏显示待办；到 09:00 自动开始温和提醒。
- 窗口内 → 温和提醒。
- 已过截止 → 全屏。

（这取代 v1 的 `launchForced` / `launchPromptEarliest` 机制，一并删除。）

**退出拦截**：仅在存在 **hard** 任务时禁用退出（`applicationShouldTerminate` 返回 `.terminateCancel`）。温和窗口内允许退出（09:30 / 18:30 的定点启动会重新拉起）。

## 3. 定点启动

用 `~/Library/LaunchAgents/com.xue.daka.schedule.plist`：

- `Label = com.xue.daka.schedule`
- `ProgramArguments = ["/usr/bin/open", "-b", com.xue.daka]` —— 已运行则只激活，不产生第二实例。
- `RunAtLoad = false`（登录启动由既有 `SMAppService` 负责）。
- `StartCalendarInterval` = 四个时间：`09:00`、`09:30`、`18:00`、`18:30`（跟随设置里的窗口开始/截止；窗口开始时拉起以便温和提醒，截止时拉起以便全屏）。
- 安装：写 plist → `launchctl bootout gui/<uid>/com.xue.daka.schedule`（忽略错误）→ `launchctl bootstrap gui/<uid> <plist>`。
- 设置变更（时间/开关）后重写并 reload。
- 仅在以 `.app` bundle 运行时安装；`swift run` 下跳过。

**开机自启**（沿用 v1）：`SMAppService.mainApp` 登录项；失败时回退写 `~/Library/LaunchAgents/com.xue.daka.plist`（RunAtLoad）。

## 4. 单实例保护

启动早期检查 `NSRunningApplication.runningApplications(withBundleIdentifier:)`：若存在其它 PID，则激活它并 `exit(0)`。防止直接双击二进制/脚本启动导致的重复菜单栏图标与重复遮罩。

## 5. 数据模型变更（`Settings`）

```jsonc
{
  "enabled": true,
  "workdays": [2,3,4,5,6],
  "morningWindowStart": "09:00",
  "morningDeadline":    "09:30",
  "eveningWindowStart": "18:00",
  "eveningDeadline":    "18:30",
  "reminderIntervalSeconds": 120
}
```

移除：`morningTime`、`eveningTime`、`launchPromptEarliest`。

**向后兼容**：`Settings` 采用 `decodeIfPresent(...) ?? 默认值` 的自定义解码，旧 `data.json` 直接以新默认值加载（不视为损坏、不丢历史）。`DayRecord`/`DakaData` 不变。

## 6. 核心类型变更

```swift
public enum ReminderLevel: Equatable, Sendable { case gentle, hard }

public struct PendingReminder: Equatable, Sendable {
    public let task: PunchTask
    public let level: ReminderLevel
}

public struct ReminderState: Equatable, Sendable {
    public var gentle: [PunchTask]
    public var hard: [PunchTask]
    public var isEmpty: Bool { gentle.isEmpty && hard.isEmpty }
}
```

`ScheduleEvaluator.pendingReminders(now:settings:record:calendar:) -> [PendingReminder]`（取代 `pendingTasks`）。

`Scheduler`：
- 删除 `launchForced`/`launchDayKey`/`consumeLaunchForceIfNeeded`。
- `onStateChange: ((ReminderState) -> Void)?`。
- `presenter: ReminderPresenting`。

```swift
public protocol ReminderPresenting: AnyObject {
    func showHard(tasks: [PunchTask], settings: Settings, now: Date)
    func showGentle(tasks: [PunchTask], settings: Settings, now: Date)
    func refresh(settings: Settings, now: Date)
    func hide()
}
```

`Scheduler.apply` 依据 `hard`/`gentle` 优先级调用 `showHard`/`showGentle`/`hide`；状态未变时调用 `refresh`。

**可测试的纯逻辑**：`LaunchAgentPlist.make(settings:bundleID:) -> String` 放在 `DakaCore`，供单测断言生成的 plist 内容；`ScheduledLaunchManager`（app target）负责写文件与 `launchctl`。

## 7. 应用层变更

- `ReminderController`：实现 `showHard`（全屏，沿用 v1 行为）/`showGentle`/`refresh`/`hide`。
  - `showGentle`：投递本地通知（`UNUserNotificationCenter`）并更新菜单栏等级；记录 `lastNotifyAt`。
  - `refresh`：若当前为 gentle 且距上次通知 ≥ `reminderIntervalSeconds`，再投递一次，更新 `lastNotifyAt`；屏幕参数变化时重建窗口。
  - 通知权限在启动时请求一次；未授权则温和提醒退化为仅菜单栏警示。
- `AppModel`：`@Published private(set) var reminderState: ReminderState`；`hasPendingTasks`（任一等级）与 `hasHardTasks`；`onStateChange` 更新之。设置项改为 4 个时间；改动后重建 `ScheduledLaunchManager`。
- `MenuBarView`：显示上班/下班窗口与截止、当前等级；4 个 `DatePicker`。
- `DakaApp`：菜单栏图标三态 —— 无待办（正常）、有 gentle（铃铛/橙色）、有 hard（警示/红色）。
- `AppDelegate`：单实例保护；仅在 `hasHardTasks` 时拦截退出。
- `NotificationPresenter`（或并入 `ReminderController`）：封装 `UNUserNotificationCenter`，首次启动请求授权。

## 8. 限制

- LaunchAgent 需要用户**已登录**且 Mac **处于唤醒**（或唤醒后补跑）；不会把 Mac 从睡眠唤醒（需 `pmset` + 管理员权限，不做）。
- 系统通知需用户授权；未授权时温和提醒仅体现在菜单栏（全屏强制不受影响）。

## 9. 测试

- `ScheduleEvaluator`（两级边界，重点）：
  - 08:59 → 无；09:00 → gentle；09:29 → gentle；09:30 → hard；09:31 → hard。
  - 17:59 → （仅上班相关）；18:00 → evening gentle；18:30 → evening hard。
  - 混合：19:00 两项都未做 → 两项 hard；18:10 上班未做且下班未做 → morning hard + evening gentle。
  - 已完成 / 跳过 / 停用 / 周末 → 无。
  - 非法时间字符串的处理与 v1 一致（该任务视为不可解析，不产生对应提醒）。
- `Scheduler`：hard 优先于 gentle；`onStateChange` 状态与等级；状态稳定时只 `refresh`；跨天触发回调。
- `LaunchAgentPlist`：断言 Label、`/usr/bin/open`、`-b`、bundleID、四个 `Hour/Minute`、无 `RunAtLoad`。
- `Settings`：旧 JSON（含 `morningTime` 等旧键）能加载并得到新默认值；新 JSON 往返一致。
- 手动：launchctl 加载生效、09:00/18:00 拉起、截止时间升级为全屏、通知授权与否的表现、单实例。

## 10. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`docs/verification.md`。
