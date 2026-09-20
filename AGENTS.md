# Agent Instructions

## 重启要求

每次修改代码后，必须重启应用以验证改动：

```bash
# 1. 编译
make build

# 2. 先关闭正在运行的 Daka（如果有的话）
killall Daka 2>/dev/null || true

# 3. 重新启动
open build/Daka.app
```

不要只编译不重启。每次改动都要执行完整流程，确保改动生效。

## 构建与测试

- `swift test` — 运行单元测试（修改后必须通过）
- `make build` — 编译 release 版本
- `make app` — 编译 + 组装 app bundle

## 代码规范

- 使用 Swift 原生风格，遵循 Swift API Design Guidelines
- 优先使用 SwiftUI 构建 UI
- 核心逻辑放在 `Sources/DakaCore/`，保持无 UI/IO 依赖，便于测试
- 修改 `DakaCore` 后必须运行 `swift test` 确认无回归
