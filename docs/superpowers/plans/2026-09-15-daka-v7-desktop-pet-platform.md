# Daka v7（桌面宠物平台）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans.

**Goal:** 增加桌面宠物宿主、工具框架与控制中心，并把现有「打卡」迁成第一个工具（行为与数据不变）。

**Architecture:** `DakaCore` 放纯元数据 `ToolID`/`ToolMetadata`/`ToolCatalog`；应用层新增 `ControlCenterView`（侧栏 + 打卡详情）、`PetWindowController`/`PetView`（无边框置顶桌宠）、`PetPanelController`/`ToolPanelView`（气泡面板）。`AppModel` 增加工具选择与桌宠显隐；`AppDelegate`/`DakaApp` 装配。

**Spec:** `docs/superpowers/specs/2026-09-15-daka-v7-desktop-pet-platform-design.md`

---

## Task 1: 工具元数据（`DakaCore`，可测）

**Files:** Create `Sources/DakaCore/ToolCatalog.swift`, `Tests/DakaCoreTests/ToolCatalogTests.swift`

```swift
import Foundation

public enum ToolID: String, CaseIterable, Identifiable, Sendable {
    case punch, water, eye, sedentary
    public var id: String { rawValue }
}

public struct ToolMetadata: Equatable, Sendable {
    public let id: ToolID
    public let title: String
    public let symbol: String

    public init(id: ToolID, title: String, symbol: String) {
        self.id = id
        self.title = title
        self.symbol = symbol
    }
}

public enum ToolCatalog {
    public static let all: [ToolMetadata] = [
        ToolMetadata(id: .punch, title: "打卡统计", symbol: "checkmark.seal"),
        ToolMetadata(id: .water, title: "喝水", symbol: "drop"),
        ToolMetadata(id: .eye, title: "护眼", symbol: "eye"),
        ToolMetadata(id: .sedentary, title: "久坐", symbol: "figure.walk")
    ]

    public static func metadata(for id: ToolID) -> ToolMetadata {
        all.first { $0.id == id } ?? all[0]
    }
}
```

测试：`all.count == ToolID.allCases.count`；每个 id 都能查到且 title/symbol 非空；`.punch` 标题为「打卡统计」。

验证：`swift build && swift test`（86 + 3 = 89）。提交 `feat: tool catalog metadata`。

---

## Task 2: 控制中心窗口

**Files:** Create `Sources/Daka/ControlCenterView.swift`, `Sources/Daka/PunchToolView.swift`, `Sources/Daka/ComingSoonView.swift`; Modify `Sources/Daka/MainWindowController.swift`、`Sources/Daka/AppModel.swift`；Delete `Sources/Daka/MainWindowView.swift`

- `AppModel` 增加：
```swift
    @Published var selectedTool: ToolID = .punch
    let tools = ToolCatalog.all

    func selectTool(_ id: ToolID) { selectedTool = id }
    func openControlCenter(selecting id: ToolID? = nil) {
        if let id { selectedTool = id }
        mainWindow?.show()
    }
```

- `ControlCenterView`：`NavigationSplitView`，侧栏 `List` 工具（图标+名称+摘要；打卡摘要用 `model` 状态），detail 按 `model.selectedTool` 渲染；`.punch → PunchToolView`，其余 `ComingSoonView`。侧栏宽度 `min:170, ideal:190`。
- `PunchToolView`：内部分段 `Picker`（统计 / 设置），分别内嵌 `StatisticsView` / `SettingsView`。
- `ComingSoonView`：显示「<工具名> 即将推出」。
- `MainWindowController` 改为承载 `ControlCenterView(model:)`（窗口尺寸 860×600）。
- 删除 `MainWindowView.swift`。

验证：`swift build && swift test`（89）；不启动应用。提交 `feat: control center window with tool sidebar`。

---

## Task 3: 桌宠窗口 + 气泡面板 + 菜单栏

**Files:** Create `Sources/Daka/PetWindowController.swift`、`Sources/Daka/PetView.swift`、`Sources/Daka/ToolPanelView.swift`; Modify `Sources/Daka/AppModel.swift`、`Sources/Daka/AppDelegate.swift`、`Sources/Daka/MenuBarView.swift`

### AppModel
```swift
    @Published var petVisible: Bool
    weak var petWindow: PetWindowController?

    func setPetVisible(_ visible: Bool) {
        petVisible = visible
        UserDefaults.standard.set(visible, forKey: "pet.visible")
        if visible { petWindow?.show() } else { petWindow?.hide() }
    }
```
init 里：`self.petVisible = UserDefaults.standard.object(forKey: "pet.visible") as? Bool ?? true`。

### `PetWindowController`（`@MainActor`）
- 懒创建 130×130 无边框透明 `NSWindow`：`isOpaque=false`、`backgroundColor=.clear`、`hasShadow=false`、`level=.floating`、`collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]`、`isMovableByWindowBackground=true`、`isReleasedWhenClosed=false`、`contentView = NSHostingView(PetView(model:onOpenPanel:))`。
- 位置：从 `UserDefaults` key `pet.frame`（`NSStringFromRect`）恢复；无或越界 → 主屏 `visibleFrame` 右下角。移动时（`NSWindow.didMoveNotification`）保存 frame。
- `show()`/`hide()`/`toggle()`。
- 气泡：`NSPopover`（`behavior=.transient`）内容 `ToolPanelView(model:)`，锚定桌宠视图；`togglePanel()`。
- 右键菜单用 SwiftUI `.contextMenu` 实现（显示控制中心 / 显示·隐藏桌宠 / 退出）。

### `PetView`
- 自绘轻量角色：圆角渐变身体 + 两只眼睛 + 微笑；`TimelineView`/`withAnimation` 做呼吸缩放与眨眼。
- 右上角状态徽标：`hard → exclamationmark.triangle.fill`、`gentle → bell.badge.fill`、否则 `checkmark.circle.fill`。
- `.onTapGesture { onOpenPanel() }`；`.contextMenu { ... }`。

### `ToolPanelView`
- 今日概览（打卡上班/下班状态；喝水/久坐「即将推出」）。
- 工具入口列表（点击 `model.openControlCenter(selecting: tool.id)`）。
- 快捷操作：`PunchButton(task: PunchTarget.resolve(record: model.record, now: model.now, minWorkDuration: model.minWorkDuration)) { model.punch($0) }` +「打开控制中心」+「退出」（hard 时禁用）。宽度 260。

### AppDelegate / MenuBarView
- `AppDelegate` 创建并持有 `PetWindowController`，赋给 `model.petWindow`；`petVisible` 时 `show()`。
- `MenuBarView`：把「显示」改成「显示控制中心」（`model.openControlCenter()`），新增「显示桌宠」切换（`model.setPetVisible(!model.petVisible)`）。

验证：`swift build && swift test`（89）；不启动应用。提交 `feat: desktop pet window, bubble panel, and menu bar entries`。

---

## Task 4: 文档与安装

- `docs/verification.md` 增加 v7 条目：桌宠显示/隐藏、拖动与位置记忆、左键气泡、右键菜单、快捷长按打卡、控制中心侧栏、打卡详情「统计/设置」、菜单栏新增项；强调打卡行为无回归。
- `make install`。

提交 `docs: verify desktop pet platform`。

---

## 完成标准

- `swift test` 全绿（≥89）。
- 桌宠可显示/隐藏、拖动、位置记忆；左键气泡面板可用；右键菜单可用。
- 控制中心侧栏包含打卡（统计/设置）与三个占位工具。
- 菜单栏保留打卡面板并新增「显示桌宠 / 显示控制中心」。
- 打卡全部既有行为与数据不变。
