# Daka：考勤规则驱动的动态下班时间（打卡时间与考勤规则合并）设计

日期：2026-09-17
状态：已确认（待实现）
取代：`2026-09-15-daka-schedule-v2-design.md` 的时间窗口部分、`2026-09-15-daka-min-work-duration-design.md` 的「最少工时」模型；重复打卡、两级提醒之外的其余行为继续有效。

## 1. 目标

打卡时间重新计算，并**移除固定打卡窗口的限定**：下班提醒不再是固定的 `18:00–18:30` 窗口，而是由「考勤规则」推导——每个用户可以配置**上班时间 / 工作时长 / 弹性时间**三个参数，下班时间随当天实际上班打卡而动态变化。

- 上班时间（标准开始时间）：`workStartTime`，默认 `09:00`
- 工作时长：`workDurationHours`，默认 `9` 小时
- 弹性时间：`flexMinutes`，默认 `30` 分钟

## 2. 精确规则

### 2.1 上班窗口与有效上班时间

- 上班打卡窗口 = `[workStartTime, workStartTime + flexMinutes]`（默认 `09:00–09:30`）。窗口仅用于上班提醒开始时间与界面展示。
- **有效上班时间** `effectiveStart`：
  - 当天无上班卡 → `nil`（无法推导下班时间）。
  - 最早上班卡 ≤ `workStartTime` → `effectiveStart = workStartTime`（早到算准点，如 `08:40` 打卡按 `09:00` 上班）。
  - 最早上班卡 > `workStartTime` → `effectiveStart = 该卡时间`（**不限于弹性窗口**；如 `09:16` 打卡 → 上班 `09:16`；`10:00` 打卡 → 上班 `10:00`）。

### 2.2 应下班时间

- `expectedLeave = effectiveStart + workDurationHours`
  - 上班 `09:00` → `18:00` 下班
  - 上班 `09:16` → `18:16` 开始提醒下班
  - 上班 `10:00` → `19:00` 开始提醒下班

### 2.3 下班完成判定

- 下班**完成** = 存在某张下班卡 `p`，满足 `p ≥ expectedLeave`。取其中**最晚**的为「有效下班卡」（`effectiveEveningPunch`）。
- **提前打的下班卡不算完成**（如 `18:10` 打卡早于 `18:16` → 继续提醒），但卡片仍保留、仍计入打卡次数。
- 当天无上班卡 → 下班永不完成（上班提醒照常）。
- 打过上班卡后：`expectedLeave` 起到之前不提醒下班；到点后持续提醒，直到打出满足 `≥ expectedLeave` 的下班卡。

## 3. 数据模型（`Settings`）与迁移

### 3.1 新设置项

```jsonc
{
  "enabled": true,
  "workdays": [2,3,4,5,6],
  "workStartTime": "09:00",
  "workDurationHours": 9,
  "flexMinutes": 30,
  "reminderIntervalSeconds": 120
}
```

- 新增 `workStartTime: String`、`workDurationHours: Double`、`flexMinutes: Int`。
- **停止使用**：`morningWindowStart`、`morningDeadline`、`eveningWindowStart`、`eveningDeadline`、`minWorkDurationHours`（保留旧 CodingKeys 仅用于解码回退）。

### 3.2 解码迁移

`Settings` 沿用自定义解码 + `decodeIfPresent`：
- `workStartTime = decode(new) ?? decode(morningWindowStart) ?? "09:00"`
- `flexMinutes = decode(new) ?? max(0, morningDeadline − morningWindowStart 分钟数) ?? 30`
- `workDurationHours = decode(new) ?? decode(minWorkDurationHours) ?? 9`

编码只写新键；下一次持久化后旧键消失，不视为损坏、不丢历史记录。

### 3.3 派生计算

`minWorkDuration`（旧）由 `workDurationHours` 取代：

```swift
public var workDuration: TimeInterval { max(0.5, workDurationHours) * 3600 }
public var flexDuration: TimeInterval { TimeInterval(max(0, flexMinutes) * 60) }
```

（`workDuration` 下限 0.5 小时避免除零/畸形配置。）

## 4. 核心推导（DakaCore 新增 `AttendanceRule`）

纯函数枚举，替换 `PunchRules` 与各处散落的 `minWorkDuration` 计算：

```swift
public enum AttendanceRule {
    /// 上班窗口开始（即 workStartTime）
    static func windowStart(_ settings:, on now:, calendar:) -> Date?
    /// 上班窗口结束 = workStartTime + flexMinutes
    static func windowEnd(_ settings:, on now:, calendar:) -> Date?
    /// 有效上班时间 = max(workStartTime, 最早上班卡)；无上班卡 → nil
    static func effectiveStart(_ record:, settings:, now:, calendar:) -> Date?
    /// 应下班时间 = effectiveStart + workDuration；无上班卡 → nil
    static func expectedLeave(_ record:, settings:, now:, calendar:) -> Date?
    /// 有效下班卡 = 最晚满足 p ≥ expectedLeave 的下班卡；否则 nil
    static func effectiveEveningPunch(_ record:, settings:, now:, calendar:) -> Date?
    static func isEveningComplete(_ record:, settings:, now:, calendar:) -> Bool
}
```

