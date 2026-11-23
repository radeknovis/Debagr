#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_ICNS="${1:-$ROOT_DIR/dist/AppIcon.icns}"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

ICONSET_DIR="$WORK_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR" "$(dirname "$OUT_ICNS")"

BASE_PNG="$WORK_DIR/icon_1024.png"

cat > "$WORK_DIR/render.swift" <<'SWIFT'
import AppKit
import CoreGraphics
import Foundation

let outPath = CommandLine.arguments[1]
let size: CGFloat = 1024
let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: Int(size),
  pixelsHigh: Int(size),
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
guard let ctx = NSGraphicsContext.current?.cgContext else {
  fatalError("No graphics context")
}

// Amber macOS squircle background
let rect = CGRect(x: 64, y: 64, width: 896, height: 896)
let bgPath = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
let grad = NSGradient(
  starting: NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.04, alpha: 1.0),
  ending: NSColor(calibratedRed: 0.71, green: 0.33, blue: 0.04, alpha: 1.0)
)!
grad.draw(in: bgPath, angle: -45)

// Dark slate device body
let phoneRect = CGRect(x: 276, y: 182, width: 472, height: 660)
let phonePath = NSBezierPath(roundedRect: phoneRect, xRadius: 84, yRadius: 84)
NSColor(calibratedRed: 0.09, green: 0.12, blue: 0.18, alpha: 1.0).setFill()
phonePath.fill()
NSColor(calibratedRed: 0.99, green: 0.90, blue: 0.54, alpha: 0.95).setStroke()
phonePath.lineWidth = 22
phonePath.stroke()

// Signal waves inside screen
ctx.setLineCap(.round)
ctx.setLineWidth(28)
ctx.setStrokeColor(NSColor(calibratedRed: 0.98, green: 0.75, blue: 0.14, alpha: 1.0).cgColor)
ctx.addArc(center: CGPoint(x: 512, y: 420), radius: 130, startAngle: .pi * 0.25, endAngle: .pi * 0.75, clockwise: false)
ctx.strokePath()

ctx.setStrokeColor(NSColor(calibratedRed: 0.99, green: 0.90, blue: 0.54, alpha: 0.85).cgColor)
ctx.addArc(center: CGPoint(x: 512, y: 420), radius: 205, startAngle: .pi * 0.27, endAngle: .pi * 0.73, clockwise: false)
ctx.strokePath()

// Center dot
ctx.setFillColor(NSColor(calibratedRed: 0.96, green: 0.62, blue: 0.04, alpha: 1.0).cgColor)
ctx.fillEllipse(in: CGRect(x: 474, y: 382, width: 76, height: 76))

NSGraphicsContext.restoreGraphicsState()

guard let pngData = rep.representation(using: .png, properties: [:]) else {
  fatalError("Failed PNG encoding")
}
try pngData.write(to: URL(fileURLWithPath: outPath))
SWIFT

swift "$WORK_DIR/render.swift" "$BASE_PNG"

for sz in 16 32 128 256 512; do
  sips -z "$sz" "$sz" "$BASE_PNG" --out "$ICONSET_DIR/icon_${sz}x${sz}.png" >/dev/null
  double=$((sz * 2))
  sips -z "$double" "$double" "$BASE_PNG" --out "$ICONSET_DIR/icon_${sz}x${sz}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$OUT_ICNS"
echo "Generated icon at $OUT_ICNS"
