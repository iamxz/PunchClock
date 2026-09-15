# Daka v7：桌面宠物宿主 + 工具框架 + 打卡迁移 设计

日期：2026-09-15
状态：已确认（待实现）
本设计把 Daka 从「打卡单功能应用」重构为「桌面宠物 + 可插拔办公小工具」的宿主平台；打卡作为第一个工具迁入（行为不变）。

## 1. 产品结构

- **宿主/框架**：桌宠窗口、工具注册、统一控制中心、统一存储目录、统一提醒通道。
- **工具**：打卡统计（v7 迁入）、喝水（v8）、护眼（v9）、久坐（v10）。
- **形态**：常规应用（Dock 图标 + 菜单栏图标 + 漂浮桌宠 + 控制中心窗口）。

## 2. 子项目

| 版本 | 内容 |
|---|---|
| v7 | 桌宠 + 工具框架 + 控制中心 + 打卡迁移 |
| v8 | 喝水工具（气泡/通知提醒 + 统计） |
| v9 | 护眼工具（20-20-20） |
| v10 | 久坐工具 |

## 3. v7 范围

1. 桌宠窗口（轻量角色 + 动画 + 拖动 + 位置记忆 + 显隐）。
2. 桌宠气泡面板（今日概览 + 工具入口 + 快捷打卡）。
3. 工具框架（工具标识/元数据/注册）。
4. 控制中心窗口（左侧工具列表 + 右侧工具内容）；打卡工具并入；其余工具占位。
5. 菜单栏保留打卡快捷面板，新增「显示桌宠 / 显示控制中心」。

**不在 v7**：喝水/护眼/久坐的具体功能与提醒（v8–v10）；通用提醒引擎（v8 引入时再抽）。

## 4. 桌宠

- **窗口**：无边框透明 `NSWindow`；`level = .floating`；`collectionBehavior` 含 `.canJoinAllSpaces`；`isMovableByWindowBackground = true`（可拖动）；`hasShadow = false`；`isOpaque = false`；`backgroundColor = .clear`；不占 Dock/菜单栏。
- **位置记忆**：把窗口 frame 存 `UserDefaults`（key `pet.frame`），启动恢复（越界则回到右下角默认位置）。
- **角色**：纯 SwiftUI 自绘的轻量角色（圆角身体 + 眼睛 + 一个状态徽标），~120×120；呼吸缩放与眨眼用 `TimelineView`/`withAnimation` 做轻动画。
- **状态徽标**：根据打卡状态显示（已打勾 / 铃铛温和 / 警示强制），复用 `AppModel.reminderState`。
- **交互**：
  - 左键单击 → 打开气泡面板（`NSPopover`，锚定桌宠）。
  - 右键 → 菜单：显示控制中心 / 隐藏桌宠 / 退出。
  - 拖动 → 移动并保存位置。
- **显隐**：菜单栏与右键菜单可切换；状态存 `UserDefaults`（key `pet.visible`）。

## 5. 工具框架

```swift
public enum ToolID: String, CaseIterable, Identifiable {
    case punch        // 打卡
    case water        // 喝水
    case eye          // 护眼
    case sedentary    // 久坐
    public var id: String { rawValue }
}

public struct ToolMetadata {
    public let id: ToolID
    public let title: String
    public let symbol: String
}
```

- `ToolCatalog.metadata(for:)` 提供名称/图标（打卡：`checkmark.seal`；喝水：`drop`；护眼：`eye`；久坐：`figure.walk`）。
- 工具数据各自独立文件，放 `~/Library/Application Support/Daka/`：
  - 打卡沿用现有 `data.json`（不迁移、不丢数据）。
  - 后续工具各自 `<tool>.json`。
- 工具的「今日摘要」由各工具提供；v7 仅打卡有摘要（如「上班已完成 · 下班待打卡」），其余显示「即将推出」。

## 6. 控制中心窗口

- 复用 v3 的主窗口控制器（改为承载 `ControlCenterView`），标题「Daka」。
- `NavigationSplitView`：左侧 `List` 工具（图标 + 名称 + 今日摘要）；右侧选中工具的详情。
- 打卡详情：内部分段（`Picker`）切换「统计 / 设置」，直接内嵌现有 `StatisticsView` 与 `SettingsView`（行为、数据不变）。
- 其余工具详情：占位文案「该工具即将推出」。

## 7. 桌宠气泡面板

`NSPopover` 内容 `ToolPanelView`：
- 顶部：今日概览——打卡状态（上班/下班）+ 后续工具占位进度。
- 中部：工具入口列表（点击 → 打开控制中心并切到该工具）。
- 底部：快捷操作——复用 `PunchButton`（长按 3 秒打卡，目标项用 `PunchTarget.resolve`）+「打开控制中心」+「退出」。

## 8. 菜单栏

保留现有打卡快捷面板（状态 + 圆形打卡按钮 + 显示 + 退出），新增：
- 「显示桌宠」（切换桌宠显隐）
- 「显示控制中心」（等价于原「显示」）

## 9. 兼容与不变项

- 打卡：窗口时间、温和/强制两级、重复打卡、最少工时、休假跳过、定点启动、开机自启、单实例、统计口径**全部不变**。
- 数据：打卡仍用 `data.json`；设置读写路径不变。
- 主窗口从「统计/设置 两标签」改为「控制中心侧栏 + 打卡详情（统计/设置 分段）」。

## 10. 组件与职责

| 组件 | 职责 |
|---|---|
| `ToolID` / `ToolMetadata` / `ToolCatalog` | 工具标识与元数据 |
| `PetWindowController` | 桌宠窗口生命周期、拖动、位置/显隐持久化 |
| `PetView` | 角色绘制 + 动画 + 状态徽标 + 点击/右键 |
| `PetPanelController` / `ToolPanelView` | 气泡面板（概览 + 入口 + 快捷操作） |
| `ControlCenterWindowController` / `ControlCenterView` | 控制中心窗口与侧栏 |
| `AppModel` | 维持现有职责；新增 `tools` 元数据、`showPet/hidePet`、`openControlCenter(selecting:)` |
| `DakaApp` / `AppDelegate` | 注册 `MenuBarExtra`、创建桌宠与控制中心、激活策略 |

## 11. 测试

- 核心逻辑沿用现有 86 个测试（打卡行为不变，全部保持通过）。
- v7 新增为 UI，主要靠手动验证：
  - 桌宠显示/隐藏、拖动与位置记忆（重启后位置保留）。
  - 左键气泡面板、右键菜单、快捷打卡（长按 3 秒）。
  - 控制中心侧栏切换工具；打卡「统计/设置」分段可用。
  - 菜单栏新增项可用；打卡原有行为不回归。

## 12. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`docs/verification.md`。
