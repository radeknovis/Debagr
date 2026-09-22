#!/bin/zsh
set -euo pipefail

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
app_directory="${1:-$project_directory/Debagr.app}"

test -x "$app_directory/Contents/MacOS/Debagr"
test -f "$app_directory/Contents/Resources/AppIcon.icns"
plutil -lint "$app_directory/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app_directory"
test "$(defaults read "$app_directory/Contents/Info" CFBundleIdentifier)" = "com.debagr.app"

print "Verified $app_directory"
