APP_NAME   := Daka
BUNDLE_ID  := com.xue.daka
APP_BUNDLE := build/$(APP_NAME).app
PKG_ROOT   := build/pkgroot
PKG_VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
PKG_OUT    := build/$(APP_NAME)-$(PKG_VERSION).pkg
UNIVERSAL  := --arch arm64 --arch x86_64
INSTALL_DIR := /Applications
# 图标变体：spark（默认）/ bell / bell-ring / ring-check / check / clock
ICON_VARIANT ?= spark

.PHONY: build test icon app assemble pkg install clean verify-version dist release

build:
	swift build -c release

test:
	swift test

icon:
	swift scripts/make-appicon.swift Resources/AppIcon.iconset $(ICON_VARIANT)
	iconutil -c icns Resources/AppIcon.iconset -o Resources/Daka.icns

# 生成全部图标变体的对比预览图（不覆盖正式图标）
icon-preview:
	swift scripts/make-appicon.swift --sheet build/appicon-variants.png

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

pkg:
	test -n "$(PKG_VERSION)"
	$(MAKE) assemble ARCHS="$(UNIVERSAL)"
	rm -rf "$(PKG_ROOT)"
	mkdir -p "$(PKG_ROOT)/Applications"
	ditto "$(APP_BUNDLE)" "$(PKG_ROOT)/Applications/$(APP_NAME).app"
	pkgbuild --root "$(PKG_ROOT)" \
	         --identifier "$(BUNDLE_ID)" \
	         --version "$(PKG_VERSION)" \
	         --install-location / \
	         "$(PKG_OUT)"
	@echo "Built $(PKG_OUT)"

install: app
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app.tmp"
	ditto "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app.tmp"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	mv "$(INSTALL_DIR)/$(APP_NAME).app.tmp" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

clean:
	rm -rf .build build

verify-version:
	test -n "$(TAG)"
	@[ "$(PKG_VERSION)" = "$(patsubst v%,%,$(TAG))" ] || (echo "version mismatch: Info.plist $(PKG_VERSION) vs TAG $(TAG)" >&2; exit 1)
	@echo "version ok: $(PKG_VERSION) == $(TAG)"

# 发版：make release VERSION=<x.y.z|patch|minor|major> [MSG="提交信息"]
release:
	@scripts/release.sh '$(VERSION)' '$(MSG)'

dist: pkg
	ditto -c -k --keepParent "$(APP_BUNDLE)" "build/$(APP_NAME)-$(PKG_VERSION).app.zip"
	shasum -a 256 "build/$(APP_NAME)-$(PKG_VERSION).pkg" "build/$(APP_NAME)-$(PKG_VERSION).app.zip" > "build/checksums.txt"
	@echo "Built build/$(APP_NAME)-$(PKG_VERSION).app.zip and build/checksums.txt"
