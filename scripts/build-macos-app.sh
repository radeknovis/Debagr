#!/bin/zsh
set -euo pipefail

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
configuration="${1:-release}"
app_directory="$project_directory/Debagr.app"
binary_path="$project_directory/.build/$configuration/debagr"
signing_identity="${CODESIGN_IDENTITY:--}"
version="${VERSION:-0.2.0}"
build_number="${BUILD_NUMBER:-1}"
staging_directory="$(mktemp -d "$project_directory/.debagr-package.XXXXXX")"
staged_app="$staging_directory/Debagr.app"

trap 'rm -rf "$staging_directory"' EXIT

case "$configuration" in
  debug|release) ;;
  *)
    print -u2 "Configuration must be debug or release."
    exit 2
    ;;
esac

cd "$project_directory"
swift build -c "$configuration" 2>&1 | xcsift -f toon -w -e -E

mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_path" "$staged_app/Contents/MacOS/Debagr"
cp "$project_directory/.build/$configuration/USBIPProbe" "$staged_app/Contents/MacOS/USBIPProbe"
cp "docs/usbip.md" "$staged_app/Contents/Resources/USB-IP-Setup.md"
cp "Packaging/Debagr.app/Contents/Info.plist" "$staged_app/Contents/Info.plist"
cp "Packaging/Resources/AppIcon.icns" "$staged_app/Contents/Resources/AppIcon.icns"
mkdir -p "$staged_app/Contents/Resources/Skills"
cp -R "Skills/debagr-deploy" "$staged_app/Contents/Resources/Skills/debagr-deploy"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$staged_app/Contents/Info.plist"

if [[ -n "${DEBAGR_WEBSITE_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :DebagrWebsiteURL string $DEBAGR_WEBSITE_URL" "$staged_app/Contents/Info.plist"
fi
if [[ -n "${DEBAGR_SUPPORT_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :DebagrSupportURL string $DEBAGR_SUPPORT_URL" "$staged_app/Contents/Info.plist"
fi

signing_arguments=(--force --options runtime --sign "$signing_identity")
if [[ "$signing_identity" != "-" ]]; then
  signing_arguments+=(--timestamp)
fi
codesign "${signing_arguments[@]}" "$staged_app/Contents/MacOS/USBIPProbe"
codesign "${signing_arguments[@]}" "$staged_app"
codesign --verify --deep --strict --verbose=2 "$staged_app"
plutil -lint "$staged_app/Contents/Info.plist"

rm -rf "$app_directory"
mv "$staged_app" "$app_directory"
print "Packaged $app_directory ($version, build $build_number)"
