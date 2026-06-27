# Changelog

## 0.3.0

- Upgrade to `dart_mcp` ^0.5.1. `connectStdio` now spawns the server process and
  bridges its stdio via `stdioChannel` (the client no longer launches it
  internally); the process is killed on `close()`. Public API unchanged.

## 0.2.0

Initial release — Model Context Protocol (MCP) tools over the official
`dart_mcp` client.

- `McpToolset.connectStdio(...)` launches an MCP server subprocess and connects
  over stdio; `McpToolset.fromChannel(...)` connects over any
  `StreamChannel<String>` (in-process servers, custom transports).
- Each MCP tool is wrapped as an Akashi `Tool`: its JSON-Schema input passes
  straight to the model, and calling it proxies a `tools/call`. Tools the server
  flags with a `destructiveHint` are surfaced as needing approval.
- `McpToolset.close()` shuts the connection (and any spawned process) down.
- Offline test against an in-process `dart_mcp` server driven through an agent.