删除 `PunchRules`（其职责并入 `AttendanceRule`），所有调用点改为 `AttendanceRule`。`WorkProgress` 的 `minWorkDuration` 参数随之改为 `workDuration`/`settings`。

## 5. 各层应用

### 5.1 `ScheduleEvaluator`

- 上班：`pending(start: workStartTime)` 不变（到点即提醒，未打上班卡持续提醒）。
- 下班：`done = AttendanceRule.isEveningComplete(...)`；`start` 由固定 `eveningWindowStart` 改为 `AttendanceRule.expectedLeave(...)`（无上班卡时下班不产生待办）。

### 5.2 `Statistics`

- `completedBoth = morningDone && isEveningComplete(new rule)`。
- `eveningDoneAt = effectiveEveningPunch`（最晚合格）。
- `workDuration = effectiveEvening − 最早上班卡`（保留“实际工作时长”口径）。
- **缺卡**：
  - 非今天工作日且未完成 → 缺卡（沿用）。
  - 今天：`有上班卡 && now ≥ expectedLeave && 未完成` → 缺卡；**无上班卡 → 进行中，不算缺卡**。
- `monthPunchDays`、`currentStreak`、`todayInProgress` 改用新的完成判定与判定时点（`todayInProgress = 工作日 && !skipped && !completed && (无上班卡 || now < expectedLeave)`）。

### 5.3 `WorkProgress` / `PunchButton` / `PunchTarget`

- 圆环分母与进度目标 = `workDurationHours`（不再是最少工时）。
- `elapsed`：有合格下班卡取 `effectiveEvening − morning`，否则 `now − morning`（沿用）。
- `PunchTarget.resolve` 的下班完成判定改用新规则。

### 5.4 `PunchFeedback` / `OverlayView`

- 提示改为「距上班满 X 小时（下班时间 HH:mm）还差 …」；无上班卡时提示先打上班卡。
- 遮罩/菜单栏展示推导的应下班时间；未打上班卡显示占位（如 `--:--`）。

### 5.5 `HealthRules`

活动窗口从 `[morningWindowStart, eveningDeadline]`（默认 9:00–18:30）改为名义工时 `[workStartTime, workStartTime + workDurationHours]`（默认 9:00–18:00）。喝水/活动提醒在工作时段内触发，逻辑不变。

### 5.6 UI（`SettingsPages`）

«打卡窗口» 分组改为 «考勤规则»：
- 上班时间：`DatePicker`（`workStartTime`，hourAndMinute）
- 弹性时间：`Stepper` 分钟（0–120，步进 5，默认 30）
- 工作时长：`Stepper` 小时（0.5–12，步进 0.5，默认 9）

提示文案同步更新（下班提醒随上班卡时间浮动）。删除 4 个窗口 DatePicker 与「每日最少工时」Stepper。

`AppModel`：新增 `updateWorkStart(_:)`、`setFlexMinutes(_:)`、`setWorkDurationHours(_:)`；删除 `updateMorningStart/Deadline/EveningStart/Deadline`、`setMinWorkHours`。

### 5.7 定点启动 `LaunchAgent`

由 4 个定点（09:00/09:30/18:00/18:30）改为 3 个：
`[workStartTime, workStartTime + flexMinutes, workStartTime + workDurationHours]`（默认 09:00/09:30/18:00）。

动态下班时间（如 18:16）无法预排期：应用常驻 + 1s tick + 唤醒/时间变更 tick 处理；排期的 18:00 仅作「典型日」兜底拉起。`LaunchAgentPlist.make` 与 `ScheduledLaunchManager` 同步调整。

## 6. 测试

- `AttendanceRule`（新）：
  - 无上班卡 → `effectiveStart/expectedLeave` 为 nil、下班不完成。
  - 早到（08:40）→ effectiveStart=09:00、expectedLeave=18:00。
  - 准点/弹性内（09:00、09:16、09:30）→ effectiveStart=打卡时间、expectedLeave=+9h。
  - 晚到（10:00）→ effectiveStart=10:00、expectedLeave=19:00（无上限）。
  - 多张上班卡 → 用最早上班卡。
  - 提前下班卡（18:10 < 18:16）不完成；合格后取最晚一张为有效下班卡。
- `ScheduleEvaluator`：上班提醒仍从 workStartTime 起；下班提醒从 expectedLeave 起（晚卡推迟）；无上班卡不产生下班待办；提前下班卡仍待办。
- `Settings`：旧 JSON（含旧键/缺失新键）→ 新默认值与迁移值；往返一致；编码只含新键。
- `WorkProgress`：分母为工作时长；进度封顶 1。
- `Statistics`：缺卡（有上班卡且过 expectedLeave 未完成 vs 无上班卡进行中）、工时口径。
- `HealthRules`：活动窗口 [workStart, workStart+workDuration]。
- `LaunchAgentPlist`：3 个定点时间。
- `PunchTarget` / `PunchFeedback`：更新后的完成判定与文案。

## 7. 限制

- 动态下班时间无法写入 `LaunchAgent` 定点排期，极端场景（应用进程不在）下只能由典型时间兜底；常态依赖常驻 tick。
- 健康提醒窗口改为名义工时（9:00–18:00），不再与下班实际打卡联动。

## 8. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`docs/verification.md`。