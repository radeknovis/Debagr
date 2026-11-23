#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_ICNS="${1:-$ROOT_DIR/dist/AppIcon.icns}"
OUT_PNG="${2:-}"

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

let colorSpace = CGColorSpaceCreateDeviceRGB()

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
  CGColor(colorSpace: colorSpace, components: [r / 255.0, g / 255.0, b / 255.0, a])!
}

// 1. macOS squircle geometry + ambient dock shadow
let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: 188, yRadius: 188)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 32, color: rgba(4, 9, 20, 0.38))
NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.16, alpha: 1.0).setFill()
squirclePath.fill()
ctx.restoreGState()

// Clip interior layers to squircle
ctx.saveGState()
squirclePath.addClip()

// Base deep navy -> teal atmospheric gradient (top-left to bottom-right)
let bgColors = [rgba(11, 20, 38), rgba(16, 36, 66), rgba(12, 51, 71)] as CFArray
if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.52, 1.0]) {
  ctx.drawLinearGradient(
    bgGradient,
    start: CGPoint(x: 100, y: 924),
    end: CGPoint(x: 924, y: 100),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
  )
}

// Soft cobalt ambient glow (upper-left)
if let cobaltGlow = CGGradient(
  colorsSpace: colorSpace,
  colors: [rgba(37, 99, 235, 0.45), rgba(37, 99, 235, 0.0)] as CFArray,
  locations: [0.0, 1.0]
) {
  ctx.drawRadialGradient(
    cobaltGlow,
    startCenter: CGPoint(x: 245, y: 805),
    startRadius: 0,
    endCenter: CGPoint(x: 245, y: 805),
    endRadius: 560,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
  )
}

// Luminous teal-emerald glow (lower-right)
if let tealGlow = CGGradient(
  colorsSpace: colorSpace,
  colors: [rgba(20, 184, 166, 0.36), rgba(20, 184, 166, 0.0)] as CFArray,
  locations: [0.0, 1.0]
) {
  ctx.drawRadialGradient(
    tealGlow,
    startCenter: CGPoint(x: 785, y: 235),
    startRadius: 0,
    endCenter: CGPoint(x: 785, y: 235),
    endRadius: 520,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
  )
}

// Subtle precision radar rings inside background
let radarCenter = CGPoint(x: 512, y: 495)
let rings: [(CGFloat, CGFloat, Bool)] = [
  (235, 0.11, false),
  (318, 0.08, true),
  (402, 0.055, false),
]
for (radius, alpha, dashed) in rings {
  ctx.saveGState()
  ctx.setStrokeColor(rgba(165, 243, 252, alpha))
  ctx.setLineWidth(2.5)
  if dashed {
    ctx.setLineDash(phase: 0, lengths: [12, 14])
  }
  ctx.addEllipse(
    in: CGRect(
      x: radarCenter.x - radius,
      y: radarCenter.y - radius,
      width: radius * 2,
      height: radius * 2
    )
  )
  ctx.strokePath()
  ctx.restoreGState()
}

// Inner specular squircle rim
ctx.saveGState()
let rimRect = squircleRect.insetBy(dx: 2, dy: 2)
let rimCGPath = CGPath(roundedRect: rimRect, cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.addPath(rimCGPath)
ctx.setLineWidth(4)
ctx.replacePathWithStrokedPath()
ctx.clip()
if let rimGrad = CGGradient(
  colorsSpace: colorSpace,
  colors: [rgba(255, 255, 255, 0.30), rgba(255, 255, 255, 0.05)] as CFArray,
  locations: [0.0, 1.0]
) {
  ctx.drawLinearGradient(
    rimGrad,
    start: CGPoint(x: 512, y: 924),
    end: CGPoint(x: 512, y: 100),
    options: []
  )
}
ctx.restoreGState()

// 2. Elevated titanium iPhone silhouette
let phoneRect = CGRect(x: 316, y: 204, width: 392, height: 616)
let phonePath = NSBezierPath(roundedRect: phoneRect, xRadius: 82, yRadius: 82)

// Phone drop shadow
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -20), blur: 36, color: rgba(3, 8, 18, 0.56))
NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.18, alpha: 1.0).setFill()
phonePath.fill()
ctx.restoreGState()

// Brushed titanium outer bezel gradient fill
ctx.saveGState()
phonePath.addClip()
if let bezelGrad = CGGradient(
  colorsSpace: colorSpace,
  colors: [rgba(226, 238, 255), rgba(148, 173, 206), rgba(92, 118, 152)] as CFArray,
  locations: [0.0, 0.5, 1.0]
) {
  ctx.drawLinearGradient(
    bezelGrad,
    start: CGPoint(x: 316, y: 820),
    end: CGPoint(x: 708, y: 204),
    options: []
  )
}
ctx.restoreGState()

