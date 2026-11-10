#!/bin/zsh
set -euo pipefail

project_directory="$(cd "$(dirname "$0")/.." && pwd)"
version="${VERSION:?Set VERSION, for example VERSION=1.0.0}"
build_number="${BUILD_NUMBER:?Set BUILD_NUMBER, for example BUILD_NUMBER=42}"
signing_identity="${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to a Developer ID Application identity}"
notary_profile="${NOTARY_PROFILE:?Set NOTARY_PROFILE to an xcrun notarytool keychain profile}"
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$build_number" =~ '^[0-9]+$' ]]; then
  print -u2 "VERSION must be numeric major.minor.patch and BUILD_NUMBER must be numeric."
  exit 2
fi
dist_directory="$project_directory/dist"
dmg_path="$dist_directory/Debagr-$version.dmg"
staging_directory="$(mktemp -d "$project_directory/.debagr-release.XXXXXX")"

trap 'rm -rf "$staging_directory"' EXIT ZERR

if [[ "$signing_identity" != *"Developer ID Application"* ]]; then
  print -u2 "CODESIGN_IDENTITY must be a Developer ID Application identity."
  exit 2
fi

cd "$project_directory"
if [[ "$version" != "$(cat VERSION)" ]]; then
  print -u2 "VERSION must match the canonical source VERSION before signing."
  exit 2
fi
if [[ -e "$dmg_path" ]]; then
  print -u2 "Refusing to overwrite $dmg_path. Archive the previous release first."
  exit 2
fi
if [[ "${ALLOW_DIRTY_RELEASE:-0}" != "1" && -n "$(git status --porcelain)" ]]; then
  print -u2 "Release requires a clean working tree. Set ALLOW_DIRTY_RELEASE=1 only for a deliberate local rehearsal."
  exit 2
fi
xcrun swift-format lint --strict --recursive Sources Tests
swift test 2>&1 | xcsift -f toon -w -e -E
./scripts/build-macos-app.sh release
./scripts/verify-macos-app.sh

notary_arguments=(--keychain-profile "$notary_profile")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
  notary_arguments+=(--keychain "$NOTARY_KEYCHAIN")
fi

notarize() {
  local artifact="$1" label="$2" result submission_id notarization_status submit_exit=0
  result="$dist_directory/Debagr-$version-$label-submission.json"
  # A completed request can still be Invalid; preserve Apple's log before failing.
  xcrun notarytool submit "$artifact" "${notary_arguments[@]}" --wait --output-format json > "$result" || submit_exit=$?
  submission_id="$(/usr/bin/plutil -extract id raw -o - "$result")"
  xcrun notarytool log "$submission_id" "${notary_arguments[@]}" \
    "$dist_directory/Debagr-$version-$label-notary-log.json"
  notarization_status="$(/usr/bin/plutil -extract status raw -o - "$result")"
  if [[ "$notarization_status" != "Accepted" || "$submit_exit" != "0" ]]; then
    print -u2 "Apple did not accept $label ($notarization_status). Inspect the notarization log in dist/."
    return 1
  fi
}

mkdir -p "$dist_directory"
ditto -c -k --keepParent Debagr.app "$staging_directory/Debagr.zip"
notarize "$staging_directory/Debagr.zip" app
xcrun stapler staple Debagr.app
xcrun stapler validate Debagr.app
spctl --assess --type execute --verbose=2 Debagr.app

mkdir -p "$staging_directory/image"
cp -R "Debagr.app" "$staging_directory/image/Debagr.app"
ln -s /Applications "$staging_directory/image/Applications"
hdiutil create \
  -volname "Debagr" \
  -srcfolder "$staging_directory/image" \
  -ov \
  -format UDZO \
  "$staging_directory/Debagr.dmg"

codesign --force --sign "$signing_identity" --timestamp "$staging_directory/Debagr.dmg"
notarize "$staging_directory/Debagr.dmg" dmg
xcrun stapler staple "$staging_directory/Debagr.dmg"
xcrun stapler validate "$staging_directory/Debagr.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$staging_directory/Debagr.dmg"
mv "$staging_directory/Debagr.dmg" "$dmg_path"
(cd "$dist_directory" && shasum -a 256 "${dmg_path:t}" > "${dmg_path:t}.sha256")

print "Release ready: $dmg_path"
