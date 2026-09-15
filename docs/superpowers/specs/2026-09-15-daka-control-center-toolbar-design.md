# Daka v9：控制中心入口与桌宠工具栏开关 设计

日期：2026-09-15
状态：已确认（待实现）
在 v8（禁止随便退出 / 后台常驻）基础上调整两处 UI 位置；其余行为不变。

## 1. 需求

- 菜单栏面板里的「控制中心」入口移到面板**右上角**，改用 **icon**（`switch.2`）。
- 菜单栏面板里的「桌宠」显示/隐藏开关**移除**，改放到**控制中心窗口右上角工具栏**。
- 桌宠右键菜单里的「显示/隐藏桌宠」保留；气泡工具面板里的「控制中心」按钮保留。

## 2. 菜单栏面板（`MenuBarView.swift`）

- 标题行改为：`HStack { Text("今日打卡").font(.headline); Spacer(); 控制中心图标按钮 }`。
- 控制中心按钮：`Image(systemName: "switch.2")`，`.imageScale(.large)` + `.padding(4)` + `.contentShape(Rectangle())`，action `model.openControlCenter()`，`.buttonStyle(.borderless)`，`.help("打开控制中心")`，`.accessibilityLabel("控制中心")`（图标较小，用 borderless 提供悬停反馈并扩大点击区域）。
- 删除底部的 `Divider()`、文字「控制中心」按钮、以及「显示桌宠 / 隐藏桌宠」按钮。
- 面板剩余内容：标题行（左标题 + 右控制中心图标）、两个状态行、打卡按钮。

## 3. 控制中心（`ControlCenterView.swift` + `MainWindowController.swift`）

- `MainWindowController.show()`：用 `NSHostingController(rootView: ControlCenterView(model: model))` 作为窗口的 `contentViewController`，替换现在的 `NSHostingView` + `contentView =`，使 SwiftUI `.toolbar` 能安装到窗口标题栏。窗口标题、尺寸、`isReleasedWhenClosed`、`setFrameAutosaveName`、`center()` 保持不变。
- `ControlCenterView` 增加 `.toolbar { ToolbarItem(placement: .primaryAction) { PetToolbarToggle(model: model) } }`。
- `PetToolbarToggle`（SwiftUI 视图，可放在 `ControlCenterView.swift` 内）：
  - `@ObservedObject var model: AppModel`
  - `Button { model.setPetVisible(!model.petVisible) }` 标签为 `Image(systemName: model.petVisible ? "pawprint.fill" : "pawprint")`
  - `.help(model.petVisible ? "隐藏桌宠" : "显示桌宠")`
- **回退**：若实测 SwiftUI `.toolbar` 未出现在窗口标题栏，则在 `MainWindowController` 显式配置 `NSToolbar`，用一个 `NSToolbarItem`（`item.view = NSHostingView(rootView: PetToolbarToggle(model: model))`）承载同一 SwiftUI 开关。

## 4. 边界

- 桌宠可见性仍以 `AppModel.petVisible` + `UserDefaults("pet.visible")` 为准，切换逻辑复用 `setPetVisible(_:)`，无新增状态。
- 控制中心窗口关闭再打开时，工具栏开关状态随 `model.petVisible` 自动同步（`@ObservedObject`）。
- 菜单栏面板不再提供桌宠开关；隐藏桌宠后仍可通过桌宠右键菜单（若仍可见）或控制中心工具栏恢复。
- 若桌宠被隐藏且用户想再显示，唯一入口是控制中心工具栏（菜单栏入口已移除）——符合本次需求。

## 5. 验证

- `make build` 成功；`make test` 全绿（无 DakaCore 改动）。
- 手动：
  - 菜单栏面板右上角出现 `switch.2` 图标，点击打开控制中心；面板中无桌宠开关、无底部「控制中心」文字按钮。
  - 控制中心窗口右上角出现桌宠图标，点击可显示/隐藏桌宠；图标随可见性变化。
  - 桌宠右键「显示/隐藏桌宠」仍可用。

## 6. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 `README.md`、`docs/verification.md` 中「菜单栏面板只含…」的描述（去掉桌宠开关）。
- 本 spec、对应 plan。
