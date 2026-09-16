# 移除桌宠 + 健康提醒全屏强提示 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 彻底移除桌宠模块（`PetView` / `PetSpeechBubble` / `PetWindowController` / `ToolPanelView` / `PetMood`），并让喝水/走动提醒与打卡一致——以统一的置顶全屏强提示（同一遮罩、可同时展示）呈现。

**Architecture:** 应用层 `Daka` 内改动，`DakaCore` 只删 `PetMood.swift` 不动逻辑。新增 `HealthAlert` 模型描述健康提醒；`OverlayModel` / `OverlayView` 增加健康提醒区与「已喝水」「已起身」按钮；`ReminderController` 把打卡与健康提醒合并到同一全屏遮罩（新增 `updateHealth`、统一 `syncOverlay`、按内容决定 ESC 暂停时长）；`HealthReminderController` 删除本地通知与 `onSpeak`，改为按到期集合变化回调 `onHealthAlerts`。

**Tech Stack:** Swift 5.10 / SwiftPM、AppKit + SwiftUI、XCTest。

**Spec:** `docs/superpowers/specs/2026-09-16-daka-remove-pet-design.md`

**验证命令：** `swift build`、`swift test`、`make build`。

---

## 背景速览（给零上下文工程师）

- 这是一个 SwiftPM macOS 应用：`DakaCore`（纯逻辑、可单测）+ `Daka`（AppKit/SwiftUI 可执行目标）。
- 打卡强提醒链路：`Scheduler.tick()` → `AppModel` 里创建的 `ReminderController`（遵循 `DakaCore.ReminderPresenting`）→ 每屏一个 `OverlayWindow`（`.screenSaver` 级别、拦截 Cmd+W/Q/M/H 与 ESC）→ 根视图 `OverlayView` 渲染 `OverlayModel`。
- 健康提醒链路（现状）：`HealthReminderController` 每 30 秒 tick，用 `GentleNotifier` 发本地通知 + `onSpeak` 回调驱动桌宠气泡。
- 桌宠被 `AppDelegate`（创建/显示浮窗）、`AppModel`（`say` / `setPetVisible` / `petVisible` / `petSpeech` / `petWindow`）、`ControlCenterView`（工具栏掌印开关）、`HealthReminderController`（`onSpeak`）引用。
- `PunchButton` 目前被 `MenuBarView` 与 `ToolPanelView` 引用；本条只删 `ToolPanelView`，`MenuBarView` 继续用 `PunchButton`。

---

### Task 1: 移除桌宠模块与全部引用

**Files:**
- Delete: `Sources/Daka/PetView.swift`
- Delete: `Sources/Daka/PetSpeechBubble.swift`
- Delete: `Sources/Daka/PetWindowController.swift`
- Delete: `Sources/Daka/ToolPanelView.swift`
- Delete: `Sources/DakaCore/PetMood.swift`
- Delete: `Tests/DakaCoreTests/PetMoodTests.swift`
- Modify: `Sources/Daka/AppDelegate.swift`
- Modify: `Sources/Daka/AppModel.swift`
- Modify: `Sources/Daka/ControlCenterView.swift`

- [ ] **Step 1: 删除桌宠相关源文件**

```bash
rm Sources/Daka/PetView.swift \
   Sources/Daka/PetSpeechBubble.swift \
   Sources/Daka/PetWindowController.swift \
   Sources/Daka/ToolPanelView.swift \
   Sources/DakaCore/PetMood.swift \
   Tests/DakaCoreTests/PetMoodTests.swift
```

- [ ] **Step 2: 精简 `AppDelegate.swift`**

删除 `private var petWindow: PetWindowController?`，删掉 `applicationDidFinishLaunching` 中的 pet 创建块与末尾 `if model.petVisible { pet.show() }`。完整目标文件：

