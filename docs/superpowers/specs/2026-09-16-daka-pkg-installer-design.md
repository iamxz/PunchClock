# Daka：macOS PKG 独立安装包设计

日期：2026-09-16
状态：已确认（待实现）

## 1. 目标

在现有 `make app` / `make install` 之外，新增一个可分发的独立安装包（PKG）：

1. 一条命令产出 `build/Daka-<version>.pkg`。
2. 二进制为 **Universal（arm64 + x86_64）**，Intel 与 Apple Silicon 均可安装。
3. 安装后应用位于 `/Applications/Daka.app`。
4. 采用 **ad-hoc 签名**，配套 README 说明 Gatekeeper 处理方式。
5. 不引入新脚本，改动集中在 `Makefile` 与 `README.md`（方案 A）。

## 2. 现状

- 构建为 SwiftPM（`Package.swift`，macOS 14+），产物由 `Makefile` 组装成 app bundle：
  - `make build` → `swift build -c release`（当前机器架构）
  - `make app` → 组 `build/Daka.app`，`codesign --force --sign -`（ad-hoc）
  - `make install` → `ditto` 到 `/Applications/Daka.app`
- `Makefile` 写死 `RELEASE_DIR := .build/release`。
- 应用对安装位置有依赖：`Sources/Daka/ScheduledLaunchManager.swift:30` 要求 `Bundle.main.bundlePath` 以 `/Applications/` 开头，否则跳过「定点拉起」。因此安装到 `/Applications` 是硬性要求。
- 应用为常驻、拦截退出（菜单/Cmd+Q/Dock 均不能退出），只能由「设置 → 系统与启动 → 退出应用」退出。
- 无 Apple Developer ID 证书；无公证。

## 3. 二进制路径处理（关键修正）

多架构构建时产物目录与单架构不同，不能再写死 `.build/release`。改为在组装时动态获取：

```make
"$(shell swift build -c release $(ARCHS) --show-bin-path)/$(APP_NAME)"
```

本机实测：单架构与 `--arch arm64 --arch x86_64` 均返回 `.build/out/Products/Release`，而 `.build/release` 只是指向该目录的软链接。用 `--show-bin-path` 可同时覆盖两种情况，避免依赖软链接是否存在的巧合。

`ARCHS` 是目标参数，故通过子 make 调用（`$(MAKE) assemble ARCHS=...`）注入，不能用 `:=` 提前固化。

## 4. Makefile 改动

新增/调整的变量：

```make
APP_NAME    := Daka
BUNDLE_ID   := com.xue.daka
APP_BUNDLE  := build/$(APP_NAME).app
PKG_ROOT    := build/pkgroot
PKG_VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
PKG_OUT     := build/$(APP_NAME)-$(PKG_VERSION).pkg
UNIVERSAL   := --arch arm64 --arch x86_64
```

目标结构：

- `build`：行为不变，`swift build -c release`。
- `app`：对外行为不变（本机架构）。实现改为 `$(MAKE) assemble ARCHS=`。
- `assemble`（内部目标）：用传入的 `ARCHS` 编二进制并组装 `build/Daka.app`：

  ```make
  assemble:
  	swift build -c release $(ARCHS)
  	rm -rf $(APP_BUNDLE)
  	mkdir -p $(APP_BUNDLE)/Contents/MacOS $(APP_BUNDLE)/Contents/Resources
  	cp "$(shell swift build -c release $(ARCHS) --show-bin-path)/$(APP_NAME)" $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
  	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
  	cp Resources/Daka.icns $(APP_BUNDLE)/Contents/Resources/Daka.icns
  	codesign --force --sign - "$(APP_BUNDLE)"
  ```

- `pkg`（新增，对外）：

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
  ```

- `install`：保持现状（`ditto` 到 `/Applications`）。
- `clean`：追加 `rm -rf $(PKG_ROOT) build/*.pkg`。
- `.PHONY` 追加 `assemble pkg`。

顺序要求：**先签名 app，再 `ditto` 进 pkgroot、再 `pkgbuild`**，确保包内 app 带签名。

`--install-location /` 配合 root 内的 `Applications/` 目录，产物安装路径为 `/Applications/Daka.app`，同时避免 pkgbuild 对根安装位置的告警。

版本号来自 `Info.plist` 的 `CFBundleShortVersionString`（当前 `1.0`），pkg 文件名与 pkg 元数据同源，避免两处维护。

## 5. 运行中安装的处理

应用常驻且拦截退出，安装器覆盖运行中的 app 会出问题。设计选择：

- **不在包内放 `pkill` 等 preinstall 脚本**——会违背应用「不允许随便退出」的设计意图。
- 已存在 `/Applications/Daka.app` 时由 installer 直接覆盖。
- README 明确要求：安装前先在「设置 → 系统与启动 → 退出应用」。

## 6. 分发说明（README 新增）

ad-hoc、未公证的现实需写清：

- 别人双击 pkg 会被 Gatekeeper 拦；处理方式：
  - 右键 pkg →「打开」，或
  - 系统设置 →「隐私与安全性」→「仍要打开」。
- 若安装后仍被隔离：

  ```sh
  xattr -dr com.apple.quarantine /Applications/Daka.app
  ```

- 「已知限制」补充：未使用 Developer ID 签名、未公证，分发给他人需按上述方式放行。

## 7. 验证

自动/命令级：

- `lipo -archs build/Daka.app/Contents/MacOS/Daka` → `arm64 x86_64`
- `pkgutil --payload-files build/Daka-1.0.pkg` → 列出 `Applications/Daka.app/...`
- `pkgutil --check-signature build/Daka-1.0.pkg` → 记录实际结果（预期 unsigned）
- `codesign -dv --verbose=4 build/Daka.app` → 显示 ad-hoc
- `make test` 不受影响，全绿

手动：

- `open build/Daka-1.0.pkg` 走完安装，确认 `/Applications/Daka.app` 为新构建。
- 从 `/Applications` 启动，确认 Dock + 菜单栏 + 主窗口正常。
- 确认「定点拉起」在 `/Applications` 下生效（路径前缀检查通过）。

## 8. 范围说明

- 不改任何 Swift 源码。
- 不引入 Developer ID 签名 / 公证流程（无证书）。
- 不做 DMG、不做 `productbuild` 发行版安装器（本次仅 component pkg）。
- 不做自动更新机制。

## 9. 交付

- 更新后的 `Makefile`（新增 `make pkg`）。
- 更新后的 `README.md`（构建与分发说明、已知限制）。
- 验证产物 `build/Daka-1.0.pkg`（`build/` 已在 `.gitignore`，不入库）。
