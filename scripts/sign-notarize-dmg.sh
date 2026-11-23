#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Debagr.app"
DMG_PATH="$DIST_DIR/Debagr-${VERSION}-arm64.dmg"
CASK_OUT="$DIST_DIR/debagr.rb"

MODE="${1:-}"

if [[ ! -d "$APP_DIR" ]]; then
  "$ROOT_DIR/scripts/bundle-app.sh"
fi

if [[ "$MODE" == "--adhoc" ]]; then
  echo "Creating ad-hoc signed DMG (for local/CI smoke verification)..."
  codesign --force --sign - --entitlements "$ROOT_DIR/packaging/Debagr.entitlements" "$APP_DIR"
else
  : "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION or pass --adhoc}"
  echo "Signing $APP_DIR with Developer ID ($DEVELOPER_ID_APPLICATION)..."
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --entitlements "$ROOT_DIR/packaging/Debagr.entitlements" \
    "$APP_DIR"
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"

  if [[ -n "${APPLE_NOTARY_PROFILE:-}" ]]; then
    APP_ZIP="$DIST_DIR/Debagr-${VERSION}-app.zip"
    rm -f "$APP_ZIP"
    ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP"
    echo "Submitting Debagr.app archive for Apple notarization..."
    xcrun notarytool submit "$APP_ZIP" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"
    spctl --assess --type execute --verbose "$APP_DIR"
    rm -f "$APP_ZIP"
  fi
fi

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
cp -R "$APP_DIR" "$STAGE_DIR/Debagr.app"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "Debagr ${VERSION}" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

if [[ "$MODE" != "--adhoc" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"
  if [[ -n "${APPLE_NOTARY_PROFILE:-}" ]]; then
    echo "Submitting $DMG_PATH for Apple notarization..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$APPLE_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
  else
    echo "APPLE_NOTARY_PROFILE not set; skipping notarization submission."
  fi
fi

SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
echo "$SHA256  $(basename "$DMG_PATH")" > "${DMG_PATH}.sha256"

sed -e "s/{{VERSION}}/$VERSION/g" -e "s/{{SHA256}}/$SHA256/g" \
  "$ROOT_DIR/packaging/homebrew/debagr.rb.template" > "$CASK_OUT"

echo "Created DMG: $DMG_PATH (sha256: $SHA256)"
echo "Generated Homebrew Cask: $CASK_OUT"
