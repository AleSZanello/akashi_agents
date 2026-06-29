# akashi_mcp

**Model Context Protocol (MCP)** tools for the [Akashi](https://github.com/AleSZanello/akashi_agents)
agent framework. Connects to an MCP server via the official
[`dart_mcp`](https://pub.dev/packages/dart_mcp) client and exposes its tools as
Akashi `Tool`s an agent can call.

```dart
import 'package:akashi/akashi.dart';
import 'package:akashi_mcp/akashi_mcp.dart';

final toolset = await McpToolset.connectStdio(
  command: 'npx',
  args: ['-y', '@modelcontextprotocol/server-everything'],
);

final agent = ToolLoopAgent(model: model, tools: toolset.tools);
// ... run the agent ...
await toolset.close(); // shuts down the client and the server process
```

Each MCP tool becomes a normal Akashi tool — the agent calls it like any other,
and `akashi_mcp` round-trips the call to the MCP server and back.

See [`example/akashi_mcp_example.dart`](example/akashi_mcp_example.dart) for a
runnable stdio tool-discovery example.

## Status

v0.3.

## License

MIT.
