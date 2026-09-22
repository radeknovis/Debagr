# Execute deployments on the paired build server

Debagr executes Apple device operations on the Mac that owns the pairing relationship and accepts remote invocations through existing SSH access. We rejected projecting RemotePairing into another Mac because Apple pairing is host-specific and CoreDevice negotiates scoped link-local networking that a macOS layer-4 relay cannot carry; callers therefore never need the Target Device to appear locally.
