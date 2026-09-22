#!/bin/zsh
set -euo pipefail

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
version="${VERSION:?Set VERSION, for example VERSION=1.0.0}"
build_number="${BUILD_NUMBER:?Set BUILD_NUMBER, for example BUILD_NUMBER=42}"
signing_identity="${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to a Developer ID Application identity}"
notary_profile="${NOTARY_PROFILE:?Set NOTARY_PROFILE to an xcrun notarytool keychain profile}"
dist_directory="$project_directory/dist"
dmg_path="$dist_directory/Debagr-$version.dmg"
staging_directory="$(mktemp -d "$project_directory/.debagr-release.XXXXXX")"

trap 'rm -rf "$staging_directory"' EXIT

if [[ "$signing_identity" != *"Developer ID Application"* ]]; then
  print -u2 "CODESIGN_IDENTITY must be a Developer ID Application identity."
  exit 2
fi

cd "$project_directory"
if [[ "${ALLOW_DIRTY_RELEASE:-0}" != "1" && -n "$(git status --porcelain)" ]]; then
  print -u2 "Release requires a clean working tree. Set ALLOW_DIRTY_RELEASE=1 only for a deliberate local rehearsal."
  exit 2
fi
swift-format lint --recursive Sources Tests
swift test 2>&1 | xcsift -f toon -w -e -E
./scripts/build-macos-app.sh release

mkdir -p "$dist_directory" "$staging_directory/image"
cp -R "Debagr.app" "$staging_directory/image/Debagr.app"
ln -s /Applications "$staging_directory/image/Applications"
hdiutil create \
  -volname "Debagr" \
  -srcfolder "$staging_directory/image" \
  -ov \
  -format UDZO \
  "$dmg_path"

xcrun notarytool submit "$dmg_path" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"
shasum -a 256 "$dmg_path" > "$dmg_path.sha256"

print "Release ready: $dmg_path"
