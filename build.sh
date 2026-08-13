#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Building washi (release)..."
swift build -c release

APP_NAME="washi.app"
CONTENTS="$APP_NAME/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "==> Assembling $APP_NAME..."
rm -rf "$APP_NAME"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

BIN_PATH="$(swift build -c release --show-bin-path)/washi"
cp "$BIN_PATH" "$MACOS_DIR/washi"

cp Resources/Info.plist "$CONTENTS/Info.plist"

if [ -d "Resources/Assets/StarterClipart" ]; then
    mkdir -p "$RESOURCES_DIR/StarterClipart"
    cp -R Resources/Assets/StarterClipart/. "$RESOURCES_DIR/StarterClipart/"
fi

echo "==> Ad-hoc codesigning..."
codesign --force --deep --sign - "$APP_NAME"

echo "==> Done."
echo "App bundle: $(pwd)/$APP_NAME"
echo "Run it with: open $APP_NAME"
