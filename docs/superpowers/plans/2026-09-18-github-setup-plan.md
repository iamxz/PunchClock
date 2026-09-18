# GitHub 完整配置实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 Daka 项目创建完整的 GitHub 配置，包括许可证、文档、CI/CD 工作流、发布系统和社区模板

**Architecture:** 创建独立的文件，每个文件负责一个特定功能（许可证、CI、发布、模板等）。工作流使用 GitHub Actions，发布系统使用 softprops/action-gh-release。

**Tech Stack:** GitHub Actions, YAML, Markdown, softprops/action-gh-release@v2

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `LICENSE` | MIT 许可证文件 |
| `CONTRIBUTING.md` | 贡献者指南 |
| `.github/workflows/ci.yml` | 持续集成工作流 |
| `.github/workflows/release.yml` | 自动发布工作流 |
| `.github/release.yml` | 自动发布说明配置 |
| `.github/ISSUE_TEMPLATE/bug_report.md` | Bug 报告模板 |
| `.github/ISSUE_TEMPLATE/feature_request.md` | 功能建议模板 |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR 模板 |
| `README.md` | 改进的 README（添加徽章和下载链接） |

---

### Task 1: 创建 LICENSE 文件

**Files:**
- Create: `LICENSE`

- [ ] **Step 1: 创建 LICENSE 文件**

```bash
cat > LICENSE << 'EOF'
MIT License

Copyright (c) 2026 xue

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
EOF
```

- [ ] **Step 2: 验证文件已创建**

Run: `ls -la LICENSE`
Expected: `-rw-r--r--  1 user  staff  ... LICENSE`

- [ ] **Step 3: 提交**

```bash
git add LICENSE
git commit -m "docs: add MIT license"
```

---

### Task 2: 创建 CONTRIBUTING.md

**Files:**
- Create: `CONTRIBUTING.md`

- [ ] **Step 1: 创建 CONTRIBUTING.md 文件**

```bash
cat > CONTRIBUTING.md << 'EOF'
# 贡献指南

感谢您对 Daka 项目的关注！我们欢迎各种形式的贡献。

## 报告 Bug

如果您发现了 Bug，请通过 [GitHub Issues](https://github.com/xue/daka/issues) 报告，并使用 Bug 报告模板。

请包含以下信息：
- 清晰的问题描述
- 复现步骤
- 期望行为与实际行为
- 环境信息（macOS 版本、应用版本）
- 截图（如适用）

## 提交功能建议

我们欢迎新功能建议！请通过 [GitHub Issues](https://github.com/xue/daka/issues) 提交，并使用功能建议模板。

## Pull Request

### 开发环境搭建

1. Fork 并克隆仓库
   ```bash
   git clone https://github.com/your-username/daka.git
   cd daka
   ```

2. 构建项目
   ```bash
   make build
   ```

3. 运行测试
   ```bash
   make test
   ```

### 提交规范

- 使用清晰的提交信息
- 每个 PR 应专注于一个功能或修复
- 确保所有测试通过

### 分支命名

- `feature/xxx` - 新功能
- `fix/xxx` - Bug 修复
- `docs/xxx` - 文档更新

### 代码规范

- 遵循现有代码风格
- 添加必要的注释
- 确保代码可读性

## 获取帮助

如有任何问题，请通过 GitHub Issues 联系我们。
EOF
```

- [ ] **Step 2: 验证文件已创建**

Run: `ls -la CONTRIBUTING.md`
Expected: `-rw-r--r--  1 user  staff  ... CONTRIBUTING.md`

- [ ] **Step 3: 提交**

```bash
git add CONTRIBUTING.md
git commit -m "docs: add contributing guide"
```

---

### Task 3: 创建 CI 工作流目录和文件

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: 创建目录结构**

```bash
mkdir -p .github/workflows
```

- [ ] **Step 2: 创建 ci.yml 文件**

```bash
cat > .github/workflows/ci.yml << 'EOF'
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
EOF
```

- [ ] **Step 3: 验证文件已创建**

Run: `ls -la .github/workflows/ci.yml`
Expected: `-rw-r--r--  1 user  staff  ... ci.yml`

- [ ] **Step 4: 验证 YAML 语法**

Run: `cat .github/workflows/ci.yml`
Expected: 正确的 YAML 格式

- [ ] **Step 5: 提交**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add CI workflow for build and test"
```

---

### Task 4: 创建 Release 工作流

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: 创建 release.yml 文件**

```bash
cat > .github/workflows/release.yml << 'EOF'
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
EOF
```

- [ ] **Step 2: 验证文件已创建**

Run: `ls -la .github/workflows/release.yml`
Expected: `-rw-r--r--  1 user  staff  ... release.yml`

- [ ] **Step 3: 提交**

```bash
git add .github/workflows/release.yml
git commit -m "ci: add release workflow for automated builds"
```

---

### Task 5: 创建发布说明配置

**Files:**
- Create: `.github/release.yml`

- [ ] **Step 1: 创建 release.yml 配置文件**

```bash
cat > .github/release.yml << 'EOF'
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
EOF
```

- [ ] **Step 2: 验证文件已创建**

Run: `ls -la .github/release.yml`
Expected: `-rw-r--r--  1 user  staff  ... release.yml`

- [ ] **Step 3: 提交**

```bash
git add .github/release.yml
git commit -m "ci: add release notes configuration"
```

---

### Task 6: 创建 Issue 模板目录和 Bug 报告模板

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug_report.md`

