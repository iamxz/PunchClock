# Daka v8：禁止随便退出 / 后台常驻 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Daka 在任何情况下都无法正常退出（系统注销/关机/重启除外），保持后台常驻持续提醒；仅在设置页保留一个二次确认的退出入口。

**Architecture:** macOS 所有退出路径（Cmd+Q、`NSApp.terminate`、菜单、系统注销）都汇聚到 `NSApplicationDelegate.applicationShouldTerminate`。以它作为唯一闸门，用一个 `AppModel.allowTermination` 标志决定放行或取消；系统关机时通过 `NSWorkspace.willPowerOffNotification` 预先置位放行。所有日常退出 UI 移除，设置页提供确认退出。

**Tech Stack:** Swift 5.10+、AppKit、SwiftUI、Swift Package Manager。行为改动集中在 `Sources/Daka`（AppKit/SwiftUI 层）；`DakaCore` 与 `make test` 不受影响。

**关于测试：** 本改动全部位于 AppKit/SwiftUI 胶水层，项目测试目标 `Tests/DakaCoreTests` 只覆盖 `DakaCore` 纯逻辑，无法对 `NSApplicationDelegate` 终止行为做单元测试。因此每个任务以 `make build`（编译通过）为自动门禁，终止行为用「手动验证步骤」验证，不写伪造的单测。

---

## 文件结构

- `Sources/Daka/AppModel.swift` — 持有 `allowTermination`，提供 `confirmQuit()`（NSAlert 二次确认）。职责：状态 + 退出确认交互入口。
- `Sources/Daka/AppDelegate.swift` — 终止闸门 `applicationShouldTerminate` + 系统关机放行观察者。职责：唯一系统级退出裁决。
- `Sources/Daka/MenuBarView.swift`、`Sources/Daka/PetView.swift`、`Sources/Daka/ToolPanelView.swift` — 移除日常退出按钮。
- `Sources/Daka/SettingsView.swift` — 新增「应用」Section，放确认退出按钮。
- `README.md`、`docs/verification.md` — 文档与手动验证清单更新。

任务顺序保证每一步都能编译：先加闸门与新入口（Task 1），再移除旧入口（Task 2），再加设置入口（Task 3），最后文档与整体验证（Task 4）。

---

### Task 1: 终止闸门（AppModel + AppDelegate）

**Files:**
- Modify: `Sources/Daka/AppModel.swift:26`（新增标志）、`Sources/Daka/AppModel.swift:211-213`（`quit()` → `confirmQuit()`）
- Modify: `Sources/Daka/AppDelegate.swift:17-40`（注册关机观察者）、`Sources/Daka/AppDelegate.swift:51-54`（闸门逻辑）

- [ ] **Step 1: 在 AppModel 增加 allowTermination 标志**

在 `Sources/Daka/AppModel.swift` 第 26 行 `var hasHardTasks: Bool { !reminderState.hard.isEmpty }` 下方新增：

```swift
    /// 唯一放行退出的开关：设置页确认退出、或系统关机时置 true。
    var allowTermination = false
```

- [ ] **Step 2: 新增确认退出 confirmQuit()（本步保留旧 quit()）**

在 `Sources/Daka/AppModel.swift` 末尾的 `func quit()` 之后新增 `confirmQuit()`（**先不要删 `quit()`**，三个旧调用点要等 Task 2 移除）：

```swift
    func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "退出 Daka？"
        alert.informativeText = "退出后将无法提醒打卡，直到下次开机或手动启动。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "仍要退出")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        allowTermination = true
        NSApp.terminate(nil)
    }
```

（`AppModel.swift` 顶部已 `import AppKit`，`NSAlert` 可用。此时旧 `quit()` 仍会走闸门被取消，属预期的过渡状态。）

- [ ] **Step 3: 在 AppDelegate 注册系统关机观察者**

在 `Sources/Daka/AppDelegate.swift` 的 `applicationDidFinishLaunching` 中，紧跟 `NSApp.setActivationPolicy(.regular)` 之后插入：

```swift
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWillPowerOff(_:)),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
```

并在 `applicationWillFinishLaunching` 方法之后新增方法：

```swift
    @objc private func systemWillPowerOff(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.allowTermination = true }
    }
```

- [ ] **Step 4: 改写 applicationShouldTerminate 为统一闸门**

把 `Sources/Daka/AppDelegate.swift` 中的：

```swift
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let hard = MainActor.assumeIsolated { AppModel.shared.hasHardTasks }
        return hard ? .terminateCancel : .terminateNow
    }
```

替换为：

```swift
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { AppModel.shared.allowTermination } ? .terminateNow : .terminateCancel
    }
```

（注意：此时 `hasHardTasks` 仍被 Task 2 之前的菜单/工具面板引用，暂不删除。）

- [ ] **Step 5: 编译验证**

Run: `make build`
Expected: 编译成功（`Build complete`），无 warning/error。

- [ ] **Step 6: 提交**

```bash
git add Sources/Daka/AppModel.swift Sources/Daka/AppDelegate.swift
git commit -m "feat: block quit via single termination gate, allow on power off"
```

