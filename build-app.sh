#!/bin/bash
set -e

APP_NAME="LettoreNative"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🛠 Building release binary..."
swift build -c release

echo "📦 Creating App Bundle structure..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "📋 Copying binary..."
cp .build/release/LettoreApp "$MACOS_DIR/$APP_NAME"

echo "📝 Creating Info.plist..."
cat << PLIST > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Lettore Native</string>
    <key>CFBundleDisplayName</key>
    <string>Lettore Native</string>
    <key>CFBundleIdentifier</key>
    <string>com.p3ter.lettorenative</string>
    <key>CFBundleVersion</key>
    <string>3.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>3.0</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>NSAppleEventsUsageDescription</key>
    <string>Lettore Native necessita di controllare altre app per leggere il testo selezionato.</string>
</dict>
</plist>
PLIST

echo "🔐 Signing App Bundle (Ad-hoc)..."
codesign --force --deep --sign - "$APP_DIR"

echo "✅ App Bundle created successfully at: $(pwd)/$APP_DIR"
