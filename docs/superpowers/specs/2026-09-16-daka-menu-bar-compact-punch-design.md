# Daka：菜单栏弹窗紧凑化 + 圆环显示打卡时间 设计

日期：2026-09-16
状态：已确认（待实现）

## 1. 目标

菜单栏下拉面板（`MenuBarView`）去掉行内的排班时间文字，让内容更紧凑；把「已打卡时间」移进大圆环中心，与「已工作时长」上下两行显示。长按打卡的交互不变。

## 2. 现状

`Sources/Daka/MenuBarView.swift`：

- 弹窗宽度 `220`。
- 两行状态（`上班打卡` / `下班打卡`）由 `statusRow` 渲染，会显示时间：
  - 已打卡：显示实际打卡时间（`09:05`）。
  - 未打卡：`待打卡 09:00–09:30` / `窗口内 …` / `已过截止 …`。
  - 不提醒：`今日不提醒`。
- 底部复用 `PunchButton`，说明文字为 `长按 3 秒打卡（可重复）`。

`Sources/Daka/PunchButton.swift`：

- 大圆环中心空闲态显示「已工作时长」`WorkProgress.hoursText`（未打上班卡时显示任务标题）；按压态显示任务标题。
- `PunchButton` 被 `MenuBarView`（菜单栏弹窗）与 `ToolPanelView`（桌宠气泡面板）复用。

## 3. 新布局

弹窗宽度 `220 → 200`，行内不再有任何时间，圆环中心两行：

```
今日打卡                    ⧉
✓ 上班打卡
○ 下班打卡   待打卡
        ╭─────────╮
        │  09:05  │   ← 上班打卡时间
        │  6.5h   │   ← 已工作时长
        ╰─────────╯
     长按 3 秒打卡
```

## 4. 行文案（去时间，保留状态词）

`statusRow` 不再拼接任何 `HH:mm` 或窗口区间，只保留状态词与次数后缀：

| 状态 | 文案 |
|---|---|
| 已完成 | `已完成`（多次追加 `（N 次）`） |
| 未打卡 | `待打卡` |
| 提醒中、已过截止 | `已过截止` |
| 提醒中、窗口内 | `窗口内` |
| 未启用 / 休假 / 非工作日 | `今日不提醒` |

说明：`statusRow` 仍需要 `deadline` 判断是否已过截止（比较用），但不再把 `start`/`deadline` 显示出来。

## 5. 圆环中心

空闲态两行，均用环色：

- 第 1 行（上班打卡时间）：当天最早上班卡 `record.morningDoneAt` 的 `HH:mm`；未打上班卡时显示任务标题（`PunchTask.title`）。
- 第 2 行（工作时长）：`WorkProgress.hoursText(elapsed)`；未打上班卡（`elapsed == nil`）时不显示。

按压态：仍显示「3 秒按压进度 + 任务标题」单行，不变。

字号：打卡时间 `15pt semibold`，工作时长 `12pt`（`monospacedDigit`）。

## 6. 应用层改动

- `Sources/Daka/MenuBarView.swift`（改）：
  - 弹窗宽度 `220 → 200`；状态文字加 `.lineLimit(1).minimumScaleFactor(0.85)`，常见（个位数）`（N 次）` 后缀不被截断（当天打卡 10 次以上为极端情况，允许省略号）。
  - `statusRow` 去掉时间拼接，文案按 §4。
- `Sources/Daka/PunchButton.swift`（改）：
  - 说明文字 `长按 3 秒打卡（可重复）` → `长按 3 秒打卡`。
  - 圆心由单行 `Text` 改为两行 `VStack`，内容按 §5。
  - 上行取 `record.morningDoneAt` 作为上班打卡时间，不新增 Core API。
- `ToolPanelView` 通过共享 `PunchButton` 自动获得同样的圆环中心行为（弹窗宽度不变，保持 `260`）。

## 7. 核心类型与 API

不新增 `DakaCore` API。上行打卡时间复用已有的 `DayRecord.morningDoneAt`（`Sources/DakaCore/Models.swift`，当天最早上班卡）；下行复用已有 `WorkProgress.hoursText`。

> 修订（2026-09-16）：初版曾新增 `PunchRules.latestPunch(record:task:)` 取「当前目标任务」的最近打卡，但 `PunchTarget.resolve` 在上班后即切到下班、而下班未打卡时返回 nil，会导致白天圆心看不到 `09:05`。改为固定取上班打卡时间，`latestPunch` 已移除。

## 8. 测试

不新增单元测试：上行复用 `record.morningDoneAt`、下行复用已有 `WorkProgress`，逻辑为直接属性/已有函数调用。UI 行为（行文案、圆心两行、按压切换）手动验证，见 `docs/verification.md` v16。

## 9. 多屏与菜单栏容量（说明，不在本次范围）

状态栏项（`NSStatusItem` / `MenuBarExtra`）由系统统管，App **无法指定显示在哪块屏**；系统会把项渲染到每块屏的菜单栏。多屏实测：系统项同时出现在内建屏与外接屏的菜单栏；但内建屏菜单栏过满时，Daka 项会被挤到刘海区（窗口 `onscreen=false`），表现为「看不到」。

这属于系统菜单栏容量问题，非 App 代码可解；本次不改。可选缓解：退出部分菜单栏 App / 使用菜单栏收纳工具。

## 10. 交付

- 更新后的 `Daka.app`（`make install`）。
- 更新 spec、plan、`docs/verification.md`。
