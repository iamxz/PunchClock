# Daka v9：控制中心入口与桌宠工具栏开关 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把菜单栏面板的「控制中心」入口移到面板右上角并改用图标；把「桌宠」显示/隐藏开关从菜单栏移入控制中心窗口右上角工具栏。

**Architecture:** 菜单栏面板（`MenuBarView`）标题行内联一个 `switch.2` 图标按钮；控制中心窗口把内容宿主从 `NSHostingView` 换成 `NSHostingController`，从而让 SwiftUI `.toolbar` 能把一个桌宠开关安装到窗口标题栏右上角（`primaryAction`）。桌宠开关复用既有的 `AppModel.setPetVisible(_:)`。

**Tech Stack:** Swift 5.10+、SwiftUI、AppKit、Swift Package Manager。改动限于 `Sources/Daka`（无 `DakaCore` 逻辑变更）。

**关于测试：** 本改动位于 SwiftUI/AppKit 层，`Tests/DakaCoreTests` 只覆盖 `DakaCore`，无法单元测试。每个任务以 `make build` 为自动门禁；界面位置/交互用「手动验证步骤」验证，不写伪造单测。

---

## 文件结构

- `Sources/Daka/MenuBarView.swift` — 面板标题行内联控制中心图标；移除底部按钮。
- `Sources/Daka/MainWindowController.swift` — 用 `NSHostingController` 作为窗口 `contentViewController`。
- `Sources/Daka/ControlCenterView.swift` — 增加 `.toolbar` 桌宠开关 + `PetToolbarToggle` 视图。
- `README.md`、`docs/verification.md` — 描述更新。

任务顺序保证每步可编译：先改菜单栏（Task 1），再改控制中心（Task 2），最后文档（Task 3）。

---

### Task 1: 菜单栏面板右上角控制中心图标

**Files:**
- Modify: `Sources/Daka/MenuBarView.swift:7-41`

- [ ] **Step 1: 改写 body 顶部与底部**

将 `Sources/Daka/MenuBarView.swift` 中 `var body: some View { ... }` 的整个 `VStack` 内容替换为：

```swift
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("今日打卡").font(.headline)
                Spacer()
                Button {
                    model.openControlCenter()
                } label: {
                    Image(systemName: "switch.2")
                }
                .buttonStyle(.plain)
                .help("打开控制中心")
            }

            VStack(spacing: 6) {
                statusRow(.morning, done: model.record.morningDone, at: model.record.morningDoneAt,
                          count: model.record.morningPunches.count,
                          start: model.settings.morningWindowStart, deadline: model.settings.morningDeadline)
                statusRow(.evening, done: model.isEveningComplete, at: model.effectiveEveningPunch,
                          count: model.record.eveningPunches.count,
                          start: model.settings.eveningWindowStart, deadline: model.settings.eveningDeadline)
            }

            PunchButton(task: PunchTarget.resolve(record: model.record,
                                                  now: model.now,
                                                  minWorkDuration: model.minWorkDuration)) { task in
                model.punch(task)
            }
        }
        .padding(16)
        .frame(width: 220)
    }
```

即：删除原来的 `Text("今日打卡").font(.headline)` 单行、底部的 `Divider()`、`Button("控制中心")`、以及「显示桌宠 / 隐藏桌宠」按钮；其余 `statusRow` 调用与 `PunchButton` 保持不变。

- [ ] **Step 2: 编译验证**

Run: `make build`
Expected: `Build complete!`，无 warning/error。

- [ ] **Step 3: 确认旧入口已删除**

Run: `rg -n "显示桌宠|隐藏桌宠|Button\(\"控制中心\"\)" Sources/Daka/MenuBarView.swift`
Expected: 无输出。

- [ ] **Step 4: 提交**

```bash
git add Sources/Daka/MenuBarView.swift
git commit -m "feat: move control center entry to menu bar top-right icon"
```

---

### Task 2: 控制中心窗口右上角桌宠工具栏开关

**Files:**
- Modify: `Sources/Daka/MainWindowController.swift:16-27`
- Modify: `Sources/Daka/ControlCenterView.swift:7-25`

- [ ] **Step 1: 用 NSHostingController 承载控制中心视图**

在 `Sources/Daka/MainWindowController.swift` 的 `show()` 中，把：

```swift
            let hosting = NSHostingView(rootView: ControlCenterView(model: model))
            let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered,
                                   defer: false)
            created.title = "Daka"
            created.isReleasedWhenClosed = false
            created.contentView = hosting
```

替换为：

```swift
            let created = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 600),
                                   styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                   backing: .buffered,
                                   defer: false)
            created.title = "Daka"
            created.isReleasedWhenClosed = false
            created.contentViewController = NSHostingController(rootView: ControlCenterView(model: model))
```

（其余 `created.delegate = self`、`created.center()`、`created.setFrameAutosaveName("DakaMainWindow")`、`window = created` 保持不变。`MainWindowController.swift` 已 `import SwiftUI`。）

- [ ] **Step 2: 给 ControlCenterView 加工具栏**

在 `Sources/Daka/ControlCenterView.swift` 的 `body` 里，把：

```swift
        .frame(minWidth: 720, minHeight: 520)
    }
```

替换为：

```swift
        .frame(minWidth: 720, minHeight: 520)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PetToolbarToggle(model: model)
            }
        }
    }
```

- [ ] **Step 3: 新增 PetToolbarToggle 视图**

在 `Sources/Daka/ControlCenterView.swift` 文件末尾（最后一个 `}` 之后）追加：

```swift

private struct PetToolbarToggle: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button {
            model.setPetVisible(!model.petVisible)
        } label: {
            Image(systemName: model.petVisible ? "pawprint.fill" : "pawprint")
        }
        .help(model.petVisible ? "隐藏桌宠" : "显示桌宠")
    }
}
```

