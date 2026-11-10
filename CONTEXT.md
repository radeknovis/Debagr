# Debagr Context

Debagr turns one Mac with Apple device trust into a deployment endpoint that
authorized people and automation can invoke remotely.

The central requirement is Target Device roaming: Tailscale runs directly on
both the Build Server and each iPhone/iPad. After initial Apple pairing, the
Target Device must remain deployable when it moves to a separate Wi-Fi
network. Remote invocation by a Caller alone does not satisfy this requirement.
Cellular-only operation is unsupported. No accompanying Mac or gateway is assumed. Remote install and launch remain
unverified until tested without USB or a shared local network.

## Language

**Pairing**:
The one-time Apple trust relationship between a Target Device and a Build Server.
_Avoid_: Registration, remote pairing

**Build Server**:
The Mac that owns Pairing and performs deployment operations against Target Devices.
_Avoid_: Client Mac, Paired Mac, gateway

**Caller**:
An authorized person, computer, CI job, or software agent that requests a Deployment.
_Avoid_: Client Mac, Developer Mac

**Target Device**:
A physical iPhone or iPad paired to the Build Server and intended to receive a build.
_Avoid_: Handset, remote device

**Artifact**:
A signed device `.app` available on the Build Server and eligible for installation on a Target Device.
_Avoid_: Payload, package

**Deployment**:
A confirmed installation of an Artifact on one explicit Target Device, optionally followed by launch.
_Avoid_: Connection, forwarding

**Remote Invocation**:
A Caller requesting a Deployment through the Build Server's existing remote-access controls.
_Avoid_: Remote Xcode, device sharing