```swift
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: MainWindowController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: [])
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // 系统关机/注销开始时置放行；若用户取消注销，60 秒后重新封锁退出。
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willPowerOffNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                AppModel.shared.allowTermination = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                MainActor.assumeIsolated { AppModel.shared.allowTermination = false }
            }
        }

        let model = AppModel.shared
        let controller = MainWindowController(model: model)
        self.mainWindow = controller
        model.mainWindow = controller

        model.start()

        let isBackground = CommandLine.arguments.contains("--background")
        let launchKey = "NSApplicationLaunchIsDefaultLaunchKey"
        let isUserLaunch = (notification.userInfo?[launchKey] as? Bool) ?? true
        if !isBackground && isUserLaunch {
            controller.show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow?.show() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { AppModel.shared.allowTermination } ? .terminateNow : .terminateCancel
    }
}
```

- [ ] **Step 3: 清理 `AppModel.swift` 中桌宠相关代码**

逐项删除：

1. 删属性 `@Published var petSpeech: String?`
2. 删属性 `@Published var petVisible: Bool` 与 `weak var petWindow: PetWindowController?`
3. 删属性 `private var speechClearTimer: Timer?`
4. 删 `init` 末行 `self.petVisible = UserDefaults.standard.object(forKey: "pet.visible") as? Bool ?? true`
5. 删 `start()` 中 `healthReminder.onSpeak = { [weak self] text in self?.say(text) }` 这一行
6. 删整个 `say(_:)` 方法（含内部 speech 清除 Timer）
7. 删整个 `setPetVisible(_:)` 方法
8. `drinkWater()` 与 `standUp()` 去掉 `say(...)` 调用：

```swift
    func drinkWater() {
        do { try logHealth(.water) } catch {}
    }

    func standUp() {
        do { try logHealth(.movement) } catch {}
    }
```

（其余打卡/统计/设置方法不动。）

- [ ] **Step 4: 移除 `ControlCenterView.swift` 的工具栏开关**

删除 `body` 里的 `.toolbar { ... }` 修饰符块，并删除文件末尾的 `private struct PetToolbarToggle: View { ... }` 整个结构体。`body` 最终为：

```swift
    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(model.tools) { tool in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(tool.title, systemImage: tool.symbol)
                        Text(summary(for: tool.id))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(SidebarSelection.tool(tool.id))
                }

                Section("设置") {
                    ForEach(SettingsPage.allCases) { page in
                        Label(page.title, systemImage: page.symbol)
                            .tag(SidebarSelection.settings(page))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            detail(for: model.selectedSidebar)
                .padding(20)
        }
        .frame(minWidth: 720, minHeight: 520)
    }
```

- [ ] **Step 5: 构建与测试**

Run: `swift build`
Expected: `Build complete!`

Run: `swift test`
Expected: 全部 PASS（`PetMoodTests` 已删，其余不受影响）。

- [ ] **Step 6: 提交**

```bash
git add -A
git commit -m "feat: remove desktop pet module"
```

---

### Task 2: 全屏遮罩支持健康提醒（模型 + 渲染 + 控制器）

**Files:**
- Modify: `Sources/Daka/OverlayView.swift`
- Modify: `Sources/Daka/ReminderController.swift`
- Modify: `Sources/Daka/AppModel.swift`

阶段目标：遮罩结构与状态机支持健康提醒，但健康提醒数据源尚未接线（`updateHealth` 暂无人调用），**行为与现状一致**，保证编译通过。

- [ ] **Step 1: `OverlayView.swift` 增加 `HealthAlert` 与 `OverlayModel` 字段**

`import SwiftUI` 之后追加（顶层）：

```swift
/// 健康提醒内容（在全屏强提示里展示）。
struct HealthAlert: Identifiable, Equatable {
    enum Kind: Equatable { case water, movement }

    let kind: Kind
    let title: String
    let body: String
    let repeatIntervalSeconds: TimeInterval

    var id: Int { kind == .water ? 0 : 1 }
}
```

