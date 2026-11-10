#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: $0 <paired-mac-ssh-host> <tailscale-hostname> <device-udid>" >&2
  exit 64
fi

paired_host=$1
tailscale_host=$2
device_udid=$3
tailscale=${TAILSCALE_BIN:-}
if [ -z "$tailscale" ]; then
  for candidate in /opt/homebrew/bin/tailscale /usr/local/bin/tailscale /Applications/Tailscale.app/Contents/MacOS/Tailscale; do
    if [ -x "$candidate" ]; then tailscale=$candidate; break; fi
  done
fi

if [ ! -x "$tailscale" ]; then
  echo "TAILSCALE_NOT_FOUND: set TAILSCALE_BIN to the Tailscale CLI" >&2
  exit 1
fi

if ! "$tailscale" ping --timeout=5s --c=1 "$tailscale_host" >/dev/null; then
  echo "VPN_PEER_UNREACHABLE: connect both endpoints to Tailscale" >&2
  exit 2
fi

if ! ssh "$paired_host" xcrun devicectl device info lockState \
  --device "$device_udid" --timeout 10 >/dev/null 2>&1; then
  echo "PAIRED_HOST_CANNOT_USE_DEVICE: $device_udid" >&2
  exit 1
fi

attempt=1
while [ "$attempt" -le 3 ]; do
  if xcrun devicectl device info lockState --device "$device_udid" \
    --timeout 5 >/dev/null 2>&1; then
    echo "DIRECT_PATH_EXISTS: local devicectl reached $device_udid with Debagr off" >&2
    exit 2
  fi
  attempt=$((attempt + 1))
done

echo "READY: paired host can use the device and this Mac has no direct path"
