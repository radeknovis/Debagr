#!/bin/zsh
set -euo pipefail

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
app_directory="${1:-$project_directory/Debagr.app}"

test -x "$app_directory/Contents/MacOS/Debagr"
test -x "$app_directory/Contents/MacOS/USBIPProbe"
codesign --verify --strict "$app_directory/Contents/MacOS/USBIPProbe"
cmp "$project_directory/docs/usbip.md" "$app_directory/Contents/Resources/USB-IP-Setup.md"
"$app_directory/Contents/MacOS/Debagr" --usbip help >/dev/null
"$app_directory/Contents/MacOS/Debagr" --cable help >/dev/null
test -f "$app_directory/Contents/Resources/Cable-Sharing.md"
test -f "$app_directory/Contents/Resources/AppIcon.icns"
cmp "$project_directory/Marketing/site/preview-licence.txt" "$app_directory/Contents/Resources/Preview-Licence.txt"
test -f "$app_directory/Contents/Resources/Skills/debagr-deploy/SKILL.md"
plutil -lint "$app_directory/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app_directory"
test "$(defaults read "$app_directory/Contents/Info" CFBundleIdentifier)" = "com.debagr.app"

print "Verified $app_directory"
