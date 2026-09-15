# Daka v3：应用主窗口 + 统计 + 精简状态栏 设计

日期：2026-09-15
状态：已确认（待实现）
在 v2（`2026-09-15-daka-schedule-v2-design.md`）基础上，改应用形态与信息架构；v2 的时间窗口与两级提醒规则不变。

## 1. 目标

把「设置 / 统计」从状态栏菜单挪进**独立的应用主窗口**；状态栏只保留「今天是否已打卡 + 打卡按钮」，保持简洁。

- 应用本体：常规应用（Dock 图标 + 主窗口）。
- 状态栏：极简面板。
- 统计：打卡天数、连续天数、平均上班时长、缺卡、以及每日上班时长曲线。

## 2. 应用形态与窗口生命周期

- `NSApp.setActivationPolicy(.regular)`：Dock 有图标，可打开主窗口。
- 主窗口用自管理的 `NSWindow`（`NSHostingView` 承载 SwiftUI `MainWindowView`），非 SwiftUI `WindowGroup`——便于「关闭即隐藏、随时重开」，且与现有 `MenuBarExtra` 共存。
- **关闭主窗口不退出应用**：拦截 `windowShouldClose` → `orderOut`，窗口对象保留。
- `applicationShouldTerminateAfterLastWindowClosed` → `false`。
- **再次打开**：
  - 点 Dock 图标（应用已运行且无可见窗口）→ `applicationShouldHandleReopen` → 显示主窗口；
  - 菜单栏面板「打开 Daka」→ 显示主窗口。
- **后台启动不弹窗**：
  - 定点拉起用 `open -b <id> --args --background`；启动参数含 `--background` → 不显示主窗口。
  - 登录项启动（`SMAppService`）→ 依据 `applicationDidFinishLaunching` 通知的 `NSApplicationLaunchIsDefaultLaunchKey` 判断非用户启动 → 不显示主窗口。
  - 用户手动启动（Finder/Dock）→ 显示主窗口。
- 退出：`applicationShouldTerminate` 仅在 hard 阶段返回 `.terminateCancel`；主窗口关闭不影响（仍在后台提醒）。

## 3. 状态栏（极简）

- 图标三态（同 v2）：none → `checkmark.seal`；gentle → `bell.badge`；hard → `exclamationmark.triangle.fill`。
- 点击弹出的紧凑面板只含：
  - 今日「上班打卡 / 下班打卡」状态（已完成时间 / 待办 / 已完成），
  - 两个打卡按钮（未完成可点，完成置灰），
  - 「打开 Daka」按钮，
  - 「退出 Daka」（仅 hard 阶段禁用）。
- 不放入设置项、不放入统计、不放入时间选择器、不放入自启/定点状态（这些在主窗口）。

## 4. 主窗口

两个标签页（`TabView`）：**统计**（默认）、**设置**。

### 4.1 统计页

- 顶部指标卡：
  - 今日状态（上班/下班是否完成）
  - 本月打卡天数（当月工作日中两次都完成的天数）
  - 连续打卡天数
  - 平均上班时长（当天两次都完成的平均值）
  - 缺卡天数（范围内）
- 曲线：最近 N 天「每日上班时长（小时）」柱状图，Swift Charts；可切 7 / 14 / 30 天，默认 14。
- 无数据时显示占位提示（“还没有足够的打卡记录”）。

### 4.2 设置页

- 启用提醒开关。
- 工作日选择（周一至周日多选）。
- 上班窗口开始 / 截止；下班窗口开始 / 截止（4 个时间）。
- 「今天不打卡（休假）」开关。
- 开机自启状态（+ 启用/打开系统设置）；定点启动状态。
- 调试：+10 分钟 / 重置时间。
- 错误与启动警告提示。

## 5. 统计口径（精确）

输入：`records: [String: DayRecord]`、`settings`、`now`、`rangeDays`、`calendar`。

对范围内每一天（从 `now` 往前 `rangeDays-1` 天到今天）构造 `DailyStat`：

- `isWorkday` = `settings.workdays.contains(weekday(day))`。
- `completedBoth` = `record.morningDone && record.eveningDone`。
- `workDuration` = 两次都完成且 `eveningDoneAt >= morningDoneAt` 时取差值，否则 `nil`。
- `skipped` = `record.skipped`。

指标：

