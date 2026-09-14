# Daka — macOS 打卡提醒应用设计

日期：2026-09-14
状态：已确认（待实现）

## 1. 目标

一个常驻 macOS 菜单栏的小应用，在工作日提醒并强制用户完成两次本地打卡：

- **上班打卡**：默认 09:00
- **下班打卡**：默认 18:30

到点未打卡时，弹出**无法关闭的全屏遮罩**，直到点击「打卡」按钮。每 2 分钟兜底重弹/置顶。开机（登录）时若当天上班未打卡，立即弹全屏催打卡。

打卡为**纯本地记录**，不连接任何公司系统、不打开网页、不执行外部脚本。

## 2. 非目标

- 不集成公司考勤系统、不调用任何网络接口。
- 不做节假日日历（仅按星期判断；提供手动「今天不打卡」跳过）。
- 不尝试完全锁死系统（见 §9 限制）。

## 3. 应用形态与技术选型

- 名称 `Daka`，Bundle ID `com.xue.daka`。
- 菜单栏应用：`LSUIElement = 1` / `NSApp.setActivationPolicy(.accessory)`，无 Dock 图标。
- 技术栈：Swift 6 + SwiftUI + AppKit。
- 工程管理：SwiftPM（`Package.swift`）。
- 构建产物：`make app` 脚本组装 `Daka.app`（生成 `Info.plist`、ad-hoc `codesign`）并安装到 `/Applications`。
- 开机自启：优先 `SMAppService.mainApp.register()`；若失败回退写 `~/Library/LaunchAgents/com.xue.daka.plist`。首次启动时注册一次，注册结果在菜单栏可见。

## 4. 打卡规则（精确语义）

设 `now`、`settings`、`record`（当日记录）。

**工作日判断**：`weekday(now)` ∈ `settings.workdays`（默认周一至周五，`Calendar` 中 Mon=2 … Fri=6）。

**基础待办（`ScheduleEvaluator.pendingTasks`）**：

1. 若 `!settings.enabled` → 返回空。
2. 若 `record.skipped`（今天不打卡）→ 返回空。
3. 若 `now` 不是工作日 → 返回空。
4. `morningPending = !record.morningDone && now >= 今天 morningTime`
5. `eveningPending = !record.eveningDone && now >= 今天 eveningTime`
6. 返回上述为真的项（可同时两项）。

**开机强制项（`launchPending`）**：在应用启动/登录时额外评估一次——

- 条件：`settings.enabled && !record.skipped && 工作日 && !record.morningDone && now >= 今天 launchPromptEarliest(默认 06:00)`
- 满足则把 `morning` 加入待办，**即使 `now < morningTime`**。
- `launchPromptEarliest` 用于避免凌晨重启时的无意义弹窗；到 6 点前不弹，9 点定时器仍会正常触发。

**提醒循环**：

- `Scheduler` 每秒评估一次 `pendingTasks(now)`（含 `launchPending` 的一次性注入）。
- 待办非空 → 显示全屏遮罩；为空 → 关闭遮罩。
- 遮罩显示期间，每 `reminderIntervalSeconds`（默认 120 秒）执行一次兜底：重定位窗口、抬升层级、重新激活应用。
- 遮罩中每个待办项一个按钮；点击某项 → `PunchStore` 写入 → 立即重新评估。全部完成后关闭遮罩。

**跨天**：日期变化时自动切换到新 `DayRecord`；历史保留。

## 5. 组件划分

每个组件单一职责，彼此通过明确接口通信：

| 组件 | 职责 | 依赖 |
|---|---|---|
| `DakaClock`（协议）+ `SystemClock` | 提供 `now`；测试可注入固定时钟 | 无 |
| `Settings` | 配置模型（时间、工作日、开关、间隔）与读写 | `PunchStore` 的存储层 |
| `DayRecord` | 单日状态数据模型 | 无 |
| `ScheduleEvaluator` | **纯函数**：`(now, settings, record, launchForced) -> [PunchTask]` | 无（无 UI/IO） |
| `PunchStore` | 持久化 `Settings` 与 `DayRecord` 历史；原子写、损坏恢复 | 文件系统 |
| `Scheduler` | 定时 tick、监听唤醒/时间变更、驱动提醒、按间隔兜底重弹 | `DakaClock`、`ScheduleEvaluator`、`PunchStore`、`ReminderController` |
| `ReminderController` | 创建/管理每屏一个的全屏遮罩窗口；抬升层级、跨 Space、拦截关闭快捷键 | AppKit |
| `MenuBarView` | 菜单栏：今日状态、手动补打卡、时间设置、今天不打卡、调试模拟时间、退出 | `PunchStore`、`Scheduler` |
| `LoginItemManager` | 开机自启注册/注销与状态查询 | `SMAppService` / LaunchAgent |

## 6. 数据模型与持久化

存储位置：`~/Library/Application Support/Daka/data.json`。

