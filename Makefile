APP_NAME   := Daka
RELEASE_DIR := .build/release
APP_BUNDLE := build/$(APP_NAME).app
INSTALL_DIR := /Applications

.PHONY: build test app install clean

build:
	swift build -c release

test:
	swift test

app: build
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(RELEASE_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist
	codesign --force --sign - "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

install: app
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app.tmp"
	ditto "$(APP_BUNDLE)" "$(INSTALL_DIR)/$(APP_NAME).app.tmp"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	mv "$(INSTALL_DIR)/$(APP_NAME).app.tmp" "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Installed to $(INSTALL_DIR)/$(APP_NAME).app"

clean:
	rm -rf .build build