---

### Task 2: 移除三个日常退出入口，清理 hasHardTasks

**Files:**
- Modify: `Sources/Daka/MenuBarView.swift:28-37`
- Modify: `Sources/Daka/PetView.swift:28-33`
- Modify: `Sources/Daka/ToolPanelView.swift:46-52`
- Modify: `Sources/Daka/AppModel.swift:26`（删除死代码）

- [ ] **Step 1: 菜单栏面板去掉「退出」**

在 `Sources/Daka/MenuBarView.swift` 中，把：

```swift
            HStack {
                Button("控制中心") { model.openControlCenter() }
                    .frame(maxWidth: .infinity)
                Button("退出") { model.quit() }
                    .frame(maxWidth: .infinity)
                    .disabled(model.hasHardTasks)
            }
            Button(model.petVisible ? "隐藏桌宠" : "显示桌宠") {
                model.setPetVisible(!model.petVisible)
            }
```

替换为：

```swift
            Button("控制中心") { model.openControlCenter() }
                .frame(maxWidth: .infinity)
            Button(model.petVisible ? "隐藏桌宠" : "显示桌宠") {
                model.setPetVisible(!model.petVisible)
            }
```

- [ ] **Step 2: 桌宠右键菜单去掉「退出 Daka」**

在 `Sources/Daka/PetView.swift` 中，把：

```swift
        .contextMenu {
            Button("打开控制中心") { model.openControlCenter() }
            Button(model.petVisible ? "隐藏桌宠" : "显示桌宠") { model.setPetVisible(!model.petVisible) }
            Divider()
            Button("退出 Daka") { model.quit() }
        }
```

替换为：

```swift
        .contextMenu {
            Button("打开控制中心") { model.openControlCenter() }
            Button(model.petVisible ? "隐藏桌宠" : "显示桌宠") { model.setPetVisible(!model.petVisible) }
        }
```

- [ ] **Step 3: 工具面板去掉「退出」**

在 `Sources/Daka/ToolPanelView.swift` 中，把：

```swift
            HStack {
                Button("控制中心") { onClose(); model.openControlCenter() }
                    .frame(maxWidth: .infinity)
                Button("退出") { model.quit() }
                    .frame(maxWidth: .infinity)
                    .disabled(model.hasHardTasks)
            }
```

替换为：

```swift
            Button("控制中心") { onClose(); model.openControlCenter() }
                .frame(maxWidth: .infinity)
```

- [ ] **Step 4: 删除死代码 hasHardTasks 与 quit()**

确认已无引用：

Run: `rg -n "hasHardTasks|model.quit\(\)" Sources`
Expected: 无任何输出（AppDelegate 的引用已在 Task 1 改为 `allowTermination`，三个调用点已在 Step 1–3 删除）。

若确认为空，在 `Sources/Daka/AppModel.swift` 删除第 26 行：

```swift
    var hasHardTasks: Bool { !reminderState.hard.isEmpty }
```

并删除末尾已无人调用的旧方法：

```swift
    func quit() {
        NSApp.terminate(nil)
    }
```

（`ReminderState.hard` 本身仍用于遮罩与菜单栏图标，保留。）

- [ ] **Step 5: 编译验证**

Run: `make build`
Expected: 编译成功（`Build complete`），无 warning/error。

- [ ] **Step 6: 提交**

```bash
git add Sources/Daka/MenuBarView.swift Sources/Daka/PetView.swift Sources/Daka/ToolPanelView.swift Sources/Daka/AppModel.swift
git commit -m "feat: remove everyday quit entry points"
```

---

### Task 3: 设置页新增确认退出入口

**Files:**
- Modify: `Sources/Daka/SettingsView.swift:68`（在「调试」Section 前插入）

- [ ] **Step 1: 新增「应用」Section**

在 `Sources/Daka/SettingsView.swift` 中，紧接 `Section("自启与定点") { ... }` 之后、`Section("调试")` 之前插入：

```swift
            Section("应用") {
                Button("退出应用") { model.confirmQuit() }
            }
```

- [ ] **Step 2: 编译验证**

Run: `make build`
Expected: 编译成功（`Build complete`）。

- [ ] **Step 3: 组装并运行，手动验证退出行为**

Run: `make app && open build/Daka.app`

依次验证：
1. 点击菜单栏图标 → 面板中**没有**「退出」；右键桌宠 → 菜单中**没有**「退出 Daka」。
2. 任意阶段按 Cmd+Q → 应用**不退出**（仍常驻）。
3. 主窗口「设置 → 应用 → 退出应用」→ 弹出「退出 Daka？」确认框；点「取消」应用仍在；再次点击并点「仍要退出」→ 应用退出。
4. 重新 `open build/Daka.app`，然后 菜单栏 → 设置 → 应用 → 退出应用 → 确认退出；确认进程消失：`pgrep -x Daka` 无输出。

- [ ] **Step 4: 提交**

```bash
git add Sources/Daka/SettingsView.swift
git commit -m "feat: add confirmed quit entry in settings"
```

---

### Task 4: 文档、手动验证清单与整体验证

