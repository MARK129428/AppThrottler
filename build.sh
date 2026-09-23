#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="AppThrottler"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SRC_DIR="$PROJECT_DIR/$APP_NAME"

echo "🔨 Building $APP_NAME..."
echo ""

# Clean
rm -rf "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Generate Info.plist with resolved values
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>AppThrottler</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.appthrottler.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>AppThrottler</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

# Compile Swift files
SOURCES=(
    "$SRC_DIR/AppThrottlerApp.swift"
    "$SRC_DIR/ContentView.swift"
    "$SRC_DIR/ProcessManager.swift"
    "$SRC_DIR/ThrottleManager.swift"
    "$SRC_DIR/NetworkProfile.swift"
    "$SRC_DIR/ProfileManager.swift"
    "$SRC_DIR/ScenarioEngine.swift"
    "$SRC_DIR/CLIRunner.swift"
    "$SRC_DIR/PacketCaptureManager.swift"
    "$SRC_DIR/TrafficMonitor.swift"
    "$SRC_DIR/FaultInjector.swift"
    "$SRC_DIR/ReportGenerator.swift"
    "$SRC_DIR/Integrations.swift"
    "$SRC_DIR/HTTPInspector.swift"
    "$SRC_DIR/HTTPInspectorView.swift"
    "$SRC_DIR/Theme.swift"
    "$SRC_DIR/ServerManager.swift"
    "$SRC_DIR/ProxyServer.swift"
)

# Copy icon if available
if [ -f "$PROJECT_DIR/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
    echo "🎨 Icon copied"
fi

echo "📦 Compiling sources..."
swiftc \
    -target arm64-apple-macosx14.0 \
    -sdk "$(xcrun --show-sdk-path)" \
    -framework SwiftUI \
    -framework AppKit \
    -framework Foundation \
    -parse-as-library \
    -O \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    "${SOURCES[@]}"

echo "✅ Build succeeded!"
echo ""
echo "📱 App bundle: $APP_BUNDLE"
echo ""
echo "To run: open '$APP_BUNDLE'"
echo "To run with sudo (for throttle features): sudo '$APP_BUNDLE/Contents/MacOS/$APP_NAME'"