// Dark obsidian glass screen inside titanium bezel
let screenRect = phoneRect.insetBy(dx: 16, dy: 16)
let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: 66, yRadius: 66)

ctx.saveGState()
screenPath.addClip()
if let screenGrad = CGGradient(
  colorsSpace: colorSpace,
  colors: [rgba(10, 17, 32), rgba(14, 26, 48), rgba(11, 35, 52)] as CFArray,
  locations: [0.0, 0.55, 1.0]
) {
  ctx.drawLinearGradient(
    screenGrad,
    start: CGPoint(x: 512, y: 804),
    end: CGPoint(x: 512, y: 220),
    options: []
  )
}

// Inner luminous wireless glow behind signal arcs
let beaconCenter = CGPoint(x: 512, y: 422)
if let beaconGlow = CGGradient(
  colorsSpace: colorSpace,
  colors: [rgba(45, 212, 191, 0.34), rgba(56, 189, 248, 0.12), rgba(10, 17, 32, 0.0)] as CFArray,
  locations: [0.0, 0.5, 1.0]
) {
  ctx.drawRadialGradient(
    beaconGlow,
    startCenter: CGPoint(x: 512, y: 492),
    startRadius: 0,
    endCenter: CGPoint(x: 512, y: 492),
    endRadius: 235,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
  )
}

// Glass reflection sheen across upper-left of screen
if let sheenGrad = CGGradient(
  colorsSpace: colorSpace,
  colors: [rgba(255, 255, 255, 0.10), rgba(255, 255, 255, 0.0)] as CFArray,
  locations: [0.0, 1.0]
) {
  ctx.saveGState()
  ctx.move(to: CGPoint(x: 332, y: 804))
  ctx.addLine(to: CGPoint(x: 692, y: 804))
  ctx.addLine(to: CGPoint(x: 332, y: 470))
  ctx.closePath()
  ctx.clip()
  ctx.drawLinearGradient(
    sheenGrad,
    start: CGPoint(x: 332, y: 804),
    end: CGPoint(x: 540, y: 580),
    options: []
  )
  ctx.restoreGState()
}

// Dynamic Island pill at top & home indicator pill at bottom
let islandRect = CGRect(x: 512 - 60, y: 756, width: 120, height: 26)
let islandPath = NSBezierPath(roundedRect: islandRect, xRadius: 13, yRadius: 13)
NSColor(calibratedRed: 0.02, green: 0.04, blue: 0.08, alpha: 0.96).setFill()
islandPath.fill()

let homeRect = CGRect(x: 512 - 58, y: 242, width: 116, height: 9)
let homePath = NSBezierPath(roundedRect: homeRect, xRadius: 4.5, yRadius: 4.5)
NSColor(calibratedWhite: 1.0, alpha: 0.28).setFill()
homePath.fill()

// 3. Luminous wireless bridge waves & core orb
ctx.setLineCap(.round)

let arcSpecs: [(CGFloat, CGFloat, CGColor)] = [
  (92, 27, rgba(56, 189, 248, 0.98)),
  (150, 24, rgba(52, 211, 153, 0.94)),
  (208, 21, rgba(167, 243, 208, 0.84)),
]

for (radius, width, color) in arcSpecs {
  ctx.saveGState()
  ctx.setShadow(offset: .zero, blur: 18, color: color)
  ctx.setStrokeColor(color)
  ctx.setLineWidth(width)
  ctx.addArc(
    center: beaconCenter,
    radius: radius,
    startAngle: .pi * 0.26,
    endAngle: .pi * 0.74,
    clockwise: false
  )
  ctx.strokePath()
  ctx.restoreGState()
}

// Glowing emerald core orb + white specular core
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 24, color: rgba(52, 211, 153, 0.78))
let outerDot = CGRect(x: beaconCenter.x - 36, y: beaconCenter.y - 36, width: 72, height: 72)
ctx.setFillColor(rgba(52, 211, 153, 1.0))
ctx.fillEllipse(in: outerDot)
ctx.restoreGState()

let innerDot = CGRect(x: beaconCenter.x - 16, y: beaconCenter.y - 16, width: 32, height: 32)
ctx.setFillColor(rgba(236, 253, 245, 0.96))
ctx.fillEllipse(in: innerDot)

ctx.restoreGState()  // end screen clip

// Subtle inner bezel stroke defining the obsidian glass against titanium rim
ctx.setStrokeColor(rgba(255, 255, 255, 0.14))
ctx.setLineWidth(2)
screenPath.stroke()

ctx.restoreGState()  // end squircle clip

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

if [[ -n "$OUT_PNG" ]]; then
  mkdir -p "$(dirname "$OUT_PNG")"
  sips -z 512 512 "$BASE_PNG" --out "$OUT_PNG" >/dev/null
  echo "Generated 512x512 PNG icon at $OUT_PNG"
fi
