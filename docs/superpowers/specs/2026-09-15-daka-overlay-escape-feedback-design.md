# Daka v14：全屏遮罩 ESC 暂停 + 打卡反馈设计

日期：2026-09-15
状态：已确认（待实现）
在 v13（`2026-09-15-daka-hard-only-reminder-design.md`）「窗口开始即全屏强提醒」基础上，给全屏遮罩加一个**临时脱困**出口并解释打卡行为。v11/v12 补卡、v13 强提醒规则不变。

## 1. 背景（问题）

v13 让全屏遮罩从窗口开始时间就弹出并持续置顶。实际使用中暴露两个问题：

- **无法脱困**：遮罩刻意拦截 ESC / Cmd+Q 等，且没有出口，一旦弹出只能完成打卡才能离开。
- **打卡「像没反应」**：由于「每日最少工时」规则（默认 8 小时），当天上班卡较晚（或没有上班卡）时，点下班打卡会写入记录但**不会让遮罩消失**，用户以为按钮无效。

典型证据：某天上班卡 10:36，18:00 下班窗口开始后大量点击下班仍不消失——因为下班需在上班满 8 小时（18:36）后才算完成。

## 2. 目标

- 按 **ESC 暂停提醒**：立即隐藏全屏遮罩，过设定间隔后自动重新弹出，循环直到完成。
- 打卡后如任务仍未完成，遮罩上**明确反馈原因**与还差多久。

## 3. ESC 暂停（snooze）

- 全屏遮罩窗口把 ESC 事件回调给 `ReminderController`（`keyDown` 的 keyCode 53 与 `cancelOperation` 两个入口都要处理）。
- `ReminderController.snooze()`：
  1. 停止「置顶重弹」计时器；
  2. 将所有遮罩窗口 `orderOut`；
  3. 启动一次性 `snoozeTimer`，时长 = `settings.effectiveReminderIntervalSeconds`（设置页「重复提醒」间隔，默认 2 分钟）。
- 到点执行 `resume()`：重新置顶所有遮罩窗口、`NSApp.activate`、重启「置顶重弹」计时器。
- 取消规则：
  - `hide()`（任务完成 / 休假 / 跨天）同时取消 `snoozeTimer`；
  - `showHard(...)`（状态变化，例如打完上班剩值班）先取消 `snoozeTimer` 再立即展示。
- 暂停期间若用户通过菜单栏/控制中心完成打卡，状态变化会让调度器 `hide()`，遮罩不再自动弹回。

## 4. 打卡反馈

- 点击遮罩上的打卡按钮后，`AppModel.punch(_:)` 在成功写入并 `scheduler.tick()` 之后判断：该任务是否仍未完成。
  - 上班：`record.morningDone == false`。
  - 下班：`isEveningComplete == false`。
- 若仍未完成，计算并推送反馈文案给遮罩；已完成则不显示。
- 文案规则（以最少工时 `H = settings.minWorkDurationHours`）：
  - 有上班卡、下班未满工时：`已记录 HH:mm；距上班满 H 小时还差 X，满后自动完成。`
  - 没有上班卡就点下班：`今天还没有上班打卡，需先打上班卡；下班需满 H 小时才算完成。`
  - `X` 由 `morningDoneAt + minWorkDuration - 本次打卡时间` 取整到分钟；小于 1 分钟显示「不足 1 分钟」。
- 展示：`OverlayModel` 增加 `message: String?`，`OverlayView` 在标题下方显示；每次打卡覆盖，「任务完成」或 `hide()` 时清空。

## 5. 核心/应用层改动

- `Sources/Daka/ReminderController.swift`
  - `OverlayWindow` 增加 `var onEscape: (() -> Void)?`；ESC 触发。
  - 新增 `snooze()` / `resume()` / `snoozeTimer`；`showHard`/`hide` 取消待弹；`showHard` 创建窗口时把 `onEscape` 指向 `snooze()`。
  - 新增 `showMessage(_:)`（或等价）设置 `overlayModel.message`。
- `Sources/Daka/OverlayView.swift`
  - `OverlayModel` 增加 `@Published var message: String?`。
  - 视图在任务按钮上方/下方显示 `message`。
- `Sources/Daka/AppModel.swift`
  - `punch(_:)` 写入并 tick 后，若任务仍未完成，计算反馈文案并调用 `reminder?.showMessage(...)`；完成时清空。
- 反馈文案计算抽成 `DakaCore` 的纯函数以便单测：
  ```swift
  public enum PunchFeedback {
      public static func text(task: PunchTask,
                              record: DayRecord,
                              settings: Settings,
                              punchedAt: Date,
                              calendar: Calendar = .current) -> String?
  }
  ```
  返回 `nil` 表示已完成、无需提示。

## 6. 边界

- 暂停间隔复用「重复提醒」设置（1–60 分钟，默认 2）；改设置后，暂停中的下次自动弹出使用新间隔。
- ESC 只暂停，不改变任何记录、不退出应用；应用继续后台常驻。
- 跨天（午夜）后状态清空，遮罩与待弹都不再出现。
- 菜单栏圆形按钮（非遮罩）打卡同样会触发反馈计算，但仅当遮罩可见时用户能看到。

## 7. 测试

- `PunchFeedback.text`（纯函数，`DakaCore`）：
  - 下班未满工时 → 返回含「还差」的文案。
  - 无上班卡点下班 → 返回提示先打上班卡。
  - 完成任务 → 返回 `nil`。
- 手动验证（`docs/verification.md` 新增）：
  - 全屏遮罩按 ESC → 立即消失，约 2 分钟后自动重新弹出，可重复。
  - 点下班打卡但未满 8 小时 → 遮罩不消失，但显示「已记录…还差…」；到点后再点即消失。
  - 没有上班卡时点下班 → 显示需先打上班卡。
  - 完成后不再弹回；跨天自动结束。

## 8. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`README.md`（说明 ESC 暂停）、`docs/verification.md`。
