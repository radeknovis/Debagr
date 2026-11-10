#!/bin/bash
set -euo pipefail
# Keep release tools independent of mutable Homebrew formulae.
version=1.7.4
checksum=d3537432e10915d86ad3f6fee212ea9f4b72b932394460216570ab1a1150dd5e
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"
: "${GITHUB_PATH:?GITHUB_PATH is required}"
: "${GITHUB_ENV:?GITHUB_ENV is required}"
[[ "$(uname -m)" == arm64 ]] || { echo 'This release toolchain requires an Apple-silicon runner' >&2; exit 1; }
selected=
for app in /Applications/Xcode*.app; do
  if [[ "$(DEVELOPER_DIR="$app/Contents/Developer" xcodebuild -version 2>/dev/null)" == $'Xcode 26.6\nBuild version 17F113' ]]; then
    selected="$app/Contents/Developer"
    break
  fi
done
[[ -n "$selected" ]] || { echo 'Required hosted Xcode 26.6 (17F113) is unavailable' >&2; exit 1; }
printf 'DEVELOPER_DIR=%s\n' "$selected" >> "$GITHUB_ENV"
tools="$RUNNER_TEMP/debagr-tools"
mkdir -p "$tools"
archive="$tools/xcsift.tar.gz"
curl --fail --location --silent --show-error "https://github.com/ldomaradzki/xcsift/releases/download/v$version/xcsift-v$version-macos-arm64.tar.gz" -o "$archive"
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c -
tar -xzf "$archive" -C "$tools"
chmod +x "$tools/xcsift"
"$tools/xcsift" --version
printf '%s\n' "$tools" >> "$GITHUB_PATH"
