#!/bin/bash

APP_NAME="ServerPulse"
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
    echo ""

    # Install to ~/Applications for Spotlight & Raycast
    mkdir -p ~/Applications
    cp -R "$APP_PATH" ~/Applications/
    echo "📦 Installed to ~/Applications/ServerPulse.app"
    echo "   → Searchable in Spotlight and Raycast"
    echo ""
    echo "To run:  open ~/Applications/ServerPulse.app"
    echo ""
    echo "To auto-start on login:"
    echo "  System Settings → General → Login Items → add ServerPulse"
else
    echo "❌ Build failed!"
    exit 1
fi
