# Daka v10：设置独立为左侧菜单 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把系统设置从「打卡统计」工具页的分段标签中拆出，左侧菜单新增「设置」分组（打卡时间 / 工作日 / 考勤规则 / 系统与启动 四个子页）；「今天不打卡」移到打卡统计页顶部。

**Architecture:** 用统一的 `SidebarSelection` 枚举（`.tool(ToolID)` / `.settings(SettingsPage)`）替换 `AppModel.selectedTool`，让 `NavigationSplitView` 的 `List` 用同一个 selection 同时管理工具与设置子页。原 `SettingsView` 按语义拆成 4 个 `Form` 子视图；错误/警告抽成 `SettingsFeedbackView` 附在「系统与启动」页。

**Tech Stack:** Swift 5.10+、SwiftUI、AppKit、Swift Package Manager。改动限于 `Sources/Daka`（无 `DakaCore` 逻辑变更）。

**关于测试：** 本改动位于 SwiftUI/AppKit 层，`Tests/DakaCoreTests` 只覆盖 `DakaCore`，无法单元测试。每个任务以 `make build` 为自动门禁；界面交互用「手动验证步骤」验证，不写伪造单测。

**Spec:** `docs/superpowers/specs/2026-09-15-daka-settings-sidebar-design.md`

---

## 文件结构

- 新增 `Sources/Daka/SettingsPage.swift` — `SettingsPage` 与 `SidebarSelection` 枚举（纯 UI 元数据）。
- 新增 `Sources/Daka/SettingsPages.swift` — `ScheduleSettingsView` / `WorkdaySettingsView` / `AttendanceSettingsView` / `SystemSettingsView` / `SettingsFeedbackView`。
- 修改 `Sources/Daka/AppModel.swift` — `selectedTool` → `selectedSidebar`；`select(_:)`；`hasSettingsFeedback`。
- 修改 `Sources/Daka/ControlCenterView.swift` — 侧边栏两段 + 按 `SidebarSelection` 分发 detail。
- 修改 `Sources/Daka/PunchToolView.swift` — 去掉分段控件，顶部加「今天不打卡」按钮。
- 删除 `Sources/Daka/SettingsView.swift` — 内容被 `SettingsPages.swift` 取代。
- 修改 `README.md`、`docs/verification.md` — 描述更新。

任务顺序保证每步可编译：先建枚举（Task 1）→ 建新子页（Task 2）→ 接侧边栏选择（Task 3）→ 改打卡页并删旧设置页（Task 4）→ 文档（Task 5）。

---

### Task 1: 新增 SettingsPage / SidebarSelection 枚举

**Files:**
- Create: `Sources/Daka/SettingsPage.swift`

- [ ] **Step 1: 新建枚举文件**

创建 `Sources/Daka/SettingsPage.swift`：

```swift
import DakaCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case schedule, workdays, attendance, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: return "打卡时间"
        case .workdays: return "工作日"
        case .attendance: return "考勤规则"
        case .system: return "系统与启动"
        }
    }

    var symbol: String {
        switch self {
        case .schedule: return "clock"
        case .workdays: return "calendar"
        case .attendance: return "checklist"
        case .system: return "gearshape"
        }
    }
}

enum SidebarSelection: Hashable {
    case tool(ToolID)
    case settings(SettingsPage)
}
```

- [ ] **Step 2: 编译验证**

Run: `make build`
Expected: `Build complete!`，无 error。

- [ ] **Step 3: 提交**

```bash
git add Sources/Daka/SettingsPage.swift
git commit -m "feat: add settings page and sidebar selection enums (v10)"
```

---

### Task 2: 拆出四个设置子页视图

**Files:**
- Create: `Sources/Daka/SettingsPages.swift`
- Modify: `Sources/Daka/AppModel.swift`（新增 `hasSettingsFeedback`）
- 保留 `Sources/Daka/SettingsView.swift`（本任务暂不删，Task 4 处理）

- [ ] **Step 1: 新建子页文件**

创建 `Sources/Daka/SettingsPages.swift`（内容来自现 `SettingsView.swift` 的拆分，无逻辑变化）：

