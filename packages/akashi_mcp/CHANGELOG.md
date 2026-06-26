# Changelog

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
