# Daka 健康习惯（喝水 + 走动）设计

日期：2026-09-15
状态：已实现

在 v7「桌宠 + 工具框架」的基础上，把占位的「喝水」「久坐」两个工具实现为可用的**健康习惯**工具：桌宠代表使用者本人，通过**面部表情变化 + 头顶气泡说话 + 系统通知**督促喝水与起身走动，并提供每日记录与统计图表。

## 1. 目标与范围

**目标**

1. 喝水：一键记录一杯水；按间隔提醒；今日进度与历史统计。
2. 走动：一键记录一次起身走动；久坐按间隔提醒；今日进度与历史统计。
3. 桌宠：到点未完成时表情变化（渴了 / 坐不住）；提醒与完成时头顶弹出气泡说话。

**范围**

- 新增独立的健康习惯数据与逻辑（`DakaCore`），独立存储文件，不改动打卡数据与行为。
- 提醒时段跟随打卡：仅在工作日、打卡工作时段（`morningWindowStart`–`eveningDeadline`）、且打卡未关闭/未休假时生效。
- 控制中心新增两个工具详情视图；侧栏摘要、桌宠面板展示实时数据与快捷记录。

**不在范围**

- 自动感知真实喝水/活动（无传感器、无摄像头），全部手动记录。
- 节假日日历、自定义多套提醒时段、iCloud 同步。
- 护眼工具（`eye`）仍保持占位。

## 2. 数据模型

新增 `Sources/DakaCore/HealthModels.swift`，存储于 `~/Library/Application Support/Daka/health.json`（与 `data.json` 同目录）。

```swift
public struct HealthSettings: Codable, Equatable, Sendable {
    public var waterEnabled: Bool           // 默认 true
    public var waterGoalCups: Int           // 默认 8
    public var waterIntervalMinutes: Int    // 默认 60（多久没喝提醒一次）
    public var movementEnabled: Bool        // 默认 true
    public var movementGoalCount: Int       // 默认 8
    public var movementIntervalMinutes: Int // 默认 60（坐多久提醒起身）

    public static let `default` = HealthSettings(
        waterEnabled: true, waterGoalCups: 8, waterIntervalMinutes: 60,
        movementEnabled: true, movementGoalCount: 8, movementIntervalMinutes: 60)
}

public struct DayHealthRecord: Codable, Equatable, Sendable {
    public var drinks: [Date]              // 每次喝水时间
    public var stands: [Date]              // 每次起身时间
}

public struct HealthData: Codable, Equatable, Sendable {
    public var settings: HealthSettings
    public var records: [String: DayHealthRecord]   // key = yyyy-MM-dd
}
```

- 所有字段用 `decodeIfPresent` + 默认值，保证旧文件/新增字段可平滑解码。
- 间隔下限做保护（如 `max(15, minutes)`），避免异常配置刷屏。

## 3. 核心逻辑（纯函数，可单测）

新增 `Sources/DakaCore/HealthRules.swift`：

```swift
public struct HealthStatus: Equatable, Sendable {
    public let cups: Int
    public let stands: Int
    public let minutesSinceDrink: Int?
    public let minutesSinceStand: Int?
    public let waterDue: Bool
    public let movementDue: Bool
    public let active: Bool                // 当前是否处于提醒时段
}

public enum HealthRules {
    public static func status(health: HealthSettings,
                              schedule: Settings,        // 复用打卡设置：workdays / 窗口 / enabled
                              record: DayHealthRecord,
                              skipped: Bool,             // 打卡当日是否休假
                              now: Date,
                              calendar: Calendar = .current) -> HealthStatus
}
```

判定规则：

- `active`：`schedule.enabled` && `!skipped` && 今天 weekday 在 `schedule.workdays` 内 && `now` 落在 `[morningWindowStart, eveningDeadline]` 之间。
- `minutesSinceDrink`：`now - (drinks.last ?? 窗口开始时间)` 的分钟数；无记录时以窗口开始时间为基准。
- `waterDue`：`active && waterEnabled && minutesSinceDrink >= waterIntervalMinutes`。
- `movementDue`：同理，基准为 `stands.last ?? 窗口开始时间`。
- 跨天：按 `yyyy-MM-dd` 取当天记录，天然归零。

## 4. 存储

新增 `Sources/DakaCore/HealthStore.swift`，**照抄 `PunchStore` 的模式**：

- 初始化解码，失败时备份为 `health.json.corrupt-<时间戳>-<随机>` 并重建为空。
- `log(kind:at:)`：往当天 `drinks` / `stands` 追加一个时间点。
- `updateSettings(_:)`：更新 `HealthSettings`。
- 写盘 `Data.write(options: .atomic)`，失败回滚内存状态并抛错。
- `defaultFileURL()` 指向 `Daka/health.json`。

## 5. 提醒与桌宠

### 5.1 提醒控制器

新增 `Sources/Daka/HealthReminderController.swift`：

