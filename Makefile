# Build Configuration
APP_NAME = MarkdownFormatter
APP_BUNDLE = $(APP_NAME).app
BIN_DIR = bin
SRC = Sources/main.swift

.PHONY: all build app run stop clean install

all: build app

# Build CLI binary
build:
	@mkdir -p $(BIN_DIR)
	swiftc -O $(SRC) -o $(BIN_DIR)/$(APP_NAME)
	@echo "✓ Binary compiled successfully at $(BIN_DIR)/$(APP_NAME)"

# Package as macOS App Bundle (.app)
app: build
	@mkdir -p $(APP_BUNDLE)/Contents/MacOS
	@mkdir -p $(APP_BUNDLE)/Contents/Resources
	@cp $(BIN_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)
	@if [ -f Resources/AppIcon.icns ]; then cp Resources/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns; fi
	@echo '<?xml version="1.0" encoding="UTF-8"?>' > $(APP_BUNDLE)/Contents/Info.plist
	@echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '<plist version="1.0">' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '<dict>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>CFBundleExecutable</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>$(APP_NAME)</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>CFBundleIdentifier</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>org.markdown-formatter.app</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>CFBundleName</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>Markdown Clipboard Formatter</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>CFBundlePackageType</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>APPL</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>CFBundleShortVersionString</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>1.0</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>CFBundleVersion</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>1</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>CFBundleIconFile</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>AppIcon.icns</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>LSMinimumSystemVersion</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <string>10.15</string>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <key>LSUIElement</key>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '    <true/>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '</dict>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo '</plist>' >> $(APP_BUNDLE)/Contents/Info.plist
	@echo "✓ App bundle packaged successfully at ./$(APP_BUNDLE)"

# Run app bundle in background
run: app
	@open $(APP_BUNDLE)
	@echo "✓ Launched $(APP_NAME) in the background!"

# Stop all running instances of the app
stop:
	@killall $(APP_NAME) 2>/dev/null || true
	@echo "✓ Stopped any running instances of $(APP_NAME)."

# Clean build artifacts
clean:
	@rm -rf $(BIN_DIR) $(APP_BUNDLE)
	@echo "✓ Cleaned build artifacts."

# Install to user Applications folder
install: app stop
	@mkdir -p ~/Applications
	@rm -rf ~/Applications/$(APP_BUNDLE)
	@cp -R $(APP_BUNDLE) ~/Applications/
	@open ~/Applications/$(APP_BUNDLE)
	@echo "✓ $(APP_NAME) installed and launched in ~/Applications!"
