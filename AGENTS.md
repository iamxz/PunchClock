# Agent Instructions

## 重启要求

每次修改代码后，必须重启应用以验证改动：

```bash
# 1. 编译
make build

# 2. 先关闭正在运行的 Daka（如果有的话）
killall Daka 2>/dev/null || true

# 3. 重新启动
open build/小打卡.app
```

不要只编译不重启。每次改动都要执行完整流程，确保改动生效。

## 构建与测试

- `swift test` — 运行单元测试（修改后必须通过）
- `make build` — 编译 release 版本
- `make app` — 编译 + 组装 app bundle（**仅本地开发自测用，不要作为发布产物**）

## 发布与打包（交给 GitHub CI）

- **打包发布必须由 GitHub Actions 完成，不要自己本地打包出 release 产物**（不要依赖本地 `make app`/`make install` 的产物作为对外发布版本）。
- 发版用脚本，一步完成：`make release VERSION=<x.y.z|patch|minor|major> [MSG="提交信息"] [NOTES="更新说明"]`（即 `scripts/release.sh`）。它会依次做：前置校验（main 分支、不落后远端、tag 不重复）→ 准备更新说明 → `swift test` → 改 `Resources/Info.plist` 双版本号 → 校验与 tag 一致 → commit（工作区未提交改动会一并提交）→ `git tag vX.Y.Z` → push main + tag。
- 推送 tag 后，CI（`.github/workflows/release.yml`）会自动构建 `.pkg` / `.app.zip` / `checksums.txt` 并发布到 GitHub Release。

### 更新说明（GitHub Release 正文）

- 正文来自仓库内的 `docs/release-notes/vX.Y.Z.md`（**每个版本一份**，会随发版提交进 main），GitHub 自动生成说明（`generate_release_notes`）已关闭，不要再依赖它。
- **发版前先把这份文件写好**（用面向用户的中文，顶部 `## 更新内容` + bullet，写"用户能感知到什么"，不要写构建/内部细节）。脚本遇到已存在的文件不会覆盖。
- 忘了写也不会发版失败：脚本会按上一个 tag 到 HEAD 的提交记录起草一份并提示，但那是占位草稿，**必须改写后再发**。
- CI 拼正文时只读 `main` 上的 `docs/release-notes/`：先取本版本的说明，再接共用的 `_footer.md`（安装步骤与 Gatekeeper 放行说明）和 `Full Changelog` 比较链接。改发布文案时只改这份 footer。
- 已发布版本的说明可以事后在 main 上补写/修正，然后用 workflow 的 `workflow_dispatch` 指定 tag 重新发布（该步骤会先删掉旧 Release 再重建），不必动 tag。
- push 失败时本地 commit/tag 已生成，按脚本提示手动重试即可（幂等）。**不要**手动 `make install` 到 `/Applications` 当作发布，也不要把本地 `build/小打卡.app` 当发布包分发。
- 本地 `make app`/`open build/小打卡.app` 仅用于开发期验证功能（如验证升级提醒逻辑），验证完即可，不代表完成发版。

## 代码规范

- 使用 Swift 原生风格，遵循 Swift API Design Guidelines
- 优先使用 SwiftUI 构建 UI
- 核心逻辑放在 `Sources/DakaCore/`，保持无 UI/IO 依赖，便于测试
- 修改 `DakaCore` 后必须运行 `swift test` 确认无回归