`OverlayModel` 增加字段：

```swift
    @Published var healthAlerts: [HealthAlert] = []
    var onWater: () -> Void = {}
    var onMovement: () -> Void = {}
```

- [ ] **Step 2: `OverlayView` 渲染健康提醒区**

在任务按钮 `ForEach(model.tasks, id: \.self) { ... }` 之后、`VStack` 闭合前插入：

```swift
                ForEach(model.healthAlerts) { alert in
                    VStack(spacing: 10) {
                        Label(alert.title,
                              systemImage: alert.kind == .water ? "drop.fill" : "figure.walk")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        Text(alert.body)
                            .font(.system(size: 20))
                            .foregroundStyle(.yellow)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 560)
                        Button {
                            if alert.kind == .water { model.onWater() } else { model.onMovement() }
                        } label: {
                            Text(alert.kind == .water ? "已喝水" : "已起身")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(width: 240, height: 56)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(alert.kind == .water ? .blue : .green)
                    }
                }
                Text("ESC 可暂停，过提醒间隔后重新弹出")
                    .font(.system(size: 14))
                    .foregroundStyle(.gray)
```

并把 `promptTitle` 改为：

```swift
    private var promptTitle: String {
        switch model.tasks {
        case [.morning]: return "该上班打卡了"
        case [.evening]: return "该下班打卡了"
        case []: return model.healthAlerts.isEmpty ? "打卡完成" : "健康提醒"
        default: return "还有打卡未完成"
        }
    }
```

- [ ] **Step 3: `ReminderController.swift` 支持健康提醒（整文件目标态）**

直接用下述内容替换整个文件：

