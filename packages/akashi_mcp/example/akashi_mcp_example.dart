// Connects to an MCP server over stdio and lists the tools it exposes (which
// you can then hand to a ToolLoopAgent).
//
// Usage: dart run example/akashi_mcp_example.dart <command> [args...]
//   e.g. dart run example/akashi_mcp_example.dart \
//          npx -y @modelcontextprotocol/server-everything
import 'dart:io';

import 'package:akashi_mcp/akashi_mcp.dart';

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln('Usage: akashi_mcp_example <command> [args...]');
    exit(64);
  }

  final toolset = await McpToolset.connectStdio<Object?>(
    command: argv.first,
    args: argv.skip(1).toList(),
  );
  try {
    stdout.writeln('Discovered ${toolset.tools.length} MCP tool(s):');
    for (final tool in toolset.tools) {
      stdout.writeln('  - ${tool.name}: ${tool.description}');
    }
    // Then: final agent = ToolLoopAgent(model: model, tools: toolset.tools);
  } finally {
    await toolset.close();
  }
}
