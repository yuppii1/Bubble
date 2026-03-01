#!/bin/bash

# Bubble macOS Build & Package Script
# Automates the creation of a signed .app bundle for the App Store.

APP_NAME="Bubble"
BUNDLE_ID="com.kwon.bubble"
BUILD_DIR="./build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
ENTITLEMENTS="BubbleMacOS/AITagger.entitlements"
ICON_PATH="Resources/AppIcon.png"

# 1. Clean and Create Directory
echo "🧹 Cleaning previous builds..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 2. Build the Swift Executable
echo "🏗️ Building Swift Package..."
pushd BubbleMacOS
swift build -c release --product Bubble --arch arm64
popd

# 3. Copy Executable and Resources
echo "📦 Packaging..."
cp "BubbleMacOS/.build/arm64-apple-macosx/release/Bubble" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

# Copy SPM Resource Bundle if it exists
BUNDLE_SRC="BubbleMacOS/.build/arm64-apple-macosx/release/Bubble_BubbleMacOS.bundle"
if [ -d "$BUNDLE_SRC" ]; then
    echo "🎨 Copying resource bundle..."
    cp -R "$BUNDLE_SRC" "$APP_BUNDLE/Contents/Resources/"
fi

# 4. Generate Info.plist
cat <<EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.3</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# 5. Codesign (if entitlements exist)
if [ -f "$ENTITLEMENTS" ]; then
    echo "🔐 Codesigning with entitlements..."
    # Clear extended attributes that cause codesign failures
    xattr -rc "$APP_BUNDLE"
    codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP_BUNDLE"
else
    echo "⚠️ Entitlements file not found. Skipping codesign..."
fi

echo "✅ App bundle created at ${APP_BUNDLE}"
