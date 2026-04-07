PROJECT      = AIProgressMonitor.xcodeproj
SCHEME       = AIProgressMonitor
DERIVED_DATA = build/DerivedData
APP_NAME     = AIProgressMonitor
RELEASE_DIR  = $(DERIVED_DATA)/Build/Products/Release
APP_PATH     = $(RELEASE_DIR)/$(APP_NAME).app
DMG_DIR      = build/dmg
DMG_PATH     = build/$(APP_NAME).dmg

# コード署名なしでローカルビルド（個人利用向け）
CODESIGN_FLAGS = CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

HOOK_DIR = $(HOME)/Library/Application\ Support/AIProgressMonitor

.PHONY: all build debug release clean install dmg setup-hooks

all: release

## Debug ビルド
debug:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-derivedDataPath $(DERIVED_DATA) \
		$(CODESIGN_FLAGS) \
		build

## Release ビルド
release:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-derivedDataPath $(DERIVED_DATA) \
		$(CODESIGN_FLAGS) \
		build

## ~/Applications にインストール
install: release
	mkdir -p ~/Applications
	rm -rf ~/Applications/$(APP_NAME).app
	cp -R $(APP_PATH) ~/Applications/$(APP_NAME).app
	@echo "Installed to ~/Applications/$(APP_NAME).app"

## DMG 作成（配布用）
dmg: release
	rm -rf $(DMG_DIR) $(DMG_PATH)
	mkdir -p $(DMG_DIR)
	cp -R $(APP_PATH) $(DMG_DIR)/
	ln -s /Applications $(DMG_DIR)/Applications
	hdiutil create \
		-volname "$(APP_NAME)" \
		-srcfolder $(DMG_DIR) \
		-ov \
		-format UDZO \
		$(DMG_PATH)
	rm -rf $(DMG_DIR)
	@echo "Created $(DMG_PATH)"

## フックスクリプトを配置
setup-hooks:
	mkdir -p $(HOOK_DIR)
	cp hooks/claude-code-hook.sh $(HOOK_DIR)/hook.sh
	chmod +x $(HOOK_DIR)/hook.sh
	cp hooks/copilot-hook.sh $(HOOK_DIR)/copilot-hook.sh
	chmod +x $(HOOK_DIR)/copilot-hook.sh
	mkdir -p $(HOME)/.copilot/hooks
	cp hooks/copilot-hooks.json $(HOME)/.copilot/hooks/ai-progress-monitor.json
	@echo "Hooks installed."

## ビルド成果物を削除
clean:
	rm -rf build
