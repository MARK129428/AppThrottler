#!/bin/bash
# Makefile alternative for building AppThrottler
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="AppThrottler"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
SRC_DIR="$PROJECT_DIR/$APP_NAME"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    TARGET="arm64-apple-macosx14.0"
else
    TARGET="x86_64-apple-macosx14.0"
fi

case "${1:-build}" in
    build)
        echo "🔨 Building $APP_NAME for $ARCH..."
        rm -rf "$BUILD_DIR"
        mkdir -p "$APP_BUNDLE/Contents/MacOS"
        mkdir -p "$APP_BUNDLE/Contents/Resources"
        cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>AppThrottler</string>
    <key>CFBundleIdentifier</key><string>com.appthrottler.app</string>
    <key>CFBundleName</key><string>AppThrottler</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

        swiftc \
            -target "$TARGET" \
            -sdk "$(xcrun --show-sdk-path)" \
            -framework SwiftUI \
            -framework AppKit \
            -framework Foundation \
            -parse-as-library \
            -O \
            -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
            "$SRC_DIR/AppThrottlerApp.swift" \
            "$SRC_DIR/ContentView.swift" \
            "$SRC_DIR/ProcessManager.swift" \
            "$SRC_DIR/ThrottleManager.swift" \
            "$SRC_DIR/NetworkProfile.swift" \
            "$SRC_DIR/ProfileManager.swift" \
            "$SRC_DIR/ScenarioEngine.swift" \
            "$SRC_DIR/CLIRunner.swift" \
            "$SRC_DIR/PacketCaptureManager.swift" \
            "$SRC_DIR/TrafficMonitor.swift" \
            "$SRC_DIR/FaultInjector.swift" \
            "$SRC_DIR/ReportGenerator.swift" \
            "$SRC_DIR/Integrations.swift" \
            "$SRC_DIR/HTTPInspector.swift" \
            "$SRC_DIR/HTTPInspectorView.swift" \
            "$SRC_DIR/Theme.swift" \
            "$SRC_DIR/ServerManager.swift" \
            "$SRC_DIR/ProxyServer.swift" \
            "$SRC_DIR/ToastView.swift"

        echo "✅ Build succeeded: $APP_BUNDLE"
        ;;
    run)
        "$0" build
        open "$APP_BUNDLE"
        ;;
    clean)
        rm -rf "$BUILD_DIR"
        echo "🧹 Cleaned."
        ;;
    *)
        echo "Usage: $0 {build|run|clean}"
        exit 1
        ;;
esac
