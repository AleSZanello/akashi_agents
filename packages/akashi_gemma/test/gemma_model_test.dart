import 'package:akashi/akashi.dart';
import 'package:akashi_gemma/akashi_gemma.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scripted [GemmaBackend] (no flutter_gemma needed): one turn per call.
class FakeGemmaBackend implements GemmaBackend {
  FakeGemmaBackend(this.turns);

  final List<List<GemmaChunk>> turns;
  int _index = 0;
  List<Message> lastMessages = const [];

  @override
  Stream<GemmaChunk> generate(
    List<Message> messages, {
    List<ToolSpec> tools = const [],
  }) async* {
    lastMessages = messages;
    final turn = _index < turns.length ? turns[_index] : const <GemmaChunk>[];
    _index++;
    for (final chunk in turn) {
      yield chunk;
    }
  }
}

Tool<Object?> weatherTool() => tool<({String city}), Object?>(
  name: 'get_weather',
  description: 'Weather for a city.',
  inputSchema: Schema.object(
    {'city': Schema.string()},
    required: ['city'],
    fromJson: (json) => (city: json['city']! as String),
  ),
  execute: (input, ctx) async => 'cold in ${input.city}',
);

void main() {
  group('GemmaModel', () {
    test('normalizes text + reasoning + function-call chunks', () async {
      final backend = FakeGemmaBackend([
        [
          const GemmaReasoningChunk('hmm'),
          const GemmaTextChunk('Hello '),
          const GemmaTextChunk('world'),
          const GemmaFunctionCallChunk('get_weather', {'city': 'Oslo'}),
        ],
      ]);
      final model = GemmaModel(backend);

      final parts = await model
          .stream(ModelRequest(messages: [UserMessage.text('hi')]))
          .toList();

      expect(
        parts.whereType<TextDeltaPart>().map((p) => p.text).join(),
        'Hello world',
      );
      expect(parts.whereType<ReasoningDeltaPart>().single.text, 'hmm');
      final call = parts.whereType<ToolCallCompletePart>().single;
      expect(call.toolName, 'get_weather');
      expect(call.input, {'city': 'Oslo'});
      expect(parts.last, isA<FinishPart>());
    });

    test(
      'drives the full agent loop on-device (tool call then answer)',
      () async {
        final backend = FakeGemmaBackend([
          [
            const GemmaFunctionCallChunk('get_weather', {'city': 'Oslo'}),
          ],
          [const GemmaTextChunk('Bring a coat.')],
        ]);
        final agent = ToolLoopAgent<Object?>(
          model: GemmaModel(backend),
          tools: [weatherTool()],
        );

        final result = await agent.run('What should I wear in Oslo?');

        expect(result.text, 'Bring a coat.');
        expect(result.steps.first.toolResults.single.toolName, 'get_weather');
        expect(result.steps.first.toolResults.single.output, 'cold in Oslo');
      },
    );

    test('generate folds the stream into a single response', () async {
      final backend = FakeGemmaBackend([
        [const GemmaTextChunk('one '), const GemmaTextChunk('two')],
      ]);
      final response = await GemmaModel(
        backend,
      ).generate(ModelRequest(messages: [UserMessage.text('hi')]));
      expect(response.message.text, 'one two');
      expect(response.finishReason, FinishReason.stop);
    });
  });
}
