#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Debagr.app"

echo "Building Debagr $VERSION (arm64 release)..."
swift build -c release --arch arm64 -Xswiftc -warnings-as-errors

BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/Debagr"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Expected built binary at $EXECUTABLE_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/Debagr"
chmod 755 "$APP_DIR/Contents/MacOS/Debagr"

sed "s/{{VERSION}}/$VERSION/g" "$ROOT_DIR/packaging/Info.plist.template" > "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

"$ROOT_DIR/scripts/generate-icon.sh" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Ad-hoc signature so local execution and smoke checks succeed cleanly;
# sign-notarize-dmg.sh applies Developer ID + Hardened Runtime when distributing.
codesign --force --sign - --entitlements "$ROOT_DIR/packaging/Debagr.entitlements" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "Bundled $APP_DIR successfully."
