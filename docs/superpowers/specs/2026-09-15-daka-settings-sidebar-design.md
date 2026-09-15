# Daka v10：设置独立为左侧菜单 设计

日期：2026-09-15
状态：已确认（待实现）
在 v9 基础上把系统设置从「打卡统计」工具页内拆出，左侧菜单新增「设置」分组，按语义分为 4 个子页分别配置；「今天不打卡」作为日常操作回归打卡页。其余行为不变。

## 1. 需求

- 左侧菜单在工具列表之外新增「设置」分组，包含 4 个子页：**打卡时间 / 工作日 / 考勤规则 / 系统与启动**。
- 系统配置不再藏在「打卡统计」工具的分段标签里；「打卡统计」工具页只做统计展示。
- 「今天不打卡（休假）」是每天可切换的状态而非配置，移到「打卡统计」页顶部。
- 分组内容：
  - 打卡时间：启用提醒开关 + 上/下班窗口起止时间。
  - 工作日：周一~周日多选。
  - 考勤规则：每日最少工时。
  - 系统与启动：开机自启、定点启动状态、退出应用、调试（+10 分钟 / 重置时间）。

## 2. 侧边栏结构（`ControlCenterView.swift`）

```
打卡统计          (工具)
喝水 / 护眼 / 久坐 (工具占位，仍 ComingSoon)
──── 设置 ────
打卡时间
工作日
考勤规则
系统与启动
```

- `List` 分为两段：一段 `ForEach(model.tools)` 渲染工具，一段 `Section("设置")` 渲染 `SettingsPage.allCases`。
- 两段共用同一个 `List(selection:)` 绑定，selection 类型为 `SidebarSelection`（见下）。
- 「设置」子页每行用 `Label(page.title, systemImage: page.symbol)`。
- 侧边栏宽度（min 170 / ideal 200 / max 260）与工具栏（`PetToolbarToggle`）保持不变。

## 3. 状态建模

新增统一选择类型与设置页枚举：

```swift
enum SettingsPage: String, CaseIterable, Identifiable {
    case schedule, workdays, attendance, system
    var id: String { rawValue }
    var title: String { ... }   // 打卡时间 / 工作日 / 考勤规则 / 系统与启动
    var symbol: String { ... }  // clock / calendar / checklist / gearshape
}

enum SidebarSelection: Hashable {
    case tool(ToolID)
    case settings(SettingsPage)
}
```

- `AppModel`：把 `@Published var selectedTool: ToolID = .punch` 替换为 `@Published var selectedSidebar: SidebarSelection = .tool(.punch)`。
- `AppModel.selectTool(_:)` 改为 `select(_ item: SidebarSelection)`，供侧边栏绑定调用。
- `openControlCenter(selecting id: ToolID? = nil)` **保持原签名不变**（内部 `selectedSidebar = .tool(id)`），`ToolPanelView` 调用点无需改动。
- 设置子页当前只从侧边栏点击进入，暂不新增以设置页为参数的 `openControlCenter` 重载；如需菜单栏直达再后续补充。
- 唯一引用 `selectedTool` 的位置是 `ControlCenterView`（第 22、45 行）与 `AppModel`（第 18、186–192 行），改动范围可控。

## 4. 设置子页视图

- 新增 `SettingsPages.swift`，从现有 `SettingsView.swift` 拆分出 4 个视图：
  - `ScheduleSettingsView`：启用提醒 `Toggle` + 4 个 `DatePicker`（沿用现有 binding 逻辑）。
  - `WorkdaySettingsView`：`weekdayOptions` + `weekdayBinding`。
  - `AttendanceSettingsView`：最少工时 `Stepper`。
  - `SystemSettingsView`：开机自启状态行、定点启动状态行、退出应用按钮、调试按钮；底部附 `SettingsFeedbackView`。
- 各页使用 `Form { ... }.formStyle(.grouped)`，与现状一致。
- 时间/星期/工时的格式化辅助（`bound`、`dateFrom`、`hhmm`、`hoursText`）抽为文件内共享 helper，避免 4 份重复。
- 旧的单一 `SettingsView.swift` 删除（其内容被拆分）。

## 5. 打卡页改动

- `PunchToolView` 去掉「统计 / 设置」分段控件。
- 页面结构改为：顶部一行「今天不打卡（休假）」切换按钮（`record.skipped` 为真时显示「恢复打卡提醒」，否则显示「标记今天不打卡（休假）」）+ 下方 `StatisticsView`。
- 休假逻辑继续复用 `model.setSkipped(_:)`，无新增状态。

## 6. 反馈显示

- 抽出 `SettingsFeedbackView(model:)`，集中显示 `errorMessage`（红）、`startupWarning`、`scheduledLaunchWarning`（橙）。
- 只挂到「系统与启动」子页底部（自启/保存相关），不在每个子页重复。

## 7. 文件改动

- 新增：`Sources/Daka/SettingsPage.swift`（`SettingsPage`、`SidebarSelection`，仿 `ToolCatalog` 风格）。
- 新增：`Sources/Daka/SettingsPages.swift`（4 个子页 + `SettingsFeedbackView`）。
- 修改：`Sources/Daka/ControlCenterView.swift`、`Sources/Daka/AppModel.swift`、`Sources/Daka/PunchToolView.swift`。
- 删除：`Sources/Daka/SettingsView.swift`。
- 不改：`ToolCatalog.swift`、`ToolPanelView.swift`（菜单栏面板不加设置入口，保持现状）、`DakaCore`。

## 8. 边界

- 选择状态单一数据源为 `selectedSidebar`，工具与设置子页互斥选中。
- 从菜单栏面板点工具仍走 `openControlCenter(selecting:)`，默认选中对应工具。
- 设置修改仍经 `AppModel.updateSettings`（写盘 + 重装定点启动 + tick），无核心逻辑改动。
- 四个设置子页共享同一持久化 `Settings`，无新建模。
- 关窗不退出、Cmd+Q 拦截等 v8/v9 行为不变。

## 9. 验证

- `make build` 成功；`make test` 全绿（无 `DakaCore` 改动，逻辑不变）。
- 手动：
  - 左侧出现「设置」分组与 4 个子页，点击分别进入对应设置；工具列表仍可正常切换。
  - 「打卡统计」页不再有分段控件，顶部有「今天不打卡」按钮且可切换状态。
  - 设置项修改后生效并持久化；重启应用后选择与设置保留（选择状态默认回到打卡统计即可）。
  - 系统与启动页能正确显示自启/定点状态、退出应用二次确认、调试按钮，以及错误/警告信息。

## 10. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 `README.md` 中「主窗口有统计 / 设置两个标签页」等描述为「左侧菜单工具 + 设置子页」。
- 本 spec、对应 plan。
