import 'dart:convert';

import 'package:akashi/akashi.dart';
import 'package:akashi_anthropic/akashi_anthropic.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as a;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

a.AnthropicClient _client(http.Client mock) => a.AnthropicClient(
  config: a.AnthropicConfig(authProvider: a.ApiKeyProvider('test-key')),
  httpClient: mock,
);

String _sse(Map<String, dynamic> event) => 'data: ${jsonEncode(event)}\n\n';

void main() {
  group('ClaudeModel.stream', () {
    test('surfaces thinking (with signature) and tool_use blocks', () async {
      final body = [
        _sse({
          'type': 'message_start',
          'message': {
            'id': 'm1',
            'type': 'message',
            'role': 'assistant',
            'model': 'claude',
            'content': <Object?>[],
            'usage': {'input_tokens': 5, 'output_tokens': 0},
          },
        }),
        _sse({
          'type': 'content_block_start',
          'index': 0,
          'content_block': {
            'type': 'thinking',
            'thinking': '',
            'signature': '',
          },
        }),
        _sse({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'thinking_delta', 'thinking': 'Let me check.'},
        }),
        _sse({
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'signature_delta', 'signature': 'sig-abc'},
        }),
        _sse({
          'type': 'content_block_start',
          'index': 1,
          'content_block': {
            'type': 'tool_use',
            'id': 'tool_1',
            'name': 'get_weather',
            'input': <String, dynamic>{},
          },
        }),
        _sse({
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"city"'},
        }),
        _sse({
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': ':"Oslo"}'},
        }),
        _sse({
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
          'usage': {'input_tokens': 5, 'output_tokens': 12},
        }),
      ].join();

      final model = ClaudeModel(
        client: _client(
          MockClient.streaming((request, bodyStream) async {
            return http.StreamedResponse(
              Stream.value(utf8.encode(body)),
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          }),
        ),
        modelId: 'claude-sonnet-4-5',
      );

      final parts = await model
          .stream(ModelRequest(messages: [UserMessage.text('weather?')]))
          .toList();

      final reasoning = parts
          .whereType<ReasoningDeltaPart>()
          .map((p) => p.text)
          .join();
      expect(reasoning, 'Let me check.');
      expect(
        parts.whereType<ReasoningDeltaPart>().any(
          (p) => p.signature == 'sig-abc',
        ),
        isTrue,
      );

      final start = parts.whereType<ToolCallStartPart>().single;
      expect(start.toolName, 'get_weather');
      expect(start.toolCallId, 'tool_1');
      final args = parts
          .whereType<ToolCallDeltaPart>()
          .map((p) => p.argsDelta)
          .join();
      expect(jsonDecode(args), {'city': 'Oslo'});

      final usage = parts.whereType<UsagePart>().single.usage;
      expect(usage.inputTokens, 5);
      expect(usage.outputTokens, 12);
    });
  });

  group('ClaudeModel request mapping', () {
    test('sets system, tools, tool_choice, and a default max_tokens', () async {
      final bodies = <Map<String, dynamic>>[];
      final mock = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'id': 'm',
            'type': 'message',
            'role': 'assistant',
            'model': 'claude',
            'content': [
              {'type': 'text', 'text': 'ok'},
            ],
            'stop_reason': 'end_turn',
            'usage': {'input_tokens': 3, 'output_tokens': 4},
          }),
          200,
        );
      });
      final model = ClaudeModel(
        client: _client(mock),
        modelId: 'claude-sonnet-4-5',
      );

      final response = await model.generate(
        ModelRequest(
          messages: [
            const SystemMessage('You are helpful.'),
            UserMessage.text('hi'),
          ],
          tools: const [
            ToolSpec(
              name: 'get_weather',
              description: 'Weather.',
              inputJsonSchema: {'type': 'object'},
            ),
          ],
          toolChoice: const ToolChoice.tool('get_weather'),
        ),
      );

      expect(response.message.text, 'ok');
      final body = bodies.single;
      expect(body['system'], 'You are helpful.');
      expect(body['max_tokens'], 4096);
      expect((body['tool_choice'] as Map<String, dynamic>)['type'], 'tool');
      expect(
        (body['tool_choice'] as Map<String, dynamic>)['name'],
        'get_weather',
      );
      expect((body['tools'] as List<dynamic>).single['name'], 'get_weather');
    });
  });
}
