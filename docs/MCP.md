# Optional local MCP interface

Debagr 0.3.0 can run `debagr --mcp` on the paired Mac. It exposes stdio
JSON-RPC only: no TCP listener, authentication service or public endpoint.
Use the same logged-in Mac user who owns the Apple pairing. Existing SSH may
launch the command remotely; the artifact path still belongs to that Mac.

Configure an MCP client to execute `/Applications/Debagr.app/Contents/MacOS/Debagr`
with arguments `["--mcp"]`. This is optional; the ordinary JSON CLI and deployment
skill remain available. Debagr versions before 0.3.0 do not have `--mcp`; run
`--version` on the paired Mac to check.

Tools: `devices`, `status`, `diagnose`, `installed_apps`, `launch_app`, `deploy_app`.
All except devices require an explicit deviceIdentifier. Launch also needs a
bundleIdentifier; deploy needs an absolute appPath and performs installation only.
Use launch_app separately for an authorized launch. Status and diagnose wait up
to 30 seconds. Clients should ask for user approval before app mutation. The
server has no setup tool and never changes pairing or signing. Arguments are
strings; unknown fields and values that start with `-` are rejected. Commands
use argument arrays without a shell and share CLI validation and errors.

The protocol is [MCP 2025-03-26 stdio](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports):
initialize, send notifications/initialized, then tools/list or tools/call.
Tool failures return isError with the CLI result as text. Requests run serially;
there is no mid-operation cancellation or streaming progress. A 180-second
deadline bounds each child; close the session after pending work completes.

Validated locally: initialization, discovery, a real read-only devices call,
argument rejection and preservation of argument boundaries. This is protocol and
CLI evidence, not remote-device installation/launch acceptance.