- [ ] **Step 4: 编译验证**

Run: `make build`
Expected: `Build complete!`，无 warning/error。

- [ ] **Step 5: 启动冒烟测试（视觉确认交给用户）**

子代理无法“看”窗口，因此这里只做启动冒烟测试；工具栏是否显示由用户/控制器在安装后确认。

因为同一 bundle id 的单实例保护会把 `build/Daka.app` 的重启转交给正在运行的实例，先结束已运行实例再启动开发构建：

Run: `make app && pkill -x Daka; sleep 1; open build/Daka.app; sleep 3; pgrep -x Daka`

Expected: `pgrep` 输出一个 PID（新版已启动）。随后可用 `pkill -x Daka` 收尾，避免残留。

- 若用户后续反馈工具栏图标未出现（SwiftUI `.toolbar` 未安装到该窗口），再执行 Step 6 的回退方案；子代理不要自行判断。

- [ ] **Step 6（仅当视觉确认工具栏未出现时）: NSToolbar 回退方案**

a. 把 `ControlCenterView.swift` 里的 `private struct PetToolbarToggle` 改为非 `private`：

```swift
struct PetToolbarToggle: View {
```

b. 在 `MainWindowController` 增加 `NSToolbarDelegate` 实现，并在 `show()` 里 `created.contentViewController = ...` 之后加上：

```swift
            let toolbar = NSToolbar(identifier: "DakaControlCenterToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            created.toolbar = toolbar
```

c. 在 `MainWindowController` 类内新增：

```swift
    private let petToolbarItemID = NSToolbarItem.Identifier("DakaPetToggle")

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [petToolbarItemID, .flexibleSpace]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, petToolbarItemID]
    }

    func toolbar(_ toolbar: NSToolbar,
                 itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == petToolbarItemID else { return nil }
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "桌宠"
        item.paletteLabel = "桌宠"
        let host = NSHostingView(rootView: PetToolbarToggle(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 34, height: 24)
        item.view = host
        return item
    }
```

并在 `MainWindowController` 的类声明行加上 `NSToolbarDelegate`：

```swift
final class MainWindowController: NSObject, NSWindowDelegate, NSToolbarDelegate {
```

然后重新 `make build` → `Build complete!`。

- [ ] **Step 7: 提交**

```bash
git add Sources/Daka/MainWindowController.swift Sources/Daka/ControlCenterView.swift
git commit -m "feat: add pet visibility toggle to control center toolbar"
```

---

### Task 3: 文档与手动验证清单

**Files:**
- Modify: `README.md:44`
- Modify: `docs/verification.md:8`、`:68`、`:94`，文末新增 v9 段

- [ ] **Step 1: 更新 README**

把 `README.md` 第 44 行：

```markdown
- 菜单栏面板只含：今日状态、打卡按钮、「控制中心」、桌宠开关。
```

替换为：

```markdown
- 菜单栏面板：右上角「控制中心」图标（`switch.2`）+ 今日状态 + 打卡按钮。
```

- [ ] **Step 2: 更新 verification.md 面板描述**

把 `docs/verification.md` 第 8 行：

```markdown
- [ ] 菜单栏面板只有：今日状态、打卡按钮、「控制中心」、桌宠开关（设置与统计在主窗口）。
```

替换为：

```markdown
- [ ] 菜单栏面板：右上角有「控制中心」图标，下面是今日状态与打卡按钮。
```

把第 68 行：

```markdown
- [ ] 状态栏面板只剩：今日状态、打卡按钮、「控制中心」、桌宠开关；不再有设置与统计。
```

替换为：

```markdown
- [ ] 状态栏面板只剩：今日状态、打卡按钮、右上角「控制中心」图标；不再有桌宠开关与设置/统计。
```

把第 94 行：

```markdown
- [ ] 菜单栏可切换「显示/隐藏桌宠」；「控制中心」按钮打开主窗口。
```

替换为：

```markdown
- [ ] 控制中心窗口右上角工具栏可切换「显示/隐藏桌宠」；菜单栏面板右上角图标打开控制中心。
```

- [ ] **Step 3: 追加 v9 段**

在 `docs/verification.md` 末尾追加：

```markdown
## v9：控制中心入口与桌宠工具栏开关

- [ ] 菜单栏面板右上角为「控制中心」图标（switch.2），点击打开控制中心窗口。
- [ ] 菜单栏面板中不再有「桌宠」开关与底部文字「控制中心」按钮。
- [ ] 控制中心窗口右上角工具栏有桌宠图标，点击可显示/隐藏桌宠，图标随可见性变化。
- [ ] 桌宠右键「显示/隐藏桌宠」仍可用。
```

- [ ] **Step 4: 测试与编译**

Run: `make test`
Expected: 全部通过（`Executed ... tests, with 0 failures`）。

Run: `make build`
Expected: `Build complete!`。

- [ ] **Step 5: 提交**

```bash
git add README.md docs/verification.md
git commit -m "docs: describe control center icon and pet toolbar toggle (v9)"
```

---

## 验证汇总

- 自动：`make build` 通过；`make test` 全绿。
- 手动：
  - 菜单栏面板右上角 `switch.2` 图标可打开控制中心；面板中无桌宠开关、无底部文字「控制中心」。
  - 控制中心窗口右上角工具栏爪印图标可显示/隐藏桌宠，图标随可见性变化。
  - 桌宠右键「显示/隐藏桌宠」仍可用。

## 交付

- `make install` 更新 `Daka.app`。
- 文档：`README.md`、`docs/verification.md`、本 plan、spec `docs/superpowers/specs/2026-09-15-daka-control-center-toolbar-design.md`。
