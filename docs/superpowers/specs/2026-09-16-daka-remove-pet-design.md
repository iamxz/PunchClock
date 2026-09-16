# Daka：移除桌宠模块，统一全屏强提示设计

日期：2026-09-16
状态：已确认（待实现）

## 1. 目标

1. **彻底移除桌宠模块**：删除桌宠浮窗、气泡、心情解析与相关 UI 入口，清理所有引用。
2. **所有提醒统一为全屏强提示**：喝水 / 走动提醒与打卡提醒一样，使用置顶、跨 Space、拦截退出快捷键的全屏遮罩；打卡与健康提醒同时到期时，在同一全屏内同时展示（用户已确认）。

## 2. 现状

- **打卡提醒**：`Scheduler` → `ReminderController` → `OverlayWindow`（置顶、全屏、拦截 ESC/Cmd+W/Q/M/H，ESC 暂停后按 `settings.reminderIntervalSeconds` 重新弹出），内容由 `OverlayView` 渲染打卡按钮。
- **喝水 / 走动提醒**：`HealthReminderController` 每 30 秒 tick，通过 `GentleNotifier` 发本地通知 + `onSpeak` 驱动桌宠气泡。
- **桌宠模块**：
  - `Sources/Daka/PetView.swift`、`PetSpeechBubble.swift`、`PetWindowController.swift`、`ToolPanelView.swift`
  - `Sources/DakaCore/PetMood.swift`
  - `Tests/DakaCoreTests/PetMoodTests.swift`
  - 引用点：`AppDelegate`（创建/显示）、`AppModel`（`petVisible`/`petSpeech`/`petWindow`/`say()`/`setPetVisible()` 与 `onSpeak` 接线）、`ControlCenterView`（工具栏 `PetToolbarToggle`）。

## 3. 移除桌宠

删除文件：

```
Sources/Daka/PetView.swift
Sources/Daka/PetSpeechBubble.swift
Sources/Daka/PetWindowController.swift
Sources/Daka/ToolPanelView.swift        // 仅桌宠弹出面板在用
Sources/DakaCore/PetMood.swift
Tests/DakaCoreTests/PetMoodTests.swift
```

清理引用：

- `Sources/Daka/AppDelegate.swift`：删除 `petWindow` 属性、`PetWindowController` 创建与 `pet.show()`。
- `Sources/Daka/AppModel.swift`：删除 `petSpeech`、`petVisible`、`petWindow`、`speechClearTimer`、`say()`、`setPetVisible()`；`drinkWater()` / `standUp()` 保留记录逻辑与 `healthReminder.tick()`，去掉 `say()` 反馈；`healthReminder.onSpeak` 接线改为 `onHealthAlerts`（见 §4）。
- `Sources/Daka/ControlCenterView.swift`：删除 `PetToolbarToggle` 及 `.toolbar` 中该项。
- `Sources/Daka/PunchButton.swift`：删除无引用后剩余的（若有）ToolPanelView 相关说明；实际 `ToolPanelView` 删除后，`MenuBarView` 仍是 `PunchButton` 的调用点。

`ps.visible` / `pet.frame` 等 UserDefaults 键遗留无害，不做迁移。

## 4. 健康提醒全屏化

### 4.1 数据模型（`Sources/Daka/OverlayView.swift` 旁新增）

```swift
struct HealthAlert: Identifiable, Equatable {
    enum Kind { case water, movement }
    let kind: Kind
    let title: String
    let body: String
    let repeatIntervalSeconds: TimeInterval
    var id: Int { kind == .water ? 0 : 1 }
}
```

### 4.2 `HealthReminderController`（改）

- 删除 `GentleNotifier`（`notifier` 属性、`notify` 调用、`requestAuthorizationIfNeeded`）与 `onSpeak`，新增回调：

  ```swift
  var onHealthAlerts: (([HealthAlert]) -> Void)?
  ```

- 每个 tick 计算当前到期的提醒，组装成 `HealthAlert` 数组回调（可为空数组）：
  - 喝水到期：title「该喝水啦 💧」，body「已经 X 分钟没喝水了，起来接杯水吧。」（X 取 `status.minutesSinceDrink ?? effectiveWaterIntervalMinutes`），`repeatIntervalSeconds = effectiveWaterIntervalMinutes * 60`
  - 走动到期：title「起来走两步 🚶」，body「坐了 X 分钟，活动一下肩颈和腿吧。」，`repeatIntervalSeconds = effectiveMovementIntervalMinutes * 60`
