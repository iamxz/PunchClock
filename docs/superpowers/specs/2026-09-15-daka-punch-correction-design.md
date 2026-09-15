# Daka v12：今日补卡 / 改时间 / 删除设计

日期：2026-09-15
状态：已确认（待实现）
在 v4（`2026-09-15-daka-repeat-punch-design.md`）「一天可多条打卡」基础上，为**今天**的打卡记录增加事后修正能力；v2 窗口/两级提醒、v3 统计口径、v4 多条语义均不变。

## 1. 目标

允许用户对**今天**的打卡记录做三种修正：

- **补卡**：漏打卡后，手动新增一条打卡（时间可选，默认当前时间）。
- **改时间**：某条打卡时间不对（例如实际 08:50 打卡却记成 09:05），直接改成正确时间。
- **删除**：误点产生的错误记录，整条删除。

范围**仅限今天**，不支持修改历史日期。上班 / 下班各自独立。

## 2. 数据模型（不变）

`DayRecord.morningPunches` / `eveningPunches` 仍为「打卡时间点列表」，不做结构改动。

- 上班时间取 `morningPunches.min()`（最早），下班取 `eveningPunches.max()`（最晚）。
- 新增/改时间/删除都是对既有列表的增删改，天然兼容「一天多条」。
- 不新增任何持久化字段，旧数据文件完全兼容。

## 3. 持久化（`PunchStore`）

新增两个方法（`mark` 保持不变，用于追加）：

```swift
public func updatePunch(_ task: PunchTask,
                        at index: Int,
                        to date: Date,
                        on day: Date,
                        calendar: Calendar = .current) throws

public func removePunch(_ task: PunchTask,
                        at index: Int,
                        on day: Date,
                        calendar: Calendar = .current) throws
```

- 以 `DakaDate.key(for: day, calendar:)` 定位当天记录；与现有 `mark` 相同，写盘失败时回滚内存。
- `index` 越界时**安全 no-op**（不崩溃、不写盘、不抛错），因为 UI 传入的 index 与渲染时一致，越界只应出现在异常竞态下。
- 到达 `updatePunch`/`removePunch` 时若当天记录不存在，按空记录处理（同样 no-op）。
- 新增（补卡）复用现有 `mark(_:at:)`，不再另加 API。

## 4. 应用层（`AppModel`）

新增三个包装方法，语义与 `punch` 一致（成功后 `refreshRecord()` + `scheduler?.tick()`；失败写 `errorMessage`）：

```swift
func addPunch(_ task: PunchTask, at time: Date)
func updatePunch(_ task: PunchTask, index: Int, to time: Date)
func removePunch(_ task: PunchTask, index: Int)
```

- `addPunch` 调 `store.mark(task, at: time)`。
- `updatePunch` / `removePunch` 调 store 对应方法并传 `on: clock.now`（即今天）。

## 5. UI（控制中心 → 打卡统计页）

在 `PunchToolView` 现有统计图**上方**新增「今日打卡」区：

- 上班 / 下班两组，各列出今天每一条打卡的时间（`HH:mm`）。
- 每组标题右侧有「补卡」按钮。
- 每条记录后有「改时间」「删除」两个操作。
- 该组无记录时显示「今天还没有打卡」。

交互：

- 点「补卡」或「改时间」弹出 sheet（`PunchTimeEditor`）：
  - `DatePicker(displayedComponents: .hourAndMinute)`，默认值为当前时间（补卡）或该条原时间（修改）。
  - 「取消」关闭；「保存」调用对应 `AppModel` 方法后关闭。
- 点「删除」先弹确认对话框，确认后删除。

类型：

```swift
struct PunchEditorTarget: Identifiable {
    let task: PunchTask
    let index: Int?      // nil = 补卡（新增）
    let initial: Date
    var id: String       // 便于 sheet(item:)
}
```

## 6. 联动与边界

- 改/删后统计（本月打卡、连续打卡、平均上班、缺卡）自动刷新，因为 `Statistics.compute` 读取的是同一份 `store.data`。
- 删除当天唯一一条上班卡后 `morningDone` 变回 `false`，调度器会重新评估提醒（可能再次出现温和/强制提醒）——这是「记录被修正」的预期行为，不做特殊抑制。
- sheet 只编辑时:分，秒沿用初始值；不做跨天编辑（仅今天）。
- 下班有效时间的判定（`PunchRules.effectiveEveningPunch`，最少工时过滤）不受影响。

## 7. 测试

`PunchStoreTests`（纯逻辑，注入时间）：

- `updatePunch` 原地替换指定下标的时间，列表条数不变。
- `removePunch` 删除指定下标，列表条数减一。
- 删除当天唯一的上班卡后 `morningDone == false`、`morningDoneAt == nil`。
- 越界 index：`updatePunch` / `removePunch` 不抛错、不改变数据、不落盘。
- 改/删后重新加载，持久化结果一致。
- 追加/删除混合后，上班取最早、下班取最晚的规则仍成立。

UI（sheet、确认对话框）走手动验证，更新 `docs/verification.md`。

## 8. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`docs/verification.md`。