**Files:**
- Modify: `README.md:42-46`、`README.md:118-122`
- Modify: `docs/verification.md:7-8`、`docs/verification.md:30-33`、`docs/verification.md:64-65`、`docs/verification.md:89-91`、文末新增 v8 段

- [ ] **Step 1: 更新 README 使用说明**

在 `README.md` 中，把第 44–46 行：

```markdown
- 菜单栏面板只含：今日状态、两个打卡按钮、「打开 Daka」、退出。
- **强制提醒阶段**：全屏遮罩无法用 ESC、Cmd+W、Cmd+M、Cmd+H 关闭，菜单「退出 Daka」置灰、Cmd+Q 无效；完成对应打卡后自动消失。
- 温和阶段可正常退出应用。
```

替换为：

```markdown
- 菜单栏面板只含：今日状态、打卡按钮、「控制中心」、桌宠开关。
- **应用不能随便退出**：任何阶段都不提供日常退出入口，Cmd+Q 同样无效，请让它在后台常驻持续提醒。
- **需要退出时**：主窗口「设置 → 应用 → 退出应用」，二次确认后才退出。
- **系统注销 / 关机 / 重启**时允许应用退出，不会阻碍关机。
- 全屏强制遮罩仍无法用 ESC、Cmd+W、Cmd+M、Cmd+H 关闭；完成对应打卡后自动消失。
```

- [ ] **Step 2: 更新 README 已知限制**

在 `README.md` 已知限制中，把第一条：

```markdown
- macOS 不允许普通应用完全锁死系统：**强制退出（Cmd+Opt+Esc / `kill -9`）无法被屏蔽**。「无法绕过」指置顶全屏、屏蔽 ESC/关闭/Cmd+Q、每 2 分钟重弹。
```

替换为：

```markdown
- macOS 不允许普通应用完全锁死系统：**强制退出（Cmd+Opt+Esc / `kill -9`）无法被屏蔽**。日常退出入口（菜单/Cmd+Q）全部拦截，但强制退出无法阻止；系统注销/关机/重启放行。
```

- [ ] **Step 3: 更新 verification.md 面板描述**

在 `docs/verification.md` 把第 8 行：

```markdown
- [ ] 菜单栏面板只有：今日状态、两个打卡按钮、「打开 Daka」、退出（设置与统计在主窗口）。
```

替换为：

```markdown
- [ ] 菜单栏面板只有：今日状态、打卡按钮、「控制中心」、桌宠开关（设置与统计在主窗口）。
```

把第 65 行：

```markdown
- [ ] 状态栏面板只剩：今日状态、两个打卡按钮、「打开 Daka」、退出；不再有设置与统计。
```

替换为：

```markdown
- [ ] 状态栏面板只剩：今日状态、打卡按钮、「控制中心」、桌宠开关；不再有设置与统计。
```

- [ ] **Step 4: 替换「退出拦截」段并新增 v8 段**

在 `docs/verification.md` 把整段：

```markdown
## 退出拦截

- [ ] 温和阶段可正常退出。
- [ ] hard 阶段菜单「退出 Daka」置灰、Cmd+Q 无效。
```

替换为：

```markdown
## 退出拦截（v8）

- [ ] 菜单栏面板 / 桌宠右键菜单 / 工具面板中都没有退出入口。
- [ ] 任何阶段（无任务、温和、强制）按 Cmd+Q 均无效，应用不退出。
- [ ] 设置页「应用 → 退出应用」弹确认框：点「取消」应用仍在；点「仍要退出」应用退出。
- [ ] 系统注销 / 关机 / 重启时应用正常结束，不卡关机。
- [ ] Cmd+Opt+Esc 强制退出仍可结束应用（已知限制，无法屏蔽）。
```

在文件末尾追加：

```markdown
## v8：禁止随便退出 / 后台常驻

- [ ] 桌宠右键菜单为：打开控制中心 / 隐藏桌宠；无「退出 Daka」。
- [ ] 工具面板底部只有「控制中心」；无「退出」。
- [ ] 从设置页确认退出后进程消失；`pgrep -x Daka` 无输出。
- [ ] 从设置页取消退出后进程仍在，且继续按当前等级提醒。
```

- [ ] **Step 5: 运行测试与整体编译**

Run: `make test`
Expected: 所有 DakaCore 测试通过（`Executed ... tests, with 0 failures`）。

Run: `make build`
Expected: `Build complete`。

- [ ] **Step 6: 提交**

```bash
git add README.md docs/verification.md
git commit -m "docs: describe no-quit resident behavior (v8)"
```

---

## 验证汇总

- 自动：`make build` 通过；`make test` 全绿（无 DakaCore 改动，验证无回归）。
- 手动（Task 3 / Task 4 清单）：无日常退出入口、Cmd+Q 无效、设置页确认退出可用、关机放行、强退不可屏蔽、取消退出后继续提醒。

## 交付

- 更新后的 `Daka.app`：`make install`。
- 文档：`README.md`、`docs/verification.md`、本 plan、spec `docs/superpowers/specs/2026-09-15-daka-no-quit-resident-design.md`。
