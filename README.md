# Daka

一个常驻 macOS 菜单栏的本地打卡提醒应用，在工作日提醒你完成 **上班 / 下班** 两次打卡。

打卡记录**纯本地保存**：不连接任何公司考勤系统、不访问网络、不打开网页、不执行外部脚本。

## 功能特性

- **时间窗口 + 两级提醒**：进入打卡窗口先「温和提醒」（系统通知 + 菜单栏铃铛图标）；到达截止仍未打卡则升级为「强制提醒」（每屏全屏遮罩，每 2 分钟重弹置顶）。
- **默认时间**：上班窗口 09:00–09:30，下班窗口 18:00–18:30（可在菜单栏修改）。
- **工作日判断**：默认周一至周五，可多选；非工作日不提醒。
- **今天不打卡（休假）**：一键跳过当天，跨天自动恢复。
- **开机自启**：登录时若当天上班未打卡，会立即催打卡。
- **定点拉起**：通过 `launchd` 在四个打卡时点自动拉起已在后台退出的应用（单实例）。
- **系统事件响应**：休眠唤醒、系统时间/时区变更后立即重算提醒。
- **数据容错**：写盘原子替换；JSON 损坏时自动备份并重建，菜单栏可见错误。
- **打卡统计（核心逻辑）**：连续天数、平均上班时长、缺卡等已在 `DakaCore` 实现，UI 尚在计划中。

## 系统要求

- macOS 14 (Sonoma) 或更高版本
- Swift 5.10+（随 Xcode 15.3+ / Command Line Tools 提供）

## 构建与安装

```sh
make build     # 仅编译（release）
make test      # 运行单元测试
make icon      # 由 Resources/AppIcon.iconset 生成 Daka.icns
make app       # 编译 + 组装并 ad-hoc 签名 build/Daka.app
make install   # 在 app 基础上安装到 /Applications/Daka.app
make clean     # 清理 .build 与 build
```

首次运行若需重新生成图标，先执行 `make icon`；`make app` / `make install` 依赖 `Resources/Daka.icns` 已存在。

## 使用说明

启动后应用仅出现在菜单栏（无 Dock 图标）：

- 菜单栏图标反映当前状态：`checkmark.seal` 正常 / `bell.badge` 窗口内待打卡 / `exclamationmark.triangle.fill` 已过截止。
- 点击图标可手动「上班打卡 / 下班打卡」补卡，设置上下班窗口时间与启用开关，切换「今天不打卡」，查看开机自启与定点启动状态。
- **强制提醒阶段**：全屏遮罩无法用 ESC、Cmd+W、Cmd+M、Cmd+H 关闭，菜单「退出 Daka」置灰、Cmd+Q 无效；完成对应打卡后自动消失。
- 温和阶段可正常退出应用。

## 数据存储

记录保存在：

```
~/Library/Application Support/Daka/data.json
```

结构大致为：

```jsonc
{
  "settings": {
    "enabled": true,
    "workdays": [2, 3, 4, 5, 6],          // 2=周一 … 6=周五
    "morningWindowStart": "09:00",
    "morningDeadline": "09:30",
    "eveningWindowStart": "18:00",
    "eveningDeadline": "18:30",
    "reminderIntervalSeconds": 120
  },
  "records": {
    "2026-09-14": {
      "morningDone": true,
      "morningDoneAt": "2026-09-14T09:01:12+08:00",
      "eveningDone": false,
      "eveningDoneAt": null,
      "skipped": false
    }
  }
}
```

`records` 以 `yyyy-MM-dd` 为键保留全部历史。文件损坏时会重命名为 `data.json.corrupt-<时间戳>-*` 备份，并重建空存储。

## 项目结构

```
Sources/
  DakaCore/        # 纯逻辑，无 UI/IO 依赖，可单测
    Models.swift          数据模型（Settings / DayRecord）
    ScheduleEvaluator.swift 纯函数：计算待办与提醒等级
    Scheduler.swift       定时 tick，驱动提醒
    PunchStore.swift      持久化（原子写、损坏恢复）
    DakaClock.swift       可注入时钟
    Statistics.swift      统计口径
    LaunchAgentPlist.swift 定点拉起 plist 生成
  Daka/            # AppKit + SwiftUI 应用层
    AppDelegate.swift / DakaApp.swift
    AppModel.swift / MenuBarView.swift
    ReminderController.swift / OverlayView.swift
    GentleNotifier.swift / LoginItemManager.swift / ScheduledLaunchManager.swift
Tests/DakaCoreTests/   # 单元测试
Resources/             # Info.plist、图标
scripts/               # 图标生成脚本
docs/                  # 设计文档、实现计划、验证清单
```

## 测试

```sh
make test
# 或
swift test
```

测试覆盖 `ScheduleEvaluator`（时间窗口/两级提醒/工作日/休假/开机强制）、`PunchStore`（往返、损坏恢复、跨天）、`Statistics` 等核心逻辑，均使用注入时钟，不依赖真实时间。

## 已知限制

- macOS 不允许普通应用完全锁死系统：**强制退出（Cmd+Opt+Esc / `kill -9`）无法被屏蔽**。「无法绕过」指置顶全屏、屏蔽 ESC/关闭/Cmd+Q、每 2 分钟重弹。
- 不做节假日日历，仅按星期判断，提供手动「今天不打卡」。
- 定点拉起依赖 `launchd`，需要用户已登录且系统已唤醒。

## 设计文档

- `docs/superpowers/specs/` — 设计规格（打卡规则、排期 v2、应用窗口与统计 v3）
- `docs/superpowers/plans/` — 实现计划
- `docs/verification.md` — 手动验证清单