```swift
import SwiftUI
import DakaCore

private let settingsWeekdayOptions: [(label: String, value: Int)] = [
    ("一", 2), ("二", 3), ("三", 4), ("四", 5), ("五", 6), ("六", 7), ("日", 1)
]

private func settingsDateFrom(_ hhmm: String, now: Date) -> Date {
    DakaDate.date(on: now, at: hhmm) ?? now
}

private func settingsHHMM(from date: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
}

private func settingsHoursText(_ hours: Double) -> String {
    hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
}

struct ScheduleSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Toggle("启用提醒", isOn: Binding(get: { model.settings.enabled },
                                            set: { model.setEnabled($0) }))

            Section("打卡窗口") {
                DatePicker("上班窗口开始", selection: bound(\.morningWindowStart, model.updateMorningStart),
                           displayedComponents: .hourAndMinute)
                DatePicker("上班窗口截止", selection: bound(\.morningDeadline, model.updateMorningDeadline),
                           displayedComponents: .hourAndMinute)
                DatePicker("下班窗口开始", selection: bound(\.eveningWindowStart, model.updateEveningStart),
                           displayedComponents: .hourAndMinute)
                DatePicker("下班窗口截止", selection: bound(\.eveningDeadline, model.updateEveningDeadline),
                           displayedComponents: .hourAndMinute)
            }
        }
        .formStyle(.grouped)
    }

    private func bound(_ keyPath: KeyPath<DakaCore.Settings, String>,
                       _ update: @escaping (String) -> Void) -> Binding<Date> {
        Binding(get: { settingsDateFrom(model.settings[keyPath: keyPath], now: model.now) },
                set: { update(settingsHHMM(from: $0)) })
    }
}

struct WorkdaySettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("工作日") {
                HStack {
                    ForEach(settingsWeekdayOptions, id: \.value) { option in
                        Toggle(option.label, isOn: weekdayBinding(option.value))
                            .toggleStyle(.button)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func weekdayBinding(_ value: Int) -> Binding<Bool> {
        Binding(get: { model.settings.workdays.contains(value) },
                set: { on in
                    var days = model.settings.workdays
                    if on { days.insert(value) } else { days.remove(value) }
                    model.setWorkdays(days)
                })
    }
}

struct AttendanceSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("考勤规则") {
                Stepper(value: Binding(get: { model.settings.minWorkDurationHours },
                                       set: { model.setMinWorkHours($0) }),
                        in: 1...12, step: 0.5) {
                    Text("每日最少工时：\(settingsHoursText(model.settings.minWorkDurationHours)) 小时")
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct SystemSettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section("自启与定点") {
                HStack {
                    Image(systemName: LoginItemManager.isEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(LoginItemManager.isEnabled ? Color.green : Color.orange)
                    Text(LoginItemManager.isEnabled ? "开机自启已启用"
                         : (LoginItemManager.requiresApproval ? "开机自启需在系统设置中允许" : "开机自启未启用"))
                    Spacer()
                    if LoginItemManager.requiresApproval {
                        Button("打开设置") { LoginItemManager.openSystemSettings() }
                    } else if !LoginItemManager.isEnabled {
                        Button("启用") { model.repairLoginItem() }
                    }
                }
                HStack {
                    Image(systemName: model.scheduledLaunchInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(model.scheduledLaunchInstalled ? Color.green : Color.orange)
                    Text(model.scheduledLaunchInstalled ? "定点启动已启用" : "定点启动未启用")
                }
            }

            Section("应用") {
                Button("退出应用") { model.confirmQuit() }
            }

            Section("调试") {
                HStack {
                    Button("+10 分钟") { model.debugAdvanceClock(by: 600) }
                    Button("重置时间") { model.resetClock() }
                }
            }

            if model.hasSettingsFeedback {
                Section {
                    SettingsFeedbackView(model: model)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct SettingsFeedbackView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            }
            if let warning = model.startupWarning {
                Text(warning).foregroundStyle(.orange)
            }
            if let warning = model.scheduledLaunchWarning {
                Text(warning).foregroundStyle(.orange)
            }
        }
    }
}
```

- [ ] **Step 2: 给 AppModel 增加 hasSettingsFeedback**

在 `Sources/Daka/AppModel.swift` 中，`@Published var scheduledLaunchInstalled = false` 这一行下面新增：

```swift
    var hasSettingsFeedback: Bool {
        errorMessage != nil || startupWarning != nil || scheduledLaunchWarning != nil
    }
```

- [ ] **Step 3: 编译验证**

Run: `make build`
Expected: `Build complete!`，无 error。

- [ ] **Step 4: 提交**

```bash
git add Sources/Daka/SettingsPages.swift Sources/Daka/AppModel.swift
git commit -m "feat: split settings into four sub-page views (v10)"
```

