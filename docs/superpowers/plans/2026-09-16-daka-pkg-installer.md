# Daka macOS PKG 独立安装包 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 新增 `make pkg`，产出可分发到他人 Mac 的 `build/Daka-<version>.pkg`（Universal 二进制，安装到 `/Applications`，ad-hoc 签名）。

**Architecture:** 纯 `Makefile` 改动：把 app 组装抽成内部目标 `assemble`（`ARCHS` 参数注入），`app` 传空（本机架构），`pkg` 传 `--arch arm64 --arch x86_64`；二进制路径用 `swift build --show-bin-path` 动态取，避免多架构产物路径差异；再用 `pkgbuild` 把 app 打进以 `/` 为安装位置的 component pkg。README 补充构建/分发说明与 Gatekeeper 处理方式。

**Tech Stack:** Swift 5.10+、SwiftPM、GNU make、`codesign` / `pkgbuild` / `pkgutil` / `lipo` / `PlistBuddy`。

**Spec:** `docs/superpowers/specs/2026-09-16-daka-pkg-installer-design.md`

---

## File Structure

- `Makefile`（改）：新增变量 `BUNDLE_ID` / `PKG_ROOT` / `PKG_VERSION` / `PKG_OUT` / `UNIVERSAL`，删除不再使用的 `RELEASE_DIR`；新增内部目标 `assemble` 与对外目标 `pkg`；`app` 改为调用 `assemble`；`.PHONY` 追加。`clean` 无需改动（`rm -rf build` 已覆盖 pkg 产物）。
- `README.md`（改）：「构建与安装」补 `make pkg` 与产物路径；新增「分发安装包」小节；「已知限制」补未签名/未公证说明。
- `docs/verification.md`（改）：新增 v18 手动验证小节。

无 Swift 源码改动。

---

### Task 1: `assemble` 内部目标 + 动态二进制路径

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: 替换变量头部**

把 `Makefile:1-4`：

```make
APP_NAME   := Daka
RELEASE_DIR := .build/release
APP_BUNDLE := build/$(APP_NAME).app
INSTALL_DIR := /Applications
```

替换为：

```make
APP_NAME   := Daka
BUNDLE_ID  := com.xue.daka
APP_BUNDLE := build/$(APP_NAME).app
PKG_ROOT   := build/pkgroot
PKG_VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
PKG_OUT    := build/$(APP_NAME)-$(PKG_VERSION).pkg
UNIVERSAL  := --arch arm64 --arch x86_64
INSTALL_DIR := /Applications
```

- [ ] **Step 2: 更新 `.PHONY`**

把 `Makefile:6`：

```make
.PHONY: build test icon app install clean
```

替换为：

```make
.PHONY: build test icon app assemble pkg install clean
```

- [ ] **Step 3: 把 `app` 拆成 `app` + `assemble`**

把 `Makefile:18-26`：

```make
app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(RELEASE_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/Daka.icns $(APP_BUNDLE)/Contents/Resources/Daka.icns
	codesign --force --sign - "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"
```

替换为：

```make
app:
	$(MAKE) assemble ARCHS=

assemble:
	swift build -c release $(ARCHS)
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp "$$(swift build -c release $(ARCHS) --show-bin-path)/$(APP_NAME)" $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	cp Resources/Daka.icns $(APP_BUNDLE)/Contents/Resources/Daka.icns
	codesign --force --sign - "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"
```

注意：`$$( ... )` 是 Makefile 里对 shell 命令替换的转义写法（Make 展开后交给 shell 执行 `$(swift build ... --show-bin-path)`）。

- [ ] **Step 4: 验证 `make app` 仍然可用**

Run: `make app`
Expected: 先 `swift build -c release`，最后输出 `Built build/Daka.app`。

- [ ] **Step 5: 验证产物正确**

Run: `lipo -archs build/Daka.app/Contents/MacOS/Daka && codesign -dv build/Daka.app 2>&1 | grep -E 'Signature|Identifier'`
Expected: 第一行 `arm64`（本机架构）；第二行出现 `Signature=adhoc` 与 `Identifier=com.xue.daka`。

