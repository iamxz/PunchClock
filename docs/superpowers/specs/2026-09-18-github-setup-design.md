# GitHub 完整配置设计文档

**日期**: 2026-09-18  
**项目**: Daka (macOS 打卡提醒应用)  
**状态**: 已批准

## 概述

为 Daka 项目创建完整的 GitHub 配置，包括许可证、文档、CI/CD 工作流、发布系统和社区模板。

## 决策记录

| 决策项 | 选择 | 理由 |
|--------|------|------|
| 许可证类型 | MIT | 宽松、简单，允许任何人使用、修改和分发 |
| 代码签名 | 无签名/公证 | 无 Apple 开发者账号，使用 ad-hoc 签名 |
| 发布触发 | 标签触发 + 手动触发 | 灵活性高，支持自动化和手动控制 |
| 发布内容 | .app + .pkg | Universal binary 适配所有 Mac，pkg 方便安装 |

## 文件清单

### 1. 许可证文件

**文件**: `LICENSE`  
**内容**: MIT 许可证，版权年份 2026，版权所有者 xue

### 2. 社区文档

**文件**: `CONTRIBUTING.md`  
**内容**:
- 报告 Bug 的流程（使用 Issue 模板）
- 提交功能建议的流程
- Pull Request 规范（分支命名、提交信息、测试要求）
- 开发环境搭建指南（克隆、构建、测试命令）

### 3. GitHub Actions 工作流

#### 3.1 持续集成

**文件**: `.github/workflows/ci.yml`  
**触发条件**:
- push 到 main 分支
- Pull Request 到 main 分支

**工作流**:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: make build
      - name: Test
        run: make test
```

#### 3.2 自动发布

**文件**: `.github/workflows/release.yml`  
**触发条件**:
- 推送版本标签 (v*.*.*)
- 手动触发 (workflow_dispatch)

**工作流**:
```yaml
name: Release

on:
  push:
    tags:
      - 'v*.*.*'
  workflow_dispatch:
    inputs:
      tag:
        description: 'Version tag (e.g., v1.0.0)'
        required: true

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build Universal Binary
        run: make pkg
      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          files: build/Daka-*.pkg
          generate_release_notes: true
```

### 4. 发布配置

**文件**: `.github/release.yml`  
**用途**: 配置自动发布说明的分类和排除规则

```yaml
changelog:
  categories:
    - title: ✨ 新功能
      labels:
        - enhancement
    - title: 🐛 Bug 修复
      labels:
        - bug
    - title: 📝 文档
      labels:
        - documentation
    - title: 🔧 其他更改
      labels:
        - '*'
```

### 5. Issue 模板

#### 5.1 Bug 报告模板

**文件**: `.github/ISSUE_TEMPLATE/bug_report.md`

```markdown
---
name: Bug 报告
about: 报告一个问题
title: '[Bug] '
labels: bug
assignees: ''
---

**描述问题**
清晰简洁地描述问题。

**复现步骤**
1. 打开应用
2. 点击 '...'
3. 看到错误

**期望行为**
描述期望的行为。

**实际行为**
描述实际的行为。

**环境信息**
- macOS 版本: [例如 14.0]
- 应用版本: [例如 1.0.0]

**截图**
如果适用，添加截图帮助解释问题。

**其他信息**
添加任何其他关于问题的信息。
```

#### 5.2 功能建议模板

**文件**: `.github/ISSUE_TEMPLATE/feature_request.md`

```markdown
---
name: 功能建议
about: 建议一个新功能
title: '[Feature] '
labels: enhancement
assignees: ''
---

**描述功能**
清晰简洁地描述您希望的功能。

**使用场景**
描述这个功能解决的问题或改善的体验。

**期望行为**
描述您期望的功能行为。

**其他信息**
添加任何其他关于功能请求的信息。
```

### 6. Pull Request 模板

**文件**: `.github/PULL_REQUEST_TEMPLATE.md`

```markdown
## 变更类型
- [ ] Bug 修复
- [ ] 新功能
- [ ] 文档更新
- [ ] 代码重构
- [ ] 其他

## 变更描述
简洁地描述这个 PR 做了什么。

## 相关 Issue
- Closes #(issue number)

## 测试
- [ ] 已运行 `make test`
- [ ] 已手动测试

## 截图（如适用）
添加截图说明变更。

## 检查清单
- [ ] 代码遵循项目规范
- [ ] 已添加必要的文档
- [ ] 已添加/更新测试
- [ ] 测试全部通过
```

### 7. README 改进

**文件**: `README.md`  
**改进内容**:

1. 在顶部添加徽章:
```markdown
[![CI](https://github.com/xue/daka/actions/workflows/ci.yml/badge.svg)](https://github.com/xue/daka/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/xue/daka)](https://github.com/xue/daka/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
```

2. 在"分发安装包"部分添加 GitHub Releases 下载链接

3. 添加"参与贡献"部分，链接到 CONTRIBUTING.md

## 实现顺序

1. LICENSE
2. CONTRIBUTING.md
3. .github/workflows/ci.yml
4. .github/workflows/release.yml
5. .github/release.yml
6. .github/ISSUE_TEMPLATE/bug_report.md
7. .github/ISSUE_TEMPLATE/feature_request.md
8. .github/PULL_REQUEST_TEMPLATE.md
9. README.md 改进

## 验证

实现完成后验证:
1. 检查所有文件是否存在且格式正确
2. 验证 YAML 语法是否正确
3. 确认 README 徽章链接正确
4. 测试 CI 工作流是否能触发