- **本月打卡天数**：当前自然月内，`isWorkday && completedBoth` 的天数。
- **平均上班时长**：范围内 `workDuration != nil` 的均值；无样本为 `nil`。
- **缺卡天数**：范围内 `isWorkday && !skipped && !completedBoth`，且**已过期**——即 `day` 早于今天，或就是今天且 `now >= 今天下班截止`。
- **连续打卡天数**：从起点往前逐个自然日：
  - 起点：若「今天是工作日、未跳过、未完成，且 `now < 今天下班截止`」→ 从**昨天**开始；否则从**今天**开始。
  - 遍历：非工作日或 `skipped` → 跳过（不打断）；`completedBoth` → 计数 +1；否则（工作日、未跳过、未完成）→ 停止。
- `range` = rangeDays。

## 6. 核心类型与 API（`DakaCore`，可测）

```swift
public struct DailyStat: Equatable, Sendable {
    public let dateKey: String
    public let weekday: Int
    public let isWorkday: Bool
    public let completedBoth: Bool
    public let skipped: Bool
    public let morningDoneAt: Date?
    public let eveningDoneAt: Date?
    public let workDuration: TimeInterval?
}

public struct StatisticsSummary: Equatable, Sendable {
    public var days: [DailyStat]          // 按时间升序
    public var rangeDays: Int
    public var monthPunchDays: Int
    public var currentStreak: Int
    public var averageWorkDuration: TimeInterval?
    public var missedDays: Int
}

public enum Statistics {
    public static func compute(records: [String: DayRecord],
                               settings: Settings,
                               now: Date,
                               rangeDays: Int,
                               calendar: Calendar = .current) -> StatisticsSummary
}
```

## 7. 应用层改动

- `AppDelegate`：激活策略 `.regular`；管理 `MainWindowController`；`applicationDidFinishLaunching` 按 §2 决定是否显示；`applicationShouldHandleReopen` 显示；`applicationShouldTerminateAfterLastWindowClosed` = false。
- `MainWindowController`（新增）：创建/持有主窗口，`show()`（`makeKeyAndOrderFront` + `NSApp.activate`），`windowShouldClose` → `orderOut` 返回 false。
- `MainWindowView`（新增）：`TabView`，统计页 + 设置页；由 `AppModel` 提供数据与操作。
- `StatisticsView`（新增）：指标卡 + `Charts` 柱状图 + 范围切换。
- `SettingsView`（新增）：设置页（从原 `MenuBarView` 迁移设置控件）。
- `MenuBarView`（改）：精简为 §3 内容。
- `AppModel`：新增 `statistics(rangeDays:) -> StatisticsSummary`（委托 `Statistics.compute`）；`openMainWindow()`（回调到 `MainWindowController`）。
- `DakaApp`：保留 `MenuBarExtra`；不再需要其它 Scene（主窗口由 `MainWindowController` 管理）。菜单栏命令可保留默认。
- `LaunchAgentPlist`：`ProgramArguments` 增加 `--args` `--background`（即 `[/usr/bin/open, -b, <id>, --args, --background]`）。

## 8. 图标

- 应用图标已有：`Resources/Daka.icns`（`make icon` 生成，`CFBundleIconFile = Daka`）。
- 状态栏图标沿用 SF Symbols。

## 9. 限制

- 主窗口依赖 `NSApplicationLaunchIsDefaultLaunchKey` 判断登录项启动；若系统行为变化，退化为「登录时也弹窗」或「都不弹」，届时以 `--background` 参数为准。
- 统计初期数据少，曲线为空属正常。
- 其余限制同 v2（LaunchAgent 需已登录且唤醒）。

## 10. 测试

- `Statistics.compute`（纯函数，重点）：
  - 范围长度与升序；非工作日不计缺卡；跳过日不计缺卡也不打断连续。
  - 平均时长只在两次都完成时计入；下班早于上班时 `workDuration == nil`。
  - 连续天数：连续完成、遇到未完成中断、跳过日跨过、今天未完成但未到截止不打断。
  - 本月打卡天数按自然月统计。
  - 缺卡：今天未到截止不算缺卡；过去工作日未完成算缺卡。
- `LaunchAgentPlist`：`ProgramArguments` 含 `--args`/`--background`（更新现有测试）。
- 应用层窗口/统计 UI 通过手动验证。

## 11. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`docs/verification.md`。
