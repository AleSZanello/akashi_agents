import 'dart:convert';

import 'package:akashi/akashi.dart';
import 'package:akashi_openai/akashi_openai.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openai_dart/openai_dart.dart' as o;
import 'package:test/test.dart';

o.OpenAIClient _client({http.Client? httpClient}) => o.OpenAIClient(
  config: o.OpenAIConfig(authProvider: o.ApiKeyProvider('test-key')),
  httpClient: httpClient ?? MockClient((_) async => http.Response('{}', 200)),
);

String _sse(Map<String, dynamic> event) => 'data: ${jsonEncode(event)}\n\n';

void main() {
  group('OpenAIModel.stream', () {
    test('reassembles index-keyed tool-call argument deltas', () async {
      final body = [
        _sse({
          'choices': [
            {
              'index': 0,
              'delta': {'role': 'assistant', 'content': ''},
            },
          ],
        }),
        _sse({
          'choices': [
            {
              'index': 0,
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_1',
                    'type': 'function',
                    'function': {'name': 'get_weather', 'arguments': '{"ci'},
                  },
                ],
              },
            },
          ],
        }),
        _sse({
          'choices': [
            {
              'index': 0,
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': 'ty":"Oslo"}'},
                  },
                ],
              },
            },
          ],
        }),
        _sse({
          'choices': [
            {
              'index': 0,
              'delta': <String, dynamic>{},
              'finish_reason': 'tool_calls',
            },
          ],
        }),
        'data: [DONE]\n\n',
      ].join();

      final model = OpenAIModel(
        client: _client(
          httpClient: MockClient.streaming((request, bodyStream) async {
            return http.StreamedResponse(
              Stream.value(utf8.encode(body)),
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          }),
        ),
        modelId: 'gpt-4o',
      );

      final parts = await model
          .stream(ModelRequest(messages: [UserMessage.text('weather?')]))
          .toList();

      final start = parts.whereType<ToolCallStartPart>().single;
      expect(start.toolName, 'get_weather');
      expect(start.toolCallId, 'call_1');
      final args = parts
          .whereType<ToolCallDeltaPart>()
          .map((p) => p.argsDelta)
          .join();
      expect(jsonDecode(args), {'city': 'Oslo'});
    });
  });

  group('OpenAIModel.generate', () {
    test('normalizes text and tool calls', () async {
      final completion = {
        'id': 'c1',
        'object': 'chat.completion',
        'model': 'gpt-4o',
        'choices': [
          {
            'index': 0,
            'message': {
              'role': 'assistant',
              'content': 'Bring a coat.',
              'tool_calls': [
                {
                  'id': 'call_1',
                  'type': 'function',
                  'function': {
                    'name': 'get_weather',
                    'arguments': '{"city":"Oslo"}',
                  },
                },
              ],
            },
            'finish_reason': 'tool_calls',
          },
        ],
        'usage': {
          'prompt_tokens': 5,
          'completion_tokens': 7,
          'total_tokens': 12,
        },
      };
      final model = OpenAIModel(
        client: _client(
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode(completion),
              200,
              headers: {'content-type': 'application/json'},
            ),
          ),
        ),
        modelId: 'gpt-4o',
      );

      final response = await model.generate(
        ModelRequest(messages: [UserMessage.text('weather?')]),
      );

      expect(response.message.text, 'Bring a coat.');
      final call = response.message.toolCalls.single;
      expect(call.toolName, 'get_weather');
      expect(call.input, {'city': 'Oslo'});
      expect(response.usage.inputTokens, 5);
      expect(response.usage.outputTokens, 7);
    });
  });

  group('OpenAIModel request mapping', () {
    test('maps responseFormat and toolChoice', () async {
      final bodies = <Map<String, dynamic>>[];
      final mock = MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'id': 'c',
            'object': 'chat.completion',
            'model': 'm',
            'choices': <Object?>[],
          }),
          200,
        );
      });
      final model = OpenAIModel(
        client: _client(httpClient: mock),
        modelId: 'm',
      );
      final schema = <String, Object?>{
        'type': 'object',
        'properties': {
          'x': {'type': 'string'},
        },
      };

      await model.generate(
        ModelRequest(
          messages: [UserMessage.text('hi')],
          responseFormat: JsonResponseFormat(schema, schemaName: 'out'),
          toolChoice: const ToolChoice.tool('get_weather'),
        ),
      );

      final body = bodies.single;
      final format = body['response_format'] as Map<String, dynamic>;
      expect(format['type'], 'json_schema');
      expect((format['json_schema'] as Map<String, dynamic>)['schema'], schema);
      final choice = body['tool_choice'] as Map<String, dynamic>;
      expect(
        (choice['function'] as Map<String, dynamic>)['name'],
        'get_weather',
      );
    });
  });

  group('OpenAIEmbeddingModel', () {
    test('returns one vector per input, ordered by index', () async {
      final response = {
        'object': 'list',
        'model': 'text-embedding-3-small',
        'data': [
          {
            'object': 'embedding',
            'index': 1,
            'embedding': [0.3, 0.4],
          },
          {
            'object': 'embedding',
            'index': 0,
            'embedding': [0.1, 0.2],
          },
        ],
      };
      final model = OpenAIEmbeddingModel(
        client: _client(
          httpClient: MockClient(
            (_) async => http.Response(jsonEncode(response), 200),
          ),
        ),
        modelId: 'text-embedding-3-small',
      );

      final vectors = await model.embed(['a', 'b']);

      expect(vectors, hasLength(2));
      expect(vectors[0], [0.1, 0.2]);
      expect(vectors[1], [0.3, 0.4]);
    });
  });
}