```swift
import AppKit
import SwiftUI
import DakaCore

/// 全屏遮罩窗口：置顶、跨所有 Space、拦截 ESC/关闭快捷键。
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           ["q", "w", "m", "h"].contains(chars) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?(); return } // ESC：暂停提醒
        super.keyDown(with: event)
    }

    override func performClose(_ sender: Any?) {}
    override func performMiniaturize(_ sender: Any?) {}
}

@MainActor
final class ReminderController: @preconcurrency ReminderPresenting {
    private var reassertInterval: TimeInterval
    private let overlayModel = OverlayModel()
    private var windows: [OverlayWindow] = []
    private var builtFrames: [CGRect] = []
    private var reassertTimer: Timer?
    private var snoozeTimer: Timer?
    private var currentTasks: [PunchTask] = []
    private var currentHealthAlerts: [HealthAlert] = []
    private var isSnoozed = false

    init(interval: TimeInterval, onPunch: @escaping (PunchTask) -> Void) {
        self.reassertInterval = interval
        self.overlayModel.onPunch = onPunch
    }

    func setWaterAction(_ action: @escaping () -> Void) {
        overlayModel.onWater = action
    }

    func setMovementAction(_ action: @escaping () -> Void) {
        overlayModel.onMovement = action
    }

    func showHard(tasks: [PunchTask], settings: DakaCore.Settings, now: Date) {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        isSnoozed = false
        overlayModel.message = nil
        currentTasks = tasks
        overlayModel.tasks = tasks
        overlayModel.settings = settings
        overlayModel.now = now
        reassertInterval = settings.effectiveReminderIntervalSeconds
        syncOverlay()
    }

    func refresh(settings: DakaCore.Settings, now: Date) {
        overlayModel.settings = settings
        overlayModel.now = now
        let desired = settings.effectiveReminderIntervalSeconds
        if desired != reassertInterval {
            reassertInterval = desired
            if isSnoozed {
                scheduleSnooze()
            } else {
                stopReassertTimer()
                startReassertTimer()
            }
        }
        if !isSnoozed { rebuildWindowsIfNeeded() }
    }

    func updateHealth(_ alerts: [HealthAlert], settings: DakaCore.Settings, now: Date) {
        currentHealthAlerts = alerts
        overlayModel.healthAlerts = alerts
        overlayModel.settings = settings
        overlayModel.now = now
        syncOverlay()
    }

    func hide() {
        stopReassertTimer()
        currentTasks = []
        overlayModel.message = nil
        syncOverlay()
    }

    deinit {
        reassertTimer?.invalidate()
        snoozeTimer?.invalidate()
    }

    private var hasContent: Bool {
        !currentTasks.isEmpty || !currentHealthAlerts.isEmpty
    }

    private func syncOverlay() {
        guard !isSnoozed else { return }
        if hasContent {
            rebuildWindowsIfNeeded()
            for w in windows { w.makeKeyAndOrderFront(nil) }
            NSApp.activate(ignoringOtherApps: true)
            startReassertTimer()
        } else {
            stopReassertTimer()
            for w in windows { w.orderOut(nil) }
        }
    }

    private func rebuildWindowsIfNeeded() {
        let screens = NSScreen.screens
        let frames = screens.map { $0.frame }
        if frames == builtFrames, windows.count == screens.count { return }
        builtFrames = frames
        for w in windows { w.orderOut(nil) }

        windows = screens.map { screen in
            let window = OverlayWindow(contentRect: screen.frame,
                                       styleMask: .borderless,
                                       backing: .buffered,
                                       defer: false,
                                       screen: screen)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OverlayView(model: overlayModel))
            window.onEscape = { [weak self] in self?.snooze() }
            return window
        }

        if hasContent, !isSnoozed {
            for window in windows { window.makeKeyAndOrderFront(nil) }
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func startReassertTimer() {
        guard reassertTimer == nil, !isSnoozed else { return }
        let t = Timer(timeInterval: reassertInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.isSnoozed, self.hasContent else { return }
                for w in self.windows { w.makeKeyAndOrderFront(nil) }
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        reassertTimer = t
    }

    private func stopReassertTimer() {
        reassertTimer?.invalidate()
        reassertTimer = nil
    }

    func snooze() {
        guard hasContent, !isSnoozed else { return }
        stopReassertTimer()
        for w in windows { w.orderOut(nil) }
        isSnoozed = true
        scheduleSnooze()
    }

    private func snoozeInterval() -> TimeInterval {
        if !currentTasks.isEmpty { return reassertInterval }
        return currentHealthAlerts.map(\.repeatIntervalSeconds).min() ?? reassertInterval
    }

    private func scheduleSnooze() {
        snoozeTimer?.invalidate()
        let t = Timer(timeInterval: snoozeInterval(), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        }
        RunLoop.main.add(t, forMode: .common)
        snoozeTimer = t
    }

    func showMessage(_ text: String?) {
        overlayModel.message = text
    }

    func resume() {
        snoozeTimer?.invalidate()
        snoozeTimer = nil
        isSnoozed = false
        syncOverlay()
    }
}
```

- [ ] **Step 4: `AppModel.swift` 接线喝水/起身动作**

在 `start()` 里创建 `reminder` 之后插入两行：

```swift
        reminder.setWaterAction { [weak self] in self?.drinkWater() }
        reminder.setMovementAction { [weak self] in self?.standUp() }
```

即该处最终为：

```swift
        let reminder = ReminderController(interval: settings.effectiveReminderIntervalSeconds) { [weak self] task in
            self?.punch(task)
        }
        reminder.setWaterAction { [weak self] in self?.drinkWater() }
        reminder.setMovementAction { [weak self] in self?.standUp() }
        self.reminder = reminder
```

- [ ] **Step 5: 构建**

Run: `swift build`
Expected: `Build complete!`（`updateHealth` 尚无调用方，未使用不影响编译；行为与之前一致。）

- [ ] **Step 6: 提交**

```bash
git add Sources/Daka/OverlayView.swift Sources/Daka/ReminderController.swift Sources/Daka/AppModel.swift
git commit -m "feat: support health alerts in full-screen overlay"
```

