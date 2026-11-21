#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP_NAME="CmdTab"
APP_BUNDLE="$ROOT_DIR/build/${APP_NAME}.app"

echo "🔨 Building $APP_NAME ($CONFIG)..."
cd "$ROOT_DIR"
swift build -c "$CONFIG"

BIN_PATH="$ROOT_DIR/.build/${CONFIG}/${APP_NAME}"
if [[ ! -f "$BIN_PATH" ]]; then
    BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"
fi

echo "📦 Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Bundle all 25 .lproj localization folders
if [[ -d "$ROOT_DIR/Localization" ]]; then
    cp -R "$ROOT_DIR/Localization/"*.lproj "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
fi

# Generate a clean native macOS AppIcon.icns if iconutil is available
if command -v iconutil >/dev/null 2>&1; then
    ICONSET_DIR="$ROOT_DIR/build/AppIcon.iconset"
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    swift - "$ICONSET_DIR" <<'SWIFT'
import AppKit
import Foundation

let outDir = CommandLine.arguments[1]
let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

func renderIcon(px: Int) -> Data? {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Rounded squircle background
    let inset = s * 0.08
    let bgRect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: bgRect, xRadius: s * 0.22, yRadius: s * 0.22)
    let grad = NSGradient(
        starting: NSColor(calibratedRed: 0.14, green: 0.38, blue: 0.98, alpha: 1.0),
        ending: NSColor(calibratedRed: 0.42, green: 0.20, blue: 0.92, alpha: 1.0)
    )!
    grad.draw(in: path, angle: -45)

    // Two overlapping window cards
    let card1 = NSRect(x: s * 0.20, y: s * 0.36, width: s * 0.44, height: s * 0.34)
    NSColor.white.withAlphaComponent(0.32).setFill()
    NSBezierPath(roundedRect: card1, xRadius: s * 0.05, yRadius: s * 0.05).fill()

    let card2 = NSRect(x: s * 0.36, y: s * 0.24, width: s * 0.46, height: s * 0.38)
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect: card2, xRadius: s * 0.06, yRadius: s * 0.06).fill()

    // Window traffic lights on front card
    let dotY = card2.maxY - s * 0.07
    let dotR = s * 0.022
    let colors: [NSColor] = [
        NSColor(calibratedRed: 1.0, green: 0.37, blue: 0.34, alpha: 1),
        NSColor(calibratedRed: 1.0, green: 0.74, blue: 0.18, alpha: 1),
        NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)
    ]
    for (i, c) in colors.enumerated() {
        c.setFill()
        let x = card2.minX + s * 0.055 + CGFloat(i) * (dotR * 2.8)
        NSBezierPath(ovalIn: NSRect(x: x, y: dotY, width: dotR * 2, height: dotR * 2)).fill()
    }

    // Subtle Command glyph inside front card
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: s * 0.17, weight: .bold),
        .foregroundColor: NSColor(calibratedRed: 0.18, green: 0.34, blue: 0.92, alpha: 1.0)
    ]
    let str = NSAttributedString(string: "⌘⇥", attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: card2.midX - sz.width / 2, y: card2.minY + (card2.height - sz.height) * 0.34))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for (px, name) in sizes {
    if let data = renderIcon(px: px) {
        try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    }
}
SWIFT
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" || true
    mkdir -p "$ROOT_DIR/docs"
    cp "$ICONSET_DIR/icon_256x256@2x.png" "$ROOT_DIR/docs/icon.png" 2>/dev/null || true
    rm -rf "$ICONSET_DIR"
fi

SIGN_IDENTITY="CmdTab Local Signing"
if security find-identity -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
    echo "🔏 Signing $APP_BUNDLE with '$SIGN_IDENTITY' (stable TCC identity)..."
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
    echo "🔏 Ad-hoc signing $APP_BUNDLE..."
    codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "✅ Built successfully: $APP_BUNDLE"
echo "👉 Run with: open \"$APP_BUNDLE\""