---

### Task 3: 侧边栏接入设置分组（统一选择状态）

**Files:**
- Modify: `Sources/Daka/AppModel.swift:18`、`:186-193`
- Modify: `Sources/Daka/ControlCenterView.swift`

- [ ] **Step 1: AppModel 用 selectedSidebar 替换 selectedTool**

在 `Sources/Daka/AppModel.swift` 把：

```swift
    @Published var selectedTool: ToolID = .punch
```

替换为：

```swift
    @Published var selectedSidebar: SidebarSelection = .tool(.punch)
```

把：

```swift
    func selectTool(_ id: ToolID) {
        selectedTool = id
    }

    func openControlCenter(selecting id: ToolID? = nil) {
        if let id { selectedTool = id }
        mainWindow?.show()
    }
```

替换为：

```swift
    func select(_ item: SidebarSelection) {
        selectedSidebar = item
    }

    func openControlCenter(selecting id: ToolID? = nil) {
        if let id { selectedSidebar = .tool(id) }
        mainWindow?.show()
    }
```

- [ ] **Step 2: ControlCenterView 侧边栏改成两段**

把 `Sources/Daka/ControlCenterView.swift` 的 `body` 中 `NavigationSplitView` 到 `.toolbar` 之前的部分改写为：

```swift
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
```

- [ ] **Step 3: 替换 selection 绑定与 detail 分发**

把原 `toolSelection` 计算属性：

```swift
    private var toolSelection: Binding<ToolID?> {
        Binding(get: { model.selectedTool },
                set: { if let value = $0 { model.selectTool(value) } })
    }
```

替换为：

```swift
    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(get: { model.selectedSidebar },
                set: { if let value = $0 { model.select(value) } })
    }
```

把原 `detail(for:)`：

```swift
    @ViewBuilder
    private func detail(for id: ToolID) -> some View {
        switch id {
        case .punch:
            PunchToolView(model: model)
        default:
            ComingSoonView(metadata: ToolCatalog.metadata(for: id))
        }
    }
```

替换为：

```swift
    @ViewBuilder
    private func detail(for selection: SidebarSelection) -> some View {
        switch selection {
        case .tool(.punch):
            PunchToolView(model: model)
        case .tool(let id):
            ComingSoonView(metadata: ToolCatalog.metadata(for: id))
        case .settings(.schedule):
            ScheduleSettingsView(model: model)
        case .settings(.workdays):
            WorkdaySettingsView(model: model)
        case .settings(.attendance):
            AttendanceSettingsView(model: model)
        case .settings(.system):
            SystemSettingsView(model: model)
        }
    }
```

- [ ] **Step 4: 编译验证**

Run: `make build`
Expected: `Build complete!`，无 error。此时 `PunchToolView` 仍引用旧 `SettingsView`（本任务未动，仍可编译）。

- [ ] **Step 5: 提交**

```bash
git add Sources/Daka/AppModel.swift Sources/Daka/ControlCenterView.swift
git commit -m "feat: add settings section to control center sidebar (v10)"
```

---

### Task 4: 打卡页去掉设置标签并加休假按钮

**Files:**
- Modify: `Sources/Daka/PunchToolView.swift`
- Delete: `Sources/Daka/SettingsView.swift`

- [ ] **Step 1: 改写 PunchToolView**

把 `Sources/Daka/PunchToolView.swift` 整个文件替换为：

```swift
import SwiftUI

struct PunchToolView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                if model.record.skipped {
                    Button("恢复打卡提醒") { model.setSkipped(false) }
                } else {
                    Button("标记今天不打卡（休假）") { model.setSkipped(true) }
                }
                Spacer()
            }
            .padding(.top, 8)

            StatisticsView(model: model)
        }
    }
}
```

即：删除 `@State private var tab`、分段 `Picker`，以及 `SettingsView` 分支；只保留顶部休假按钮 + `StatisticsView`。

- [ ] **Step 2: 删除旧 SettingsView.swift**

Run: `rm Sources/Daka/SettingsView.swift`
Expected: 无输出。

- [ ] **Step 3: 编译验证**

Run: `make build`
Expected: `Build complete!`，无 error。

- [ ] **Step 4: 确认旧引用已清除**

Run: `rg -n "SettingsView\\(model|selectedTool|selectTool" Sources/Daka`
Expected: 无输出（`SettingsFeedbackView`/`*SettingsView` 子页的新引用不含 `SettingsView(model`）。