- [ ] **Step 6: 提交**

```bash
git add Makefile
git commit -m "refactor: extract assemble target with dynamic bin path"
```

---

### Task 2: `make pkg` 产出 Universal PKG

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: 新增 `pkg` 目标**

在 `Makefile` 的 `install` 目标之前插入：

```make
pkg:
	$(MAKE) assemble ARCHS="$(UNIVERSAL)"
	rm -rf $(PKG_ROOT)
	mkdir -p $(PKG_ROOT)/Applications
	ditto $(APP_BUNDLE) $(PKG_ROOT)/Applications/$(APP_NAME).app
	pkgbuild --root $(PKG_ROOT) \
	         --identifier $(BUNDLE_ID) \
	         --version $(PKG_VERSION) \
	         --install-location / \
	         $(PKG_OUT)
	@echo "Built $(PKG_OUT)"
```

- [ ] **Step 2: 确认 `clean` 无需改动**

现有 `clean: rm -rf .build build` 已覆盖 `build/pkgroot` 与 `build/*.pkg`，不改动。

- [ ] **Step 3: 验证 `make pkg`**

Run: `make pkg`
Expected: 编译 universal 二进制（较慢），最后输出 `Built build/Daka-1.0.pkg`；`pkgbuild` 无报错。

- [ ] **Step 4: 验证二进制为 Universal**

Run: `lipo -archs build/Daka.app/Contents/MacOS/Daka`
Expected: `arm64 x86_64`（顺序可能为 `x86_64 arm64`）。

- [ ] **Step 5: 验证 pkg 内容与安装位置**

Run: `pkgutil --payload-files build/Daka-1.0.pkg`
Expected: 列出以 `Applications/Daka.app/Contents/MacOS/Daka`、`Applications/Daka.app/Contents/Info.plist`、`Applications/Daka.app/Contents/Resources/Daka.icns` 开头的路径。

- [ ] **Step 6: 记录签名状态（预期 unsigned，仅验证不崩）**

Run: `pkgutil --check-signature build/Daka-1.0.pkg`
Expected: 输出包含 `Status: no signature` 或 `unsigned`（ad-hoc 未对 pkg 签名，属预期）。

- [ ] **Step 7: 提交**

```bash
git add Makefile
git commit -m "feat: add make pkg producing universal installer package"
```

---

### Task 3: README 构建与分发说明

**Files:**
- Modify: `README.md`

- [ ] **Step 1: 「构建与安装」补 `make pkg`**

把 `README.md:28-35` 的代码块：

```sh
make build     # 仅编译（release）
make test      # 运行单元测试
make icon      # 由 Resources/AppIcon.iconset 生成 Daka.icns
make app       # 编译 + 组装并 ad-hoc 签名 build/Daka.app
make install   # 在 app 基础上安装到 /Applications/Daka.app
make clean     # 清理 .build 与 build
```

替换为：

```sh
make build     # 仅编译（release，本机架构）
make test      # 运行单元测试
make icon      # 由 Resources/AppIcon.iconset 生成 Daka.icns
make app       # 编译 + 组装并 ad-hoc 签名 build/Daka.app（本机架构）
make pkg       # 编译 Universal（arm64 + x86_64）+ 组装 + 打成 build/Daka-<版本>.pkg
make install   # 在 app 基础上安装到 /Applications/Daka.app
make clean     # 清理 .build 与 build
```

- [ ] **Step 2: 新增「分发安装包」小节**

把 `README.md:37`：

```markdown
首次运行若需重新生成图标，先执行 `make icon`；`make app` / `make install` 依赖 `Resources/Daka.icns` 已存在。
```

替换为：

