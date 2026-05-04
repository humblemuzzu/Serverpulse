#!/bin/bash

APP_NAME="ServerPulse"
BUNDLE_ID="com.muzammil.serverpulse"
OUTPUT_DIR="./build"
APP_PATH="$OUTPUT_DIR/$APP_NAME.app"

echo "🔨 Building $APP_NAME..."

mkdir -p "$OUTPUT_DIR"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp ServerPulse/Info.plist "$APP_PATH/Contents/"

swiftc -O \
    -target arm64-apple-macosx12.0 \
    -o "$APP_PATH/Contents/MacOS/ServerPulse" \
    ServerPulse/main.swift \
    -framework Cocoa \
    -framework SwiftUI

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
    echo "📍 App location: $APP_PATH"
    echo ""
    echo "To run:  open \"$APP_PATH\""
    echo ""
    echo "To auto-start on login:"
    echo "  System Settings → General → Login Items → add ServerPulse"
else
    echo "❌ Build failed!"
    exit 1
fi