- [ ] **Step 1: 创建目录结构**

```bash
mkdir -p .github/ISSUE_TEMPLATE
```

- [ ] **Step 2: 创建 bug_report.md 文件**

```bash
cat > .github/ISSUE_TEMPLATE/bug_report.md << 'EOF'
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
EOF
```

- [ ] **Step 3: 验证文件已创建**

Run: `ls -la .github/ISSUE_TEMPLATE/bug_report.md`
Expected: `-rw-r--r--  1 user  staff  ... bug_report.md`

- [ ] **Step 4: 提交**

```bash
git add .github/ISSUE_TEMPLATE/bug_report.md
git commit -m "docs: add bug report issue template"
```

---

### Task 7: 创建功能建议模板

**Files:**
- Create: `.github/ISSUE_TEMPLATE/feature_request.md`

- [ ] **Step 1: 创建 feature_request.md 文件**

```bash
cat > .github/ISSUE_TEMPLATE/feature_request.md << 'EOF'
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
EOF
```

- [ ] **Step 2: 验证文件已创建**

Run: `ls -la .github/ISSUE_TEMPLATE/feature_request.md`
Expected: `-rw-r--r--  1 user  staff  ... feature_request.md`

- [ ] **Step 3: 提交**

```bash
git add .github/ISSUE_TEMPLATE/feature_request.md
git commit -m "docs: add feature request issue template"
```

---

### Task 8: 创建 PR 模板

**Files:**
- Create: `.github/PULL_REQUEST_TEMPLATE.md`

- [ ] **Step 1: 创建 PULL_REQUEST_TEMPLATE.md 文件**

```bash
cat > .github/PULL_REQUEST_TEMPLATE.md << 'EOF'
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
EOF
```

- [ ] **Step 2: 验证文件已创建**

Run: `ls -la .github/PULL_REQUEST_TEMPLATE.md`
Expected: `-rw-r--r--  1 user  staff  ... PULL_REQUEST_TEMPLATE.md`

- [ ] **Step 3: 提交**

```bash
git add .github/PULL_REQUEST_TEMPLATE.md
git commit -m "docs: add pull request template"
```

---

### Task 9: 更新 README.md

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 读取现有 README.md**

Run: `cat README.md | head -20`
Expected: 显示 README 的前 20 行

- [ ] **Step 2: 在文件顶部添加徽章**

在 `# Daka` 之前添加：

```markdown
[![CI](https://github.com/xue/daka/actions/workflows/ci.yml/badge.svg)](https://github.com/xue/daka/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/xue/daka)](https://github.com/xue/daka/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

```

- [ ] **Step 3: 在"分发安装包"部分添加 GitHub Releases 链接**

在"### 分发安装包"部分的开头添加：

```markdown
### 下载安装

从 [GitHub Releases](https://github.com/xue/daka/releases) 下载最新版本的 `.pkg` 安装包。

```

- [ ] **Step 4: 在文件末尾添加参与贡献部分**

在文件末尾添加：

```markdown
## 参与贡献

我们欢迎各种形式的贡献！请查看 [CONTRIBUTING.md](CONTRIBUTING.md) 了解详情。
```

- [ ] **Step 5: 验证修改**

Run: `git diff README.md`
Expected: 显示 README.md 的变更内容

- [ ] **Step 6: 提交**

```bash
git add README.md
git commit -m "docs: add badges and download link to README"
```

---

### Task 10: 最终验证

- [ ] **Step 1: 检查所有文件是否存在**

Run: `ls -la LICENSE CONTRIBUTING.md .github/`
Expected: 显示所有创建的文件

- [ ] **Step 2: 检查 GitHub Actions 工作流**

Run: `ls -la .github/workflows/`
Expected: 显示 ci.yml 和 release.yml

- [ ] **Step 3: 检查 Issue 模板**

Run: `ls -la .github/ISSUE_TEMPLATE/`
Expected: 显示 bug_report.md 和 feature_request.md

- [ ] **Step 4: 检查 PR 模板**

Run: `ls -la .github/PULL_REQUEST_TEMPLATE.md`
Expected: 显示 PULL_REQUEST_TEMPLATE.md

- [ ] **Step 5: 检查 git 状态**

Run: `git status`
Expected: 显示工作区干净或只有未跟踪的文件

- [ ] **Step 6: 检查提交历史**

Run: `git log --oneline -10`
Expected: 显示最近的 10 条提交

---

## 完成

所有任务完成后，项目将拥有：

1. ✅ MIT 许可证
2. ✅ 贡献者指南
3. ✅ CI 工作流（自动构建和测试）
4. ✅ Release 工作流（自动发布到 GitHub Releases）
5. ✅ 发布说明配置
6. ✅ Bug 报告模板
7. ✅ 功能建议模板
8. ✅ PR 模板
9. ✅ 改进的 README（徽章和下载链接）

### 下一步

1. 推送到 GitHub
2. 创建第一个标签触发发布：
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```
3. 或在 GitHub Actions 页面手动触发发布
