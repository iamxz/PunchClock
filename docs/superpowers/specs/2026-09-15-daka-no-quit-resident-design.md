# Daka v8：禁止随便退出 / 后台常驻 设计

日期：2026-09-15
状态：已确认（待实现）
在 v7（桌宠平台）基础上，让应用无法「随便退出」；v2 窗口/两级提醒、v3 主窗口与统计、v4 重复打卡、v5 最少工时、v6 休假、v7 桌宠的其余部分不变。

## 1. 定位

Daka 是**考勤提示器**：一旦进程退出，就不会再有任何提醒——当天未打的卡彻底被漏掉。因此应用必须**后台常驻**，不允许用户随手退出。

## 2. 需求

- **任何时候都阻止退出**：不再区分温和/强制阶段，任何一天、任何状态下都不能正常退出。
- **保持现有形态**：继续保留 Dock 图标与菜单栏（不改 `activationPolicy`、不改 `LSUIElement`）。
- **保留一个确认式退出入口**：放在设置页，供更新 / 卸载 / 故障排查使用，需二次确认。
- **系统注销/关机/重启放行**：不得阻碍系统关机，否则会卡住注销/关机。
- 强制退出（Cmd+Opt+Esc / `kill -9`）普通应用无法屏蔽，维持现状说明。

## 3. 机制：单一终止闸门

macOS 上所有退出路径（Cmd+Q、`NSApp.terminate`、菜单项、系统注销）最终都经过 `NSApplicationDelegate.applicationShouldTerminate`。用它作为唯一闸门：

- `AppModel` 新增 `allowTermination: Bool = false`（普通可写属性，不走持久化）。
- `AppDelegate.applicationShouldTerminate`：

```swift
func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    MainActor.assumeIsolated { AppModel.shared.allowTermination } ? .terminateNow : .terminateCancel
}
```

- `AppDelegate` 在 `applicationDidFinishLaunching` 注册系统关机通知：

```swift
NSWorkspace.shared.notificationCenter.addObserver(
    self,
    selector: #selector(systemWillPowerOff),
    name: NSWorkspace.willPowerOffNotification,
    object: nil
)
```

  收到后 `AppModel.shared.allowTermination = true`，使注销/关机/重启能正常结束进程。
- 单实例逻辑（`applicationWillFinishLaunching` 中 `exit(0)`）不经过该闸门，重复启动时仍会激活已有实例并结束新进程，行为不变。
- `applicationShouldTerminateAfterLastWindowClosed` 维持返回 `false`（关窗不退出）。

## 4. 各层应用

- **移除日常退出入口**：
  - `MenuBarView.swift` 菜单栏面板删除「退出」按钮。
  - `PetView.swift` 桌宠右键菜单删除「退出 Daka」。
  - `ToolPanelView.swift` 浮动工具面板删除「退出」按钮。
- `AppModel.quit()` 改名/收敛为确认退出：`confirmQuit()`，弹出 `NSAlert`（标题「退出 Daka？」，说明「退出后将无法提醒打卡，直到下次开机或手动启动。」，按钮「仍要退出」/「取消」）；确认后 `allowTermination = true` 再 `NSApp.terminate(nil)`。取消则不改状态。
- **设置页** `SettingsView` 新增「应用」Section，含「退出应用」按钮，点击调用 `model.confirmQuit()`。
- 随退出按钮一并清理只在禁用退出时用到的 `.disabled(model.hasHardTasks)`；确认无其他引用后删除 `AppModel.hasHardTasks`，避免死代码。`ReminderState.hard` 本身仍用于遮罩与图标判定，保留。

## 5. 边界

- Cmd+Q 仍可能触发系统默认 Quit，但会走到闸门被取消，等同于无效。
- 若用户从不主动退出，应用将跨天常驻；跨天重置、定点拉起等既有逻辑不变。
- 系统关机通知若晚于终止询问（极端时序），`applicationShouldTerminate` 可能先返回取消；此时以「系统仍会完成关机」为准，不额外处理（macOS 关机流程对 cancel 的 app 有兜底）。
- 「注销/关机」通知在流程**开始**时发出，用户可能中途取消。放行标志在通知后 60 秒自动复位：真实关机在数秒内就会询问并结束进程（复位无影响），被取消的注销则恢复「禁止退出」，存在不超过 60 秒的短暂可退出窗口。
- 关机通知用 `queue: .main` 的 block 观察者（而非 selector），保证主线程投递，避免 `MainActor.assumeIsolated` 跨线程崩溃。
- 数据与打卡逻辑（DakaCore）不涉及本次改动，无新增持久化字段。

## 6. 验证

手动验证（补充进 `docs/verification.md`）：

- 菜单栏面板 / 桌宠右键 / 工具面板中均**没有**退出入口。
- Cmd+Q 无效，应用不退出。
- 设置页「退出应用」弹出确认框：点「取消」不退出；点「仍要退出」应用退出。
- 系统注销 / 关机 / 重启时应用能正常结束、不卡关机。
- Cmd+Opt+Esc 强制退出仍可结束应用（已知限制，不屏蔽）。

自动化：无 DakaCore 逻辑改动，现有 `make test` 应保持通过。

## 7. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 `README.md`（使用说明中「温和阶段可正常退出」改为「任何阶段都不能退出，仅设置页可确认退出」；已知限制保留强制退出说明）。
- 本 spec、对应 plan、`docs/verification.md`。