---

### Task 3: 健康提醒改全屏输出，删除本地通知

**Files:**
- Modify: `Sources/Daka/HealthReminderController.swift`
- Delete: `Sources/Daka/GentleNotifier.swift`
- Modify: `Sources/Daka/AppModel.swift`

阶段目标：铁链接通——`HealthReminderController` 按到期集合变化回调 `onHealthAlerts`，`AppModel` 转发给 `ReminderController.updateHealth`；删除 `GentleNotifier` 与 `onSpeak`。

- [ ] **Step 1: 重写 `HealthReminderController.swift`（整文件目标态）**

```swift
import Foundation
import DakaCore

/// 独立的健康提醒调度：按工作时段评估喝水/走动，到期以全屏强提示呈现。
@MainActor
final class HealthReminderController {
    /// 当到期提醒集合变化时回调（空数组表示全部解决）。
    var onHealthAlerts: (([HealthAlert]) -> Void)?
    var onTick: (() -> Void)?

    private let clock: DakaClock
    private let healthStore: HealthStore
    private let scheduleStore: PunchStore
    private let interval: TimeInterval

    private var timer: Timer?
    private var lastEmitted: [HealthAlert] = []

    init(clock: DakaClock,
         healthStore: HealthStore,
         scheduleStore: PunchStore,
         interval: TimeInterval = 30) {
        self.clock = clock
        self.healthStore = healthStore
        self.scheduleStore = scheduleStore
        self.interval = interval
    }

    func start() {
        stop()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        timer?.invalidate()
    }

    func tick() {
        let now = clock.now
        let health = healthStore.data.settings
        let schedule = scheduleStore.data.settings
        let record = healthStore.record(for: now)
        let skipped = scheduleStore.record(for: now).skipped
        let status = HealthRules.status(health: health, schedule: schedule,
                                        record: record, skipped: skipped, now: now)

        var alerts: [HealthAlert] = []

        if status.waterDue {
            let every = TimeInterval(health.effectiveWaterIntervalMinutes * 60)
            let minutes = status.minutesSinceDrink ?? health.effectiveWaterIntervalMinutes
            alerts.append(HealthAlert(kind: .water,
                                      title: "该喝水啦 💧",
                                      body: "已经 \(minutes) 分钟没喝水了，起来接杯水吧。",
                                      repeatIntervalSeconds: every))
        }
        if status.movementDue {
            let every = TimeInterval(health.effectiveMovementIntervalMinutes * 60)
            let minutes = status.minutesSinceStand ?? health.effectiveMovementIntervalMinutes
            alerts.append(HealthAlert(kind: .movement,
                                      title: "起来走两步 🚶",
                                      body: "坐了 \(minutes) 分钟，活动一下肩颈和腿吧。",
                                      repeatIntervalSeconds: every))
        }

        if alerts != lastEmitted {
            lastEmitted = alerts
            onHealthAlerts?(alerts)
        }
        onTick?()
    }
}
```

要点：到期时保持同一条 `HealthAlert` 不变（`lastEmitted` 相等即不重复回调，遮罩持续显示、不会每 30 秒重弹）；喝水/起身后 `status.waterDue/movementDue` 变 false → `alerts` 变化 → 回调移除了对应提醒。

- [ ] **Step 2: 删除 `GentleNotifier.swift`**

```bash
rm Sources/Daka/GentleNotifier.swift
```

- [ ] **Step 3: `AppModel.swift` 接线 `onHealthAlerts` 并即时刷新**

把 `start()` 里的这行：

```swift
        healthReminder.onSpeak = { [weak self] text in self?.say(text) }
```

替换为：

```swift
        healthReminder.onHealthAlerts = { [weak self] alerts in
            guard let self else { return }
            self.reminder?.updateHealth(alerts, settings: self.settings, now: self.now)
        }
```