- 保留现有节流：`waterDue` / `movementDue` 且距上次通知已过一个间隔才再次回调；未到期时把 `lastWaterNoticeAt` / `lastMovementNoticeAt` 置 nil 并回调空数组。

### 4.3 `OverlayModel` / `OverlayView`（改）

- `OverlayModel` 增加：

  ```swift
  @Published var healthAlerts: [HealthAlert] = []
  var onWater: () -> Void = {}
  var onMovement: () -> Void = {}
  ```

  `AppModel` 接线：`onWater = { model.drinkWater() }`、`onMovement = { model.standUp() }`。

- `OverlayView`：打卡按钮区（现有）之下增加「健康提醒」区，逐条渲染 `HealthAlert`：

  - 图标：water `drop.fill`（蓝）、movement `figure.walk`（绿）
  - title + body 居中
  - 大号操作按钮：喝水「已喝水」、走动「已起身」，点击执行 `onWater` / `onMovement`
  - 提示文案：`ESC 暂停，过一个提醒间隔后重新弹出`

- `promptTitle` 逻辑扩展：
  - `tasks == [] && healthAlerts.isEmpty` → 打卡完成（保留）
  - `tasks == [] && !healthAlerts.isEmpty` → 「健康提醒」
  - 其余按现有打卡逻辑

### 4.4 `ReminderController`（改）

- 新增状态 `private var currentHealthAlerts: [HealthAlert] = []`。
- 新增方法：

  ```swift
  func updateHealth(_ alerts: [HealthAlert], settings: DakaCore.Settings, now: Date)
  ```

  - 更新 `overlayModel.healthAlerts`、`overlayModel.settings`、`overlayModel.now`
  - 调 `syncOverlay()` 统一维护显示与定时器

- **可见性规则**：全屏可见 ⇔ `!currentTasks.isEmpty || !currentHealthAlerts.isEmpty`。
  - 现有 `showHard` / `refresh` / `hide` 语义不变，`hide()` 只在无打卡时触发；若 `currentHealthAlerts` 非空，`hide()` 后可见性由 `syncOverlay` 重新判定（健康提醒仍在，不关窗）。
  - 由 `showHard` / `refresh` / `updateHealth` / `hide` 统一进入 `syncOverlay()`：重建/显示窗口、管理「顶置重复置前」定时器、`NSApp.activate`。

- **ESC 暂停**（`snooze()`）：
  - 暂停时长：`currentTasks` 非空 → `reassertInterval`；否则取 `currentHealthAlerts.repeatIntervalSeconds` 的最小值。
  - 暂停期间置 `isSnoozed`：`updateHealth` / `refresh` 只更新数据不置前窗口；`showHard`（打卡状态变化）沿用现状——取消暂停并重新弹出。
  - `resume()` 恢复 `isSnoozed = false` 并重新 `syncOverlay()`。

- `showMessage`（打卡反馈）沿用，不随 `syncOverlay` 重构而改变。

## 5. 错误处理与边界

- 全屏期间喝茶/起身记录失败：沿用 `AppModel.errorMessage`，遮罩保持，下次节流重新出现。
- 无任何提醒时不显示遮罩、不启动重复置前定时器。
- 喝水后喝水到期立即消失（`updateHealth([])`），若打卡待办仍在则遮罩退化为仅打卡内容（工厂：不闪断）。
- `updateHealth` 在暂停期内到来：缓存数据，不提前弹出。

## 6. 范围说明

- 不改 `DakaCore`（除删除 `PetMood.swift` 外）：`Scheduler`、`ReminderPresenting`、`HealthRules`、`PunchStore` 等不动；`HealthReminderController` 逻辑改动均在应用层 `Daka`。
- 不引入通知权限（`GentleNotifier` 删除后无通知调用）。
- 菜单栏面板、主窗口、统计 UI 均不变。
- `ReminderState` 保留（`Scheduler` / `DakaApp` 菜单栏图标态用到）。

## 7. 测试

- 删除 `Tests/DakaCoreTests/PetMoodTests.swift`。
- 其余 `make test` 应全绿（本次不改 `DakaCore` 逻辑）。
- 更新 `docs/verification.md` 手动验证清单：
  - 桌宠不出现，无掌印入口、无工具面板。
  - 喝水/走动到期弹全屏（含按钮文案），点「已喝水/已起身」记录并关闭。
  - ESC 暂停：打卡按打卡间隔、仅健康按健康间隔重新弹出。
  - 打卡与健康同时到期：同一全屏同时展示，可一次处理完。
  - 打卡完成后遮罩不闪断、健康提示继续。

## 8. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`docs/verification.md`、README。