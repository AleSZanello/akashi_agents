import 'dart:async';

import 'package:akashi/akashi.dart';
import 'package:akashi_mcp/akashi_mcp.dart';
import 'package:dart_mcp/server.dart' as mcp;
import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';

/// A minimal in-process MCP server exposing a single `echo` tool.
final class _EchoServer extends mcp.MCPServer with mcp.ToolsSupport {
  _EchoServer(super.channel)
    : super.fromStreamChannel(
        implementation: mcp.Implementation(name: 'echo-server', version: '1'),
      );

  @override
  FutureOr<mcp.InitializeResult> initialize(mcp.InitializeRequest request) {
    registerTool(
      mcp.Tool(
        name: 'echo',
        description: 'Echoes the given text.',
        inputSchema: mcp.ObjectSchema(
          properties: {'text': mcp.Schema.string()},
          required: ['text'],
        ),
      ),
      (call) async => mcp.CallToolResult(
        content: <mcp.Content>[
          mcp.Content.text(text: 'echo: ${call.arguments?['text']}'),
        ],
      ),
    );
    return super.initialize(request);
  }
}

/// A scripted [LanguageModel]: turn 1 calls `echo`, turn 2 answers.
final class _ScriptedModel implements LanguageModel {
  _ScriptedModel(this._turns);

  final List<List<ModelStreamPart>> _turns;
  int _index = 0;

  @override
  String get providerId => 'fake';
  @override
  String get modelId => 'fake';

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    final turn =
        _index < _turns.length
            ? _turns[_index]
            : const [FinishPart(FinishReason.stop)];
    _index++;
    for (final part in turn) {
      yield part;
    }
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async =>
      throw UnimplementedError();
}

void main() {
  group('McpToolset', () {
    test('lists and calls an MCP tool through an agent', () async {
      final controller = StreamChannelController<String>();
      final server = _EchoServer(controller.local);
      addTearDown(server.shutdown);

      final toolset = await McpToolset.fromChannel<Object?>(controller.foreign);
      addTearDown(toolset.close);

      expect(toolset.tools.map((t) => t.name), contains('echo'));

      final model = _ScriptedModel([
        [
          const ToolCallCompletePart(
            toolCallId: 'c1',
            toolName: 'echo',
            input: {'text': 'hi'},
          ),
          const FinishPart(FinishReason.stop),
        ],
        [const TextDeltaPart('done'), const FinishPart(FinishReason.stop)],
      ]);
      final agent = ToolLoopAgent<Object?>(model: model, tools: toolset.tools);

      final events = await agent.stream('go').toList();

      final result = events.whereType<ToolResult>().single.result;
      expect(result.isError, isFalse);
      expect(result.output, 'echo: hi');
      // The result was fed back to the model on the follow-up turn.
      expect(events.whereType<RunFinish>().single.text, 'done');
    });
  });
}