并让 `logHealth` 记录后立即重算健康提醒（点「已喝水/已起身」可即时关闭遮罩），把：

```swift
    private func logHealth(_ kind: HealthLogKind) throws {
        errorMessage = nil
        do {
            try healthStore.log(kind, at: clock.now)
            refreshHealth()
            scheduler?.tick()
        } catch {
            errorMessage = "记录失败：\(error.localizedDescription)"
            throw error
        }
    }
```

改为：

```swift
    private func logHealth(_ kind: HealthLogKind) throws {
        errorMessage = nil
        do {
            try healthStore.log(kind, at: clock.now)
            refreshHealth()
            scheduler?.tick()
            healthReminder?.tick()
        } catch {
            errorMessage = "记录失败：\(error.localizedDescription)"
            throw error
        }
    }
```

- [ ] **Step 4: 构建与测试**

Run: `swift build`
Expected: `Build complete!`

Run: `swift test`
Expected: 全部 PASS。

Run: `make build`
Expected: `Build complete!`

- [ ] **Step 5: 提交**

```bash
git add Sources/Daka/HealthReminderController.swift Sources/Daka/GentleNotifier.swift Sources/Daka/AppModel.swift
git commit -m "feat: present water and movement reminders as full-screen overlay"
```

---

### Task 4: 文档更新（README + verification.md）

**Files:**
- Modify: `README.md`
- Modify: `docs/verification.md`

- [ ] **Step 1: 更新 `README.md`**

第 18 行：

```markdown
- **喝水 / 走动**：桌宠会定时提醒你喝水、起身活动；点一下即可记录一杯水 / 一次起身，桌宠表情和气泡会回应。提醒只在工作日、打卡工作时段内生效。
```

改为：

```markdown
- **喝水 / 走动**：到点同样以全屏强提示提醒你喝水、起身活动，可一键记录一杯水 / 一次起身。提醒只在工作日、打卡工作时段内生效。
```

第 48 行：

```markdown
- **应用不能随便退出**：菜单栏 / 桌宠 / 工具面板都没有退出入口，Cmd+Q 与 Dock 退出同样被拦截，请让它在后台常驻持续提醒。
```

改为：

```markdown
- **应用不能随便退出**：菜单栏 / 控制中心都没有退出入口，Cmd+Q 与 Dock 退出同样被拦截，请让它在后台常驻持续提醒。
```

第 51 行：

```markdown
- 全屏遮罩可用 **ESC 暂停**：立即隐藏，过「重复提醒」间隔后自动重新弹出，直到完成打卡；Cmd+W / Cmd+M / Cmd+H 仍无效。
```

改为：

```markdown
- 全屏遮罩可用 **ESC 暂停**：立即隐藏，过「重复提醒」间隔后自动重新弹出，直到完成打卡或健康动作；Cmd+W / Cmd+M / Cmd+H 仍无效。
```

并在第 52 行「打卡后若当天仍未完成…」那条之后追加：

```markdown
- 喝水 / 走动到点同样弹出全屏强提示（含「已喝水」「已起身」按钮），打卡与健康提醒可同一全屏同时出现，处理完一样即自动收起对应部分。
```

项目结构清单，「DakaCore」行：

```markdown
    DakaDate.swift / PunchRules.swift / PunchTarget.swift / PetMood.swift / ToolCatalog.swift 日期、打卡规则与工具目录
```

改为：

```markdown
    DakaDate.swift / PunchRules.swift / PunchTarget.swift / ToolCatalog.swift 日期、打卡规则与工具目录
```

「Daka」行：

```markdown
    ReminderController.swift / OverlayView.swift
    PetView.swift / PetWindowController.swift / PetSpeechBubble.swift / ToolPanelView.swift
    HealthReminderController.swift / HealthToolViews.swift
    GentleNotifier.swift / LoginItemManager.swift / ScheduledLaunchManager.swift
```

改为：

