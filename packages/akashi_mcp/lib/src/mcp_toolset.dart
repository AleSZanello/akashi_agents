import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:dart_mcp/client.dart' as mcp;
import 'package:dart_mcp/stdio.dart' as mcp_stdio;
import 'package:stream_channel/stream_channel.dart';

/// Connects to a Model Context Protocol (MCP) server and exposes its tools as
/// Akashi [Tool]s.
///
/// ```dart
/// final toolset = await McpToolset.connectStdio<MyDeps>(
///   command: 'npx',
///   args: ['-y', '@modelcontextprotocol/server-everything'],
/// );
/// final agent = ToolLoopAgent(model: model, tools: toolset.tools);
/// // ... later
/// await toolset.close();
/// ```
///
/// Each MCP tool's JSON-Schema input is passed straight through to the model,
/// and calling it proxies a `tools/call` to the server. Tools the server flags
/// with a `destructiveHint` annotation are surfaced as needing approval.
final class McpToolset<TDeps> {
  McpToolset._(this._client, this.connection, this.tools, [this._process]);

  final mcp.MCPClient _client;

  /// The spawned server process (stdio transport only); killed on [close].
  final Process? _process;

  /// The underlying MCP server connection.
  final mcp.ServerConnection connection;

  /// The MCP server's tools, wrapped as Akashi tools.
  final List<Tool<TDeps>> tools;

  /// Connect over an arbitrary [channel] of newline-free JSON-RPC strings
  /// (e.g. an in-process server, or a custom transport).
  static Future<McpToolset<TDeps>> fromChannel<TDeps>(
    StreamChannel<String> channel, {
    String clientName = 'akashi',
    String clientVersion = '0.2.0',
  }) async {
    final client = mcp.MCPClient(
      mcp.Implementation(name: clientName, version: clientVersion),
    );
    final connection = client.connectServer(channel);
    return _initialize<TDeps>(client, connection, clientName, clientVersion);
  }

  /// Launch an MCP server as a subprocess ([command] + [args]) and connect to
  /// it over stdio — the most common MCP transport.
  static Future<McpToolset<TDeps>> connectStdio<TDeps>({
    required String command,
    List<String> args = const [],
    String clientName = 'akashi',
    String clientVersion = '0.3.0',
  }) async {
    // dart_mcp 0.5 no longer spawns the process itself: start it and bridge its
    // stdout/stdin into a newline-delimited JSON-RPC channel.
    final process = await Process.start(command, args);
    final channel = mcp_stdio.stdioChannel(
      input: process.stdout,
      output: process.stdin,
    );
    final client = mcp.MCPClient(
      mcp.Implementation(name: clientName, version: clientVersion),
    );
    final connection = client.connectServer(channel);
    return _initialize<TDeps>(
      client,
      connection,
      clientName,
      clientVersion,
      process,
    );
  }

  static Future<McpToolset<TDeps>> _initialize<TDeps>(
    mcp.MCPClient client,
    mcp.ServerConnection connection,
    String clientName,
    String clientVersion, [
    Process? process,
  ]) async {
    await connection.initialize(
      mcp.InitializeRequest(
        protocolVersion: mcp.ProtocolVersion.latestSupported,
        capabilities: mcp.ClientCapabilities(),
        clientInfo: mcp.Implementation(
          name: clientName,
          version: clientVersion,
        ),
      ),
    );
    connection.notifyInitialized();
    final listing = await connection.listTools();
    final tools = [
      for (final tool in listing.tools) _wrap<TDeps>(connection, tool),
    ];
    return McpToolset._(client, connection, tools, process);
  }

  /// Shut down the connection (and, for stdio, the server process).
  Future<void> close() async {
    await _client.shutdown();
    _process?.kill();
  }
}

Tool<TDeps> _wrap<TDeps>(mcp.ServerConnection connection, mcp.Tool mcpTool) {
  final destructive = mcpTool.toolAnnotations?.destructiveHint ?? false;
  return tool<Map<String, Object?>, TDeps>(
    name: mcpTool.name,
    description: mcpTool.description ?? '',
    inputSchema: Schema.raw<Map<String, Object?>>(
      _asMap(mcpTool.inputSchema),
      (json) =>
          json is Map ? json.cast<String, Object?>() : <String, Object?>{},
    ),
    execute: (input, ctx) async {
      final result = await connection.callTool(
        mcp.CallToolRequest(name: mcpTool.name, arguments: input),
      );
      return _resultOutput(result);
    },
    needsApproval: destructive ? (input, ctx) => true : null,
  );
}

/// Flattens an MCP [mcp.CallToolResult] into a JSON-encodable value: a single
/// string when every block is text, otherwise the raw content blocks.
Object? _resultOutput(mcp.CallToolResult result) {
  final blocks = [for (final content in result.content) _asMap(content)];
  final allText = blocks.isNotEmpty && blocks.every((b) => b['type'] == 'text');
  if (allText) {
    return blocks.map((b) => b['text'] as String? ?? '').join('\n');
  }
  return blocks;
}

/// dart_mcp models are extension types over `Map<String, Object?>`; upcasting to
/// `Object?` exposes the underlying map at runtime.
Map<String, Object?> _asMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : <String, Object?>{};
