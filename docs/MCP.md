# Optional local MCP interface

The unreleased source branch can run `debagr --mcp` on the paired Mac. It exposes
stdio JSON-RPC only: no TCP listener, authentication service or public endpoint.
Use the same logged-in Mac user who owns the Apple pairing. Existing SSH may
launch the command remotely; the artifact path still belongs to that Mac.

Configure an MCP client to execute `/Applications/Debagr.app/Contents/MacOS/Debagr`
with arguments `["--mcp"]`. This is optional; the ordinary JSON CLI and deployment
skill remain available. Do not configure a published 0.2.0 binary as an MCP server;
it does not implement this source-branch feature.

Tools: `devices`, `status`, `diagnose`, `installed_apps`, `launch_app`, `deploy_app`.
All except devices require an explicit deviceIdentifier. Launch also needs a
bundleIdentifier; deploy needs an absolute appPath and performs installation only.
Use launch_app separately for an authorized launch. Clients should ask for user
approval before app mutation. The server never changes pairing or signing.
Commands use argument arrays without a shell and share CLI validation and errors.

The protocol is [MCP 2025-03-26 stdio](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports):
initialize, send notifications/initialized, then tools/list or tools/call.
Tool failures return isError with the CLI result as text. Requests run serially;
there is no mid-operation cancellation or streaming progress. A command deadline
bounds each child; close the session after pending work completes.

Validated locally: initialization, discovery, a real read-only devices call,
argument rejection and preservation of argument boundaries. This is protocol and
CLI evidence, not remote-device installation/launch acceptance.