- 独立 `Timer`，每 30 秒 tick 一次（复用注入时钟）。
- 每次 tick 计算 `HealthRules.status`；当 `waterDue` / `movementDue` 为真、且距上次同类提醒已达该工具间隔时，发**系统通知**并触发桌宠气泡。
- 记忆 `lastWaterNoticeAt` / `lastMovementNoticeAt`，避免每 tick 重复提醒。
- 完成后（记录）、离开时段、关闭工具时不再提醒。

### 5.2 通知

扩展 `GentleNotifier`：新增通用方法 `notify(id:title:body:)`（现有打卡通知改为内部复用该方法，行为不变）。

- 喝水：「该喝水啦 💧」/「已经 X 分钟没喝水了，起来接杯水吧。」
- 走动：「起来走两步 🚶」/「坐了 X 分钟，活动一下肩颈和腿。」

### 5.3 桌宠气泡与表情

- `AppModel` 新增 `@Published var petSpeech: String?`；触发提醒或完成记录时赋值，约 6 秒后自动清空（定时器）。
  - 到点：「该喝水啦～💧」/「坐太久啦，起来走两步 🚶」
  - 记录后：「咕嘟咕嘟 +1 杯！」/「走一走真舒服～」
- `PetView` 在桌宠头顶显示对话气泡（圆角气泡 + 指向小三角），`petSpeech == nil` 时不显示。
- `PetMood` 新增两个状态：`.thirsty`（🥵）、`.restless`（😤）。
  - `resolve` 新增可选参数 `health: HealthStatus? = nil`，**默认 nil 时行为与现状完全一致**（现有 `PetMoodTests` 不变仍通过）。
  - 优先级：打卡 hard > 打卡 gentle > 健康（`waterDue` / `movementDue`）> 时间。
  - 两者同时到点时优先显示 `.thirsty`（喝水更紧急）。

## 6. 界面

### 6.1 控制中心工具详情

- `WaterToolView`：
  - 顶部指标卡：今日 `3/8 杯`、连续达标天数、平均每日杯数、距上次喝水时间。
  - 大按钮「+1 杯」（记录当前时间）。
  - 设置区：启用开关、每日目标杯数、提醒间隔（分钟）。
  - 图表：7/14/30 天每日杯数柱状图 + 目标虚线（复用 `Charts`，参考 `StatisticsView`）。
- `MovementToolView`：
  - 顶部指标卡：今日 `4/8 次`、连续达标天数、距上次起身时间、平均每日次数。
  - 大按钮「起来走走」。
  - 设置区：启用开关、每日目标次数、提醒间隔（分钟）。
  - 图表：每日起身次数柱状图 + 目标虚线。

### 6.2 摘要与快捷入口

- `ControlCenterView.summary(for:)`：`.water` 返回 `今日 3/8 杯`；`.sedentary` 返回 `已起身 4 次`。
- `ToolPanelView` 今日概览：喝水/久坐显示实时数据；每个工具加「+1 杯」「起来走走」快捷按钮。
- 侧栏与面板文案由「即将推出」改为实时值。

### 6.3 统计口径

新增 `Sources/DakaCore/HealthStatistics.swift`，参考 `Statistics`：

- 逐日聚合杯数/次数；`rangeDays` 由视图选择 7/14/30。
- 计算连续达标天数、区间平均、达标天数。

## 7. 组件与职责

| 组件 | 职责 |
|---|---|
| `HealthModels` | 设置、每日记录、顶层数据结构 |
| `HealthRules` | 纯函数状态判定（是否到点、进度、是否活跃） |
| `HealthStore` | `health.json` 读写、损坏恢复、记录/设置更新 |
| `HealthStatistics` | 区间聚合与统计口径 |
| `HealthReminderController` | 定时评估、发通知、驱动桌宠气泡 |
| `AppModel` | 持有 store、发布今日状态与 `petSpeech`、提供记录/设置方法 |
| `WaterToolView` / `MovementToolView` | 控制中心工具详情 |
| `PetView` | 头顶气泡 + 健康表情 |
| `GentleNotifier` | 通用通知方法 |

## 8. 测试

- `HealthRulesTests`（注入时钟）：窗口内到点、窗口外不提醒、间隔未到不提醒、工作日判断、休假不提醒、跨天归零、目标达成。
- `HealthStoreTests`：往返、损坏恢复、记录追加、设置更新、原子写回滚。
- `HealthStatisticsTests`：逐日聚合、连续达标、平均、范围选择。
- `PetMoodTests`：新增健康状态覆盖时间、默认 nil 不回归、优先级（hard > gentle > health > time）。
- UI（气泡、通知、按钮、图表）走 `docs/verification.md` 手动清单。

## 9. 兼容与不变项

- 打卡全部行为、`data.json`、设置读写路径、统计口径**不变**。
- `PetMood.resolve` 新增参数带默认值，现有调用与测试不变。
- 护眼工具继续占位。

## 10. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`docs/verification.md` 与 `README.md` 功能清单。
