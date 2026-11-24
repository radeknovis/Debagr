#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/Debagr.app"

FORCE_ADHOC=0
for arg in "$@"; do
  case "$arg" in
    --adhoc)
      FORCE_ADHOC=1
      ;;
    *)
      echo "Usage: $0 [--adhoc]" >&2
      exit 2
      ;;
  esac
done

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

EXPLICIT_IDENTITY=0
if [[ "$FORCE_ADHOC" -eq 1 ]] || [[ "${CODESIGN_IDENTITY:-}" == "-" ]] || ([[ -n "${CI:-}" ]] && [[ -z "${CODESIGN_IDENTITY:-}" ]] && [[ -z "${DEVELOPER_ID_APPLICATION:-}" ]]); then
  SIGN_IDENTITY="-"
  EXPLICIT_IDENTITY=1
elif [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  SIGN_IDENTITY="$CODESIGN_IDENTITY"
  EXPLICIT_IDENTITY=1
elif [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"
  EXPLICIT_IDENTITY=1
else
  AUTO_IDENTITY="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | awk '/Developer ID Application:/ && !/CSSMERR_TP_CERT_REVOKED/ { print $2; exit }' \
      || true
  )"
  if [[ -n "$AUTO_IDENTITY" ]]; then
    SIGN_IDENTITY="$AUTO_IDENTITY"
  else
    SIGN_IDENTITY="-"
  fi
fi

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  echo "Signing $APP_DIR with identity $SIGN_IDENTITY..."
  if codesign --force --options runtime --sign "$SIGN_IDENTITY" --entitlements "$ROOT_DIR/packaging/Debagr.entitlements" "$APP_DIR"; then
    echo "Signed $APP_DIR with certificate ($SIGN_IDENTITY)."
  elif [[ "$EXPLICIT_IDENTITY" -eq 1 ]]; then
    exit 1
  else
    echo "Warning: failed signing with auto-detected identity $SIGN_IDENTITY; falling back to ad-hoc signature." >&2
    codesign --force --sign - --entitlements "$ROOT_DIR/packaging/Debagr.entitlements" "$APP_DIR"
    echo "Signed $APP_DIR ad-hoc."
  fi
else
  codesign --force --sign - --entitlements "$ROOT_DIR/packaging/Debagr.entitlements" "$APP_DIR"
  echo "Signed $APP_DIR ad-hoc."
fi

codesign --verify --deep --strict "$APP_DIR"

echo "Bundled $APP_DIR successfully."
