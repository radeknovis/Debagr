# Execute deployments on the paired build server

Clarification: this decision does not require the Target Device to stay on the
Build Server's LAN. The device must be able to roam with Tailscale running on
both endpoints. Direct-device Tailscale transport has prior iPhone evidence across separate Wi-Fi networks; fresh acceptance remains required. Cellular-only operation is unsupported. The earlier two-Mac experiment does not establish that this
same-pairing, direct-device path is impossible.

Debagr executes Apple device operations on the Mac that owns the pairing relationship and accepts remote invocations through existing SSH access. We rejected projecting RemotePairing into another Mac because Apple pairing is host-specific and CoreDevice negotiates scoped link-local networking that a macOS layer-4 relay cannot carry; callers therefore never need the Target Device to appear locally.
