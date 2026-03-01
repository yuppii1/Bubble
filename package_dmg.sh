#!/bin/bash

# Bubble Advanced DMG Packager
# Automates background art and icon layout using AppleScript.

APP_NAME="Bubble"
IMAGE_NAME="${APP_NAME}_Installer"
STAGING_DIR="dmg_staging"
RELEASE_DIR="release"
BACKGROUND_IMG="Resources/dmg_background.png"

echo "🎯 Preparing staging area..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "build/${APP_NAME}.app" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Hide the background image folder
mkdir -p "$STAGING_DIR/.background"
cp "$BACKGROUND_IMG" "$STAGING_DIR/.background/background.png"

echo "💿 Creating temporary disk image..."
rm -f "${IMAGE_NAME}_temp.dmg"
hdiutil create -srcfolder "$STAGING_DIR" -volname "$APP_NAME Installation" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW "${IMAGE_NAME}_temp.dmg"

echo "📂 Mounting image for configuration..."
DEVICE=$(hdiutil attach -readwrite -noverify "${IMAGE_NAME}_temp.dmg" | grep 'Apple_HFS' | awk '{print $1}')
sleep 2 # Wait for mount

echo "🎨 Applying visual styles via AppleScript..."
# Coordinates are {x, y}
APP_POS="{170, 240}"
APPS_POS="{430, 240}"
WINDOW_SIZE="{600, 500}"

osascript <<EOF
tell application "Finder"
    tell disk "$APP_NAME Installation"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 100, 400 + 600, 100 + 500}
        set viewOptions to the icon view options of container window
        set icon size of viewOptions to 100
        set arrangement of viewOptions to not arranged
        set background picture of viewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" to $APP_POS
        set position of item "Applications" to $APPS_POS
        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

echo "⏏️ Ejecting and finalizing..."
hdiutil detach "$DEVICE"
sleep 2

mkdir -p "$RELEASE_DIR"
rm -f "$RELEASE_DIR/${APP_NAME}.dmg"
hdiutil convert "${IMAGE_NAME}_temp.dmg" -format UDZO -imagekey zlib-level=9 -o "$RELEASE_DIR/${APP_NAME}.dmg"

rm -f "${IMAGE_NAME}_temp.dmg"
rm -rf "$STAGING_DIR"

echo "✅ Enhanced DMG created at $RELEASE_DIR/${APP_NAME}.dmg"