```markdown
首次运行若需重新生成图标，先执行 `make icon`；`make app` / `make pkg` / `make install` 依赖 `Resources/Daka.icns` 已存在。

### 分发安装包

`make pkg` 产出的 `build/Daka-<版本>.pkg` 是 Universal 安装包，双击后自动把应用装到 `/Applications/Daka.app`。

安装包与 app 均为 **ad-hoc 签名、未公证**，别人首次打开会被 Gatekeeper 拦截，需任选一种放行：

- 右键 pkg →「打开」，或
- 系统设置 →「隐私与安全性」→「仍要打开」。

若安装后启动仍提示已损坏/无法验证，执行：

```sh
xattr -dr com.apple.quarantine /Applications/Daka.app
```

**安装前请先退出正在运行的应用**（主窗口「设置 → 系统与启动 → 退出应用」），否则安装器覆盖运行中的 app 可能失败。
```

- [ ] **Step 3: 「已知限制」补签名说明**

在 `README.md`「已知限制」小节末尾追加：

```markdown
- 安装包为 ad-hoc 签名、未公证（无 Developer ID 证书），分发给他人需按「分发安装包」一节放行 Gatekeeper。
```

- [ ] **Step 4: 提交**

```bash
git add README.md
git commit -m "docs: document make pkg and distribution steps"
```

---

### Task 4: 验证清单 + 端到端安装冒烟

**Files:**
- Modify: `docs/verification.md`

- [ ] **Step 1: 新增 v18 小节**

在 `docs/verification.md` 末尾追加：

```markdown
## v18：PKG 独立安装包

- [ ] `make pkg` 产出 `build/Daka-1.0.pkg`，无报错。
- [ ] `lipo -archs build/Daka.app/Contents/MacOS/Daka` 输出 `arm64 x86_64`（Intel 与 Apple Silicon 都可装）。
- [ ] `pkgutil --payload-files build/Daka-1.0.pkg` 列出 `Applications/Daka.app/...`。
- [ ] 双击 pkg 走完安装向导，`/Applications/Daka.app` 为本次构建；从 `/Applications` 启动后 Dock + 菜单栏 + 主窗口正常。
- [ ] 从 `/Applications` 运行时「定点拉起」生效（应用要求路径以 `/Applications/` 开头）。
- [ ] `make app` 仍只编本机架构（未回归）。
- [ ] `make install` 仍正常安装并启动。
```

- [ ] **Step 2: 全量测试**

Run: `make test`
Expected: 全部用例通过（本次不改 Swift 代码）。

- [ ] **Step 3: 端到端安装冒烟**

先退出正在运行的应用（主窗口 →「设置 → 系统与启动 → 退出应用」），然后：

Run: `open build/Daka-1.0.pkg`
Expected: 弹出安装向导；一路「继续 → 安装」，完成后 `/Applications/Daka.app` 更新。

Run: `codesign -dv /Applications/Daka.app 2>&1 | grep Signature && lipo -archs /Applications/Daka.app/Contents/MacOS/Daka`
Expected: `Signature=adhoc`；`arm64 x86_64`。

- [ ] **Step 4: 确认 `make install` 未回归**

Run: `make install`
Expected: 输出 `Built build/Daka.app` 与 `Installed to /Applications/Daka.app`。

- [ ] **Step 5: 提交**

```bash
git add docs/verification.md
git commit -m "docs: add pkg installer verification checklist"
```

---

## Self-Review

**Spec coverage：** §3 动态路径（Task 1 Step 3）、§4 变量与目标结构（Task 1/2）、§5 运行中安装（Task 3 Step 2 提示 + Task 4 Step 3 前置退出）、§6 分发说明（Task 3）、§7 验证（Task 2 Step 4-6、Task 4）、§8 范围（无 Swift 改动、无公证）、§9 交付（全部）。

**Placeholder scan：** 无 TBD/TODO；每个步骤给出完整代码或完整命令。

**Type consistency：** `ARCHS` 由 `app` 传空、`pkg` 传 `$(UNIVERSAL)`，`assemble` 只读该变量；`PKG_VERSION` 在变量头部定义一次，`PKG_OUT` 与 `pkgbuild --version` 同源；`BUNDLE_ID` 与 `Info.plist` 的 `com.xue.daka` 一致；`PKG_ROOT` 在 `pkg` 与 `clean` 中同名引用。
