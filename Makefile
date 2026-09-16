APP_NAME   := Daka
BUNDLE_ID  := com.xue.daka
APP_BUNDLE := build/$(APP_NAME).app
PKG_ROOT   := build/pkgroot
PKG_VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
PKG_OUT    := build/$(APP_NAME)-$(PKG_VERSION).pkg
UNIVERSAL  := --arch arm64 --arch x86_64
INSTALL_DIR := /Applications

.PHONY: build test icon app assemble pkg install clean

build:
	swift build -c release

test:
	swift test

icon:
	swift scripts/make-appicon.swift Resources/AppIcon.iconset
	iconutil -c icns Resources/AppIcon.iconset -o Resources/Daka.icns

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

install: app
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app.tmp"
	ditto "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app.tmp"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	mv "$(INSTALL_DIR)/$(APP_NAME).app.tmp" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

clean:
	rm -rf .build build
