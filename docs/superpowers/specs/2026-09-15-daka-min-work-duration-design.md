# Daka v5：最少工时（不满 8 小时，下班打卡不算完成）设计

日期：2026-09-15
状态：已确认（待实现）
在 v4（重复打卡）基础上增加「最少工时」判定；v2 窗口/两级提醒、v3 主窗口与统计、v4 重复打卡的其余部分不变。

## 1. 定位

Daka 是**考勤提示器**：目的是提醒你别忘了在正确的时间打卡（对应现实世界的考勤）。因此下班必须是一段真实的工作时长，提前点的下班卡不算数。

## 2. 规则

- **最少工时**：`settings.minWorkDurationHours`，默认 **8 小时**，可在设置里改。
- **有效下班打卡**：当天存在某个下班打卡 `p`，使得 `p − 当天最早上班打卡 ≥ 最少工时`。取其中**最晚**的一个作为「下班时间」。
- 当天**没有上班打卡** → 无法计算时长 → 下班**不算完成**（继续提醒）。
- **所有下班打卡仍全部保留**（含不满工时的），只是不满工时的不算完成。
- 不满工时时：下班仍未完成 → 过了下班窗口截止后**继续全屏催**，直到打出满足工时的下班卡（可重复打卡）。

## 3. 数据模型

- `DayRecord` 不变（`morningPunches`/`eveningPunches` 列表）。
- `Settings` 新增 `minWorkDurationHours: Double = 8`（`decodeIfPresent` 默认 8；旧数据平滑升级）。
- 新增纯函数（`DakaCore`）：

```swift
public enum PunchRules {
    /// 满足最少工时的最晚下班打卡；无上班卡或无合格下班卡时为 nil。
    public static func effectiveEveningPunch(_ record: DayRecord,
                                             minWorkDuration: TimeInterval) -> Date? {
        guard let morning = record.morningDoneAt else { return nil }
        return record.eveningPunches
            .filter { $0.timeIntervalSince(morning) >= minWorkDuration }
            .max()
    }

    public static func isEveningComplete(_ record: DayRecord,
                                         minWorkDuration: TimeInterval) -> Bool {
        effectiveEveningPunch(record, minWorkDuration: minWorkDuration) != nil
    }
}

extension Settings {
    public var minWorkDuration: TimeInterval { max(0, minWorkDurationHours) * 3600 }
}
```

## 4. 各层应用

- `ScheduleEvaluator.pendingReminders`：下班的「完成」改为 `PunchRules.isEveningComplete(record, minWorkDuration: settings.minWorkDuration)`；上班仍为 `record.morningDone`。
- `Statistics.compute`：
  - `completedBoth = record.morningDone && isEveningComplete(...)`。
  - 「下班时间」用 `effectiveEveningPunch`；`workDuration = effectiveEvening − 最早morning`。
  - 缺卡 / 连续 / 平均工时随之使用新的完成判定。
- `PunchTarget.resolve`：增加 `minWorkDuration`，下班是否完成用 `isEveningComplete`。
- 菜单栏：
  - 下班状态行显示**有效下班时间**（最晚合格）；未完成时按 hard/gentle/待打卡显示。
  - 打卡次数仍显示全部次数。
  - 圆形按钮目标判定用新的完成状态。
- 设置页：新增「每日最少工时」调节（默认 8 小时，例如 Stepper 1–12，步进 0.5）。
- `AppModel`：暴露 `minWorkDuration`、`effectiveEveningPunch`、`isEveningComplete`、`setMinWorkHours(_:)`。

## 5. 边界

- 上班卡在当天晚些时候才打（如 11:00）→ 8 小时后是 19:00，晚于下班窗口 18:30 → 18:30 起一直全屏催，直到 19:00 后打卡。
- 没打上班卡 → 下班永远不算完成（同时上班也在催）。
- 最少工时设为 0 时等价于「打卡即完成」。
- 只改判定与展示，不改打卡记录的保存（不满工时的卡仍记录）。

## 6. 测试

- `PunchRules`：
  - 无上班卡 → nil / 不完成。
  - 上班 9:00、下班 16:00（7h）→ 不合格；下班 17:00（8h）→ 合格；两个都在 → 取 17:00。
  - 上班 9:00、下班 17:00+18:00 → 取 18:00。
  - `minWorkDuration = 0` → 任一有下班卡即合格。
- `Settings`：旧 JSON 缺少 `minWorkDurationHours` → 默认 8；往返一致。
- `ScheduleEvaluator`：上班 9:00、下班 17:00（<8h）→ 下班仍待办（过截止为 hard）；下班 18:00（≥8h）→ 无下班提醒。
- `Statistics`：只有不合格下班卡 → `completedBoth == false`、不计时长、算缺卡；合格后计入。
- `PunchTarget`：下班有卡但不合格 → 目标仍为下班。

## 7. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`docs/verification.md`。
