# Daka v4：重复打卡（同一项一天可打多次）设计

日期：2026-09-15
状态：已确认（待实现）
在 v3 基础上调整数据模型与菜单栏按钮语义；v2 的窗口/两级提醒规则、v3 的主窗口与统计不变。

## 1. 目标

允许同一天对同一项（上班/下班）**打卡多次**，并保留全部时间点。典型场景：17:00 打了下班卡但人还没走，18:00 再打一次，下班时间以最后一次为准。

## 2. 数据模型（`DayRecord`）

改为以「打卡时间列表」为数据源：

```swift
public struct DayRecord: Codable, Equatable, Sendable {
    public var morningPunches: [Date]     // 上班打卡时间点（全部保留）
    public var eveningPunches: [Date]     // 下班打卡时间点（全部保留）
    public var skipped: Bool

    public var morningDone: Bool { !morningPunches.isEmpty }
    public var eveningDone: Bool { !eveningPunches.isEmpty }
    public var morningDoneAt: Date? { morningPunches.min() }   // 上班取最早
    public var eveningDoneAt: Date? { eveningPunches.max() }   // 下班取最晚

    public func isDone(_ task: PunchTask) -> Bool
}
```

- `morningDone`/`eveningDone`/`morningDoneAt`/`eveningDoneAt` 变为只读计算属性（保持既有调用方不变）。
- **向后兼容解码**：`init(from:)` 先尝试 `morningPunches`/`eveningPunches`；缺失时回退旧字段——`morningDone == true` → `[morningDoneAt ?? Date()]`，`eveningDone` 同理。`encode` 只写新字段。

## 3. 持久化（`PunchStore`）

`mark(_:at:)` 改为**追加**：

```swift
case .morning: rec.morningPunches.append(date)
case .evening: rec.eveningPunches.append(date)
```

不再去重、不覆盖；失败仍回滚（沿用现有逻辑）。

## 4. 提醒逻辑（不变）

`morningDone`/`eveningDone` 语义仍是「是否至少打过一次」，因此：

- 打一次后即视为完成，不再提醒该任务。
- 重复打卡不会重新触发或改变提醒等级。
- 统计用 `morningDoneAt`（最早）/`eveningDoneAt`（最晚）计算上班时长，无需改动。

## 5. 菜单栏按钮（v3 的单个圆形按钮）

- 按钮**始终可点**（不再有「已完成」禁用态），支持重复打卡。
- 目标项判定：

```swift
if !record.morningDone { .morning }
else if !record.eveningDone { .evening }
else { now 的小时 < 12 ? .morning : .evening }   // 都打完后按时间补打
```

- 长按 3 秒进度逻辑不变。
- 状态行显示：上班时间取最早、下班时间取最晚；可加打卡次数提示（如「已打 2 次」）。

## 6. 主窗口

- 统计口径不变（上班最早 / 下班最晚）。
- 设置页「今天」区域可显示两项的打卡次数（可选）。

## 7. 测试

- `DayRecord`：
  - 新格式编解码往返；旧格式（`morningDone`+`morningDoneAt`）解码为 `[morningDoneAt]`。
  - `morningDoneAt` 取最早、`eveningDoneAt` 取最晚。
- `PunchStore`：
  - 同一项打卡两次后 `morningPunches.count == 2`、`morningDoneAt` 为第一次时间（上班）、`eveningDoneAt` 为最后一次（下班）。
  - 往返持久化后列表保留。
- `ScheduleEvaluator`：打一次即完成，重复打卡不改变提醒结果。
- 菜单栏目标项判定（抽成可测纯函数，如 `PunchTarget.resolve(record:now:calendar:)`）：上班未打→上班；上班已打下班未打→下班；都打完且 12 点前→上班、12 点后→下班。

## 8. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`docs/verification.md`。
