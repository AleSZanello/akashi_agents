import 'dart:convert';

import 'package:akashi/akashi.dart';
import 'package:akashi_google/akashi_google.dart';
import 'package:googleai_dart/googleai_dart.dart' as g;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

g.GoogleAIClient _client(http.Client mock) => g.GoogleAIClient(
      config: g.GoogleAIConfig(authProvider: g.ApiKeyProvider('test-key')),
      httpClient: mock,
    );

/// A mock that records each request body and replies with [response] JSON.
MockClient _capturing(
  List<Map<String, dynamic>> bodies,
  Map<String, dynamic> response,
) =>
    MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(jsonEncode(response), 200,
          headers: {'content-type': 'application/json'});
    });

void main() {
  group('GeminiModel.generate', () {
    test('normalizes text and function calls', () async {
      final mock = MockClient((request) async => http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'role': 'model',
                    'parts': [
                      {'text': 'Bring a coat.'},
                      {
                        'functionCall': {
                          'name': 'get_weather',
                          'args': {'city': 'Oslo'},
                        },
                      },
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
              'usageMetadata': {
                'promptTokenCount': 5,
                'candidatesTokenCount': 7,
              },
            }),
            200,
          ));
      final model = GeminiModel(client: _client(mock), modelId: 'gemini-x');

      final response = await model
          .generate(ModelRequest(messages: [UserMessage.text('weather?')]));

      expect(response.message.text, 'Bring a coat.');
      final call = response.message.toolCalls.single;
      expect(call.toolName, 'get_weather');
      expect(call.input, {'city': 'Oslo'});
      expect(response.usage.inputTokens, 5);
      expect(response.usage.outputTokens, 7);
      expect(response.finishReason, FinishReason.stop);
    });
  });

  group('GeminiModel request mapping', () {
    test('responseFormat sets responseMimeType and responseSchema', () async {
      final bodies = <Map<String, dynamic>>[];
      final mock = _capturing(bodies, {'candidates': <Object?>[]});
      final model = GeminiModel(client: _client(mock), modelId: 'm');
      final schema = <String, Object?>{
        'type': 'object',
        'properties': {
          'x': {'type': 'string'},
        },
      };

      await model.generate(ModelRequest(
        messages: [UserMessage.text('hi')],
        responseFormat: JsonResponseFormat(schema),
      ));

      final config = bodies.single['generationConfig'] as Map<String, dynamic>;
      expect(config['responseMimeType'], 'application/json');
      expect(config['responseSchema'], schema);
    });

    test('toolChoice maps onto functionCallingConfig', () async {
      final bodies = <Map<String, dynamic>>[];
      final mock = _capturing(bodies, {'candidates': <Object?>[]});
      final model = GeminiModel(client: _client(mock), modelId: 'm');

      Map<String, dynamic> fcc(Map<String, dynamic> body) =>
          (body['toolConfig'] as Map<String, dynamic>)['functionCallingConfig']
              as Map<String, dynamic>;

      await model.generate(ModelRequest(
        messages: [UserMessage.text('hi')],
        toolChoice: ToolChoice.any,
      ));
      expect(fcc(bodies.last)['mode'], 'ANY');

      await model.generate(ModelRequest(
        messages: [UserMessage.text('hi')],
        toolChoice: const ToolChoice.tool('get_weather'),
      ));
      expect(fcc(bodies.last)['mode'], 'ANY');
      expect(fcc(bodies.last)['allowedFunctionNames'], ['get_weather']);

      await model.generate(ModelRequest(
        messages: [UserMessage.text('hi')],
        toolChoice: ToolChoice.none,
      ));
      expect(fcc(bodies.last)['mode'], 'NONE');

      await model.generate(ModelRequest(
        messages: [UserMessage.text('hi')],
        toolChoice: ToolChoice.auto,
      ));
      expect(bodies.last.containsKey('toolConfig'), isFalse);
    });
  });

  group('GeminiEmbeddingModel', () {
    test('returns one vector per input', () async {
      final mock = MockClient((request) async => http.Response(
            jsonEncode({
              'embedding': {
                'values': [0.1, 0.2, 0.3],
              },
            }),
            200,
          ));
      final model =
          GeminiEmbeddingModel(client: _client(mock), modelId: 'embed-x');

      final vectors = await model.embed(['a', 'bb']);

      expect(vectors, hasLength(2));
      expect(vectors.first, [0.1, 0.2, 0.3]);
    });
  });
}