```jsonc
{
  "settings": {
    "enabled": true,
    "workdays": [2, 3, 4, 5, 6],          // Mon..Fri
    "morningTime": "09:00",
    "eveningTime": "18:30",
    "launchPromptEarliest": "06:00",
    "reminderIntervalSeconds": 120
  },
  "records": {
    "2026-09-14": {
      "date": "2026-09-14",
      "morningDone": true,
      "morningDoneAt": "2026-09-14T09:01:12+08:00",
      "eveningDone": false,
      "eveningDoneAt": null,
      "skipped": false
    }
  }
}
```

- `records` 以 `yyyy-MM-dd` 为键，保留全部历史。
- 写入采用「写临时文件 + 原子替换」，避免半写损坏。
- 读取失败/JSON 损坏 → 将原文件重命名为 `data.json.corrupt-<时间戳>` 备份，重建空存储，并在菜单栏提示。
- 写盘失败 → 菜单栏显示错误，不静默；内存状态仍可用。

## 7. 全屏遮罩行为

- `NSWindow`：无边框，`level = .screenSaver`，`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`。
- 每个 `NSScreen` 一个窗口，frame = 该屏 `frame`；显示器热插拔时重建。
- `canBecomeKey = true`，`makeKeyAndOrderFront`，`NSApp.activate(ignoringOtherApps: true)`。
- 内容：大号提示（“该上班打卡了” / “该下班打卡了” / 两项同时欠账时并列）、当前时间、欠账时长、对应「打卡」按钮。
- **拦截关闭**：
  - 无关闭按钮 / 无取消按钮；`keyDown` 吞掉 ESC（`cancelOperation`）与 Cmd+W / Cmd+M / Cmd+H。
  - `NSApplicationDelegate.applicationShouldTerminate` 在有待办时返回 `.terminateCancel`，并移除 Quit 菜单项。
- 无法被常规方式绕过；每 2 分钟兜底重弹（§4）。

## 8. 菜单栏界面

- `MenuBarExtra(style: .window)`，图标随状态变化（正常 / 待打卡红点）。
- 显示今日两项状态（已完成时间 或 待办）。
- 「上班打卡」「下班打卡」手动按钮（用于补卡）。
- 「今天不打卡」开关（仅当天有效，跨天自动清除）。
- 设置：上班时间、下班时间、启用开关。
- 调试（可通过设置隐藏）：「模拟时间」用于免等待验证遮罩。
- 自启状态显示与修复入口。
- 退出：仅在无待办时可用；有待办时置灰并说明原因。

## 9. 已知限制（明确声明）

- macOS 不允许普通应用完全锁死系统：**强制退出（Cmd+Opt+Esc / `kill -9`）无法被屏蔽**。
- 因此「无法绕过」指：置顶全屏、禁止 ESC/关闭按钮、阻止 Cmd+Q、每 2 分钟重弹；不包含阻止强制退出。
- 若要 100% 不可绕过需启用系统级「引导式访问 / 单应用模式」，会锁死整机，本应用不采用。

## 10. 容错与边界

- **休眠唤醒**：监听 `NSWorkspace.didWakeNotification`，唤醒后立即重算待办并显示。
- **系统时间/时区变更**：监听 `NSSystemClockDidChange` 与 `NSSystemTimeZoneDidChange`，重算。
- **跨天**：以日历日切换 `DayRecord`。
- **多显示器**：每屏一个遮罩；热插拔重算。
- **未到 6 点重启**：不因开机强制弹窗（`launchPromptEarliest`）。
- **数据损坏**：备份并重建（§6）。

## 11. 测试策略

**自动化（`swift test`）**

- `ScheduleEvaluator`（纯函数，重点）：
  - 未到上班时间 → 无待办；到点未打卡 → 上班待办。
  - 18:30 后上班未打卡 → 仅上班；上班已打、下班未打 → 仅下班；两项都欠 → 两项。
  - 周末 / 非工作日 → 无待办（即使未打卡）。
  - `enabled = false` / `skipped = true` → 无待办。
  - `launchForced` 在 `now < morningTime` 时仍返回上班待办；`now < launchPromptEarliest` 时不返回。
  - 边界：`now == morningTime` 视为已到点。
- `PunchStore`：
  - 写入/读取往返一致；`Settings` 与历史记录持久化。
  - 损坏 JSON → 备份生成、存储重建、不抛异常。
  - 跨天 → 生成新的 `DayRecord`，旧记录保留。
  - 原子写：替换后文件内容完整。
- `DakaClock` 注入固定时间，测试不依赖真实时钟。

**手动检查清单**

- 多显示器：每屏都出现遮罩，图标位置正确。
- 覆盖在其它应用的全屏 Space 之上。
- 遮罩期间 ESC / Cmd+W / Cmd+Q 不生效。
- 休眠数分钟后唤醒，立即弹出正确待办。
- 登录/重启后按 §4 规则弹窗。
- 改系统时间跨越打卡点，提醒随之更新。
- 「今天不打卡」跨天恢复。

## 12. 交付物

- 可运行的 `Daka.app`，安装于 `/Applications`。
- `make` 目标：`make app`（构建+组装+签名+安装）、`make test`、`make clean`。
- 源码、`Package.swift`、构建脚本、单元测试、本设计文档。
