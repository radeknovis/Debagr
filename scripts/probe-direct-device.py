"""Experimental direct lockdown probe; reuse existing trust, never request new pairing.

Run with: uv run --python 3.13 --with pymobiledevice3==11.17.0
  scripts/probe-direct-device.py --host DEVICE_TAILSCALE_IP --udid DEVICE_UDID
"""

import argparse
import asyncio
import ipaddress
import json
from pathlib import Path

from pymobiledevice3.lockdown import create_using_tcp
from pymobiledevice3.pair_records import get_preferred_pair_record
from pymobiledevice3.remote.tunnel_service import RemotePairingTunnelService
from pymobiledevice3.service_connection import ServiceConnection


async def probe(host, udid):
    # Probe protocol responses, not just SYN/ACK: VPN proxies may accept a TCP
    # connection before the underlying iOS service can be contacted.
    print(json.dumps({"stage": "remotepairing_handshake"}), flush=True)
    pairing = RemotePairingTunnelService(udid, host, 49152)
    try:
        async with asyncio.timeout(8):
            pairing._reader, pairing._writer = await asyncio.open_connection(host, 49152)
            await pairing._attempt_pair_verify()
        print(json.dumps({"stage": "remotepairing_responded"}), flush=True)
    except Exception as error:
        print(json.dumps({"stage": "remotepairing_no_response", "error_type": type(error).__name__}), flush=True)
    finally:
        await pairing.close()

    print(json.dumps({"stage": "lockdown_query_type"}), flush=True)
    connection = await ServiceConnection.create_using_tcp(host, 62078)
    try:
        async with asyncio.timeout(8):
            response = await connection.send_recv_plist({"Request": "QueryType", "Label": "Debagr"})
        if response.get("Type") != "com.apple.mobile.lockdown":
            raise RuntimeError("Unexpected service on lockdown port")
        print(json.dumps({"stage": "lockdown_responded"}), flush=True)
    finally:
        await connection.close()

    # Retrieve the original Mac's record via usbmuxd; never log or export its keys.
    print(json.dumps({"stage": "loading_existing_pairing"}), flush=True)
    record = await get_preferred_pair_record(udid, Path.home() / ".pymobiledevice3")
    if record is None:
        raise RuntimeError("No existing pairing record is accessible on this Build Server")
    print(json.dumps({"stage": "connecting_lockdown"}), flush=True)
    client = await create_using_tcp(host, identifier=udid, pair_record=record, autopair=False)
    async with client:
        if client.udid != udid:
            raise RuntimeError("Connected device does not match the selected UDID")
        if not client.paired:
            raise RuntimeError("The device rejected the existing Build Server pairing")
        print(json.dumps({"stage": "authenticated_lockdown", "os": client.product_version}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", required=True)
    parser.add_argument("--udid", required=True)
    args = parser.parse_args()
    if ipaddress.ip_address(args.host) not in ipaddress.ip_network("100.64.0.0/10"):
        parser.error("--host must be the Target Device's Tailscale IPv4 address")
    try:
        asyncio.run(asyncio.wait_for(probe(args.host, args.udid), timeout=20))
    except Exception as error:
        # Error strings from protocol libraries may include pairing data.
        print(json.dumps({"stage": "failed", "error_type": type(error).__name__}))
        raise SystemExit(1)