- [ ] **Step 5: 提交**

```bash
git add Sources/Daka/PunchToolView.swift
git rm Sources/Daka/SettingsView.swift
git commit -m "feat: move leave-day action to punch page, drop old settings view (v10)"
```

---

### Task 5: 文档与手动验证清单

**Files:**
- Modify: `README.md:41`、`:46`
- Modify: `docs/verification.md`（v3 与 v7 描述行、文末追加 v10 段）

- [ ] **Step 1: 更新 README**

把 `README.md` 第 41 行：

```markdown
- 主窗口有「统计 / 设置」两个标签页；「设置」页可改上下班窗口时间与启用开关、切换「今天不打卡」、查看开机自启与定点启动状态。
```

替换为：

```markdown
- 主窗口左侧为工具列表 +「设置」分组；「设置」下分「打卡时间 / 工作日 / 考勤规则 / 系统与启动」四个子页分别配置，「打卡统计」页顶部可切换「今天不打卡」。
```

把第 46 行：

```markdown
- **需要退出时**：主窗口「设置 → 应用 → 退出应用」，二次确认后才退出。
```

替换为：

```markdown
- **需要退出时**：主窗口「设置 → 系统与启动 → 退出应用」，二次确认后才退出。
```

- [ ] **Step 2: 更新 verification.md 既有描述**

把 v3 段中的：

```markdown
- [ ] 主窗口「设置」页可改启用、工作日、4 个时间、今天不打卡，查看自启与定点状态，调试时间。
```

替换为：

```markdown
- [ ] 主窗口左侧「设置」分组含「打卡时间 / 工作日 / 考勤规则 / 系统与启动」四个子页；「打卡统计」页顶部可切换「今天不打卡」。
```

把 v5 段中的：

```markdown
- [ ] 设置页「考勤规则」可改每日最少工时（1–12 小时，步进 0.5）；改后立即生效。
```

替换为：

```markdown
- [ ] 「设置 → 考勤规则」可改每日最少工时（1–12 小时，步进 0.5）；改后立即生效。
```

把 v7 段中的：

```markdown
- [ ] 控制中心左侧列出「打卡统计 / 喝水 / 护眼 / 久坐」，右侧显示所选工具的统计与设置；打卡可切「统计 / 设置」。
```

替换为：

```markdown
- [ ] 控制中心左侧列出「打卡统计 / 喝水 / 护眼 / 久坐」及「设置」分组（打卡时间 / 工作日 / 考勤规则 / 系统与启动）。
```

- [ ] **Step 3: 追加 v10 段**

在 `docs/verification.md` 末尾追加：

```markdown
## v10：设置独立为左侧菜单

- [ ] 控制中心左侧有「设置」分组，含「打卡时间 / 工作日 / 考勤规则 / 系统与启动」四个子页，点击分别进入对应设置。
- [ ] 「打卡统计」工具页不再有「统计 / 设置」分段控件，顶部显示「标记今天不打卡（休假）」（休假后变为「恢复打卡提醒」）。
- [ ] 打卡时间页可改启用提醒与 4 个窗口时间；工作日页可多选；考勤规则页可改最少工时。
- [ ] 系统与启动页可查看自启/定点状态、退出应用（二次确认）、调试时间；错误/警告显示在该页。
- [ ] 设置修改后立即生效并持久化；重启应用后设置保留。
- [ ] 工具列表（喝水/护眼/久坐）仍显示「即将推出」，无回归。
```

- [ ] **Step 4: 编译与测试**

Run: `make build`
Expected: `Build complete!`。

Run: `make test`
Expected: 全部通过（`Executed ... tests, with 0 failures`）。

- [ ] **Step 5: 提交**

```bash
git add README.md docs/verification.md
git commit -m "docs: describe settings sidebar split (v10)"
```

---

## 验证汇总

- 自动：每个任务 `make build` 通过；最终 `make test` 全绿。
- 手动：
  - 左侧「设置」分组 4 子页可分别进入并修改设置，修改立即生效。
  - 「打卡统计」页无分段控件，顶部休假按钮可切换。
  - 系统与启动页状态与错误/警告显示正确。

## 交付

- `make install` 更新 `Daka.app`。
- 文档：`README.md`、`docs/verification.md`、本 plan、spec `docs/superpowers/specs/2026-09-15-daka-settings-sidebar-design.md`。