```markdown
    ReminderController.swift / OverlayView.swift
    HealthReminderController.swift / HealthToolViews.swift
    LoginItemManager.swift / ScheduledLaunchManager.swift
```

- [ ] **Step 2: 更新 `docs/verification.md`**

1. 把「## v7：桌面宠物平台」整个小节内容替换为一行说明：

```markdown
## v7：桌面宠物平台（v17 起桌宠已移除，本节不再适用）
```

2. 「## 退出拦截（v8）」第一条改为：

```markdown
- [ ] 菜单栏面板 / 控制中心中都没有退出入口。
```

（删除该小节末尾「- [ ] 桌宠右键菜单为：打开控制中心 / 隐藏桌宠；无「退出 Daka」。」与「- [ ] 工具面板底部只有「控制中心」；无「退出」。」两条。）

3. 删除「## v9：…」小节的这两条：

```markdown
- [ ] 控制中心窗口右上角工具栏有桌宠图标，点击可显示/隐藏桌宠，图标随可见性变化。
- [ ] 桌宠右键「显示/隐藏桌宠」仍可用。
```

4. 「## v11：健康习惯（喝水 / 走动）」中：

- 「点「喝了一杯水」」一条改为：

```markdown
- [ ] 点「喝了一杯水」→ 今日杯数 +1、柱状图当天柱升高。
```

- 「点「起来走走」」一条改为：

```markdown
- [ ] 点「起来走走」→ 今日起身次数 +1。
```

- 删除「- [ ] 桌宠面板「今日概览」显示实时杯数/起身次数，并有「喝水」「走动」快捷按钮。」一条。

- 上间隔提醒一条改为：

```markdown
- [ ] 在工作日、打卡工作时段内，距上次记录超过间隔后弹出全屏强提示（喝水 💧 / 起身 🚶），不同时到上周各显示一行。
```

- 「记录后对应表情恢复」一条改为：

```markdown
- [ ] 记录后对应全屏提示消失；关闭「启用提醒」后不再提醒。
```

5. 「## v13：…」里这条改为：

```markdown
- [ ] 打卡提醒不再发送「窗口内」系统通知；喝水/走动改为全屏强提示（不再发系统通知）。
```

6. 删除「## v16：…」末尾「- [ ] 桌宠气泡面板里的圆形按钮同样显示两行。」一条。

7. 文件末尾追加：

```markdown
## v17：移除桌宠 + 健康全屏强提示

- [ ] 桌面不再出现桌宠；控制中心窗口右上角无掌印图标；无「工具面板」弹层。
- [ ] 喝水到点 → 全屏「该喝水啦 💧」+「已喝水」按钮；点按钮 → 记录一杯、遮罩收起。
- [ ] 久坐到点 → 全屏「起来走两步 🚶」+「已起身」按钮；点按钮 → 记录一次、遮罩收起。
- [ ] 只弹健康提示时按 ESC → 遮罩隐藏，过一个提醒间隔（喝水/走动间隔）后重新弹出。
- [ ] 打卡与健康同时到期 → 同一全屏同时显示打卡按钮与健康区；打个少个、喝杯少饮水，全部处理完遮罩消失。
- [ ] 打卡完成后若健康仍未处理 → 遮罩不闪断，继续只显示健康区。
- [ ] 通过控制中心「喝了一杯水 / 起来走走」记录后，正在显示的健康全屏立即收起。
- [ ] 系统不再发送喝水/走动本地通知（已删除通知权限请求）。
- [ ] 打卡全部既有行为无回归（强提醒、ESC 暂停、重复间隔、最少工时、休假、定点启动）。
```

- [ ] **Step 3: 提交**

```bash
git add README.md docs/verification.md
git commit -m "docs: update README and verification for pet removal and health fullscreen"
```

---

## 完成后

- `swift test` 全绿；`make build` 成功。
- `make install` 后按 `docs/verification.md` 的 v17 清单手动验证，并回归打卡强提醒。