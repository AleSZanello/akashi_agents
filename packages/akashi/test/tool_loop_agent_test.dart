import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

import 'support/fake_language_model.dart';

Tool<Object?> weatherTool({
  Future<Object?> Function(({String city}) input)? onExecute,
}) =>
    tool<({String city}), Object?>(
      name: 'get_weather',
      description: 'Get the weather for a city.',
      inputSchema: Schema.object(
        {'city': Schema.string()},
        required: ['city'],
        fromJson: (json) => (city: json['city']! as String),
      ),
      execute: (input, ctx) async => onExecute != null
          ? onExecute(input)
          : {'tempC': 9, 'city': input.city},
    );

void main() {
  group('ToolLoopAgent', () {
    test('runs a tool then returns the final answer', () async {
      final model = FakeLanguageModel([
        [
          const ToolCallCompletePart(
            toolCallId: 'c1',
            toolName: 'get_weather',
            input: {'city': 'Oslo'},
          ),
          const FinishPart(FinishReason.stop),
        ],
        [
          const TextDeltaPart('Bring a coat.'),
          const FinishPart(FinishReason.stop),
        ],
      ]);

      final agent =
          ToolLoopAgent<Object?>(model: model, tools: [weatherTool()]);
      final result = await agent.run('What should I wear in Oslo?');

      expect(result.text, 'Bring a coat.');
      expect(result.steps, hasLength(2));
      expect(result.steps.first.toolResults.single.toolName, 'get_weather');
      expect(result.steps.first.toolResults.single.isError, isFalse);

      // The second model call must carry the tool result back.
      expect(model.requests, hasLength(2));
      expect(model.requests[1].messages.whereType<ToolMessage>(), isNotEmpty);
    });

    test('passes typed deps and decoded input to the tool', () async {
      final seen = <String>[];
      final model = FakeLanguageModel([
        [
          const ToolCallCompletePart(
            toolCallId: 'c1',
            toolName: 'get_weather',
            input: {'city': 'Lima'},
          ),
          const FinishPart(FinishReason.stop),
        ],
        [
          const TextDeltaPart('Done.'),
          const FinishPart(FinishReason.stop),
        ],
      ]);

      final agent = ToolLoopAgent<Object?>(
        model: model,
        tools: [
          weatherTool(onExecute: (input) async {
            seen.add(input.city);
            return 'ok';
          }),
        ],
      );

      await agent.run('weather?');
      expect(seen.single, 'Lima');
    });

    test('stops at the step ceiling when the model never finishes', () async {
      final turns = List.generate(
        20,
        (_) => <ModelStreamPart>[
          const ToolCallCompletePart(
            toolCallId: 'c',
            toolName: 'get_weather',
            input: {'city': 'X'},
          ),
          const FinishPart(FinishReason.stop),
        ],
      );
      final model = FakeLanguageModel(turns);

      final agent = ToolLoopAgent<Object?>(
        model: model,
        tools: [weatherTool()],
        stopWhen: [stepCountIs(3)],
      );

      final result = await agent.run('go');
      expect(result.steps, hasLength(3));
      expect(result.finishReason, FinishReason.stop);
    });

    test('feeds tool errors back to the model and keeps going', () async {
      final model = FakeLanguageModel([
        [
          const ToolCallCompletePart(
            toolCallId: 'c1',
            toolName: 'get_weather',
            input: {'city': 'Oslo'},
          ),
          const FinishPart(FinishReason.stop),
        ],
        [
          const TextDeltaPart('Sorry, that failed.'),
          const FinishPart(FinishReason.stop),
        ],
      ]);

      final agent = ToolLoopAgent<Object?>(
        model: model,
        tools: [
          weatherTool(onExecute: (_) async => throw StateError('no service')),
        ],
      );

      final events = await agent.stream('go').toList();

      expect(events.whereType<ErrorEvent>(), isNotEmpty);
      final toolResult = events.whereType<ToolResult>().single;
      expect(toolResult.result.isError, isTrue);
      expect(toolResult.result.output, contains('no service'));

      // The follow-up request carries the error result back.
      final followUp = model.requests[1].messages.whereType<ToolMessage>();
      expect(followUp, isNotEmpty);
    });

    test('stream emits a well-formed event sequence', () async {
      final model = FakeLanguageModel([
        [
          const TextDeltaPart('Hello'),
          const TextDeltaPart(' world'),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final agent = ToolLoopAgent<Object?>(model: model);
      final events = await agent.stream('hi').toList();

      expect(events.first, isA<RunStart>());
      expect(events.last, isA<RunFinish>());
      final text = events.whereType<TextDelta>().map((e) => e.text).join();
      expect(text, 'Hello world');
      expect((events.last as RunFinish).text, 'Hello world');
    });

    test('unknown tool calls become error results, not crashes', () async {
      final model = FakeLanguageModel([
        [
          const ToolCallCompletePart(
            toolCallId: 'c1',
            toolName: 'does_not_exist',
            input: {},
          ),
          const FinishPart(FinishReason.stop),
        ],
        [
          const TextDeltaPart('handled'),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final agent =
          ToolLoopAgent<Object?>(model: model, tools: [weatherTool()]);
      final result = await agent.run('go');

      expect(result.text, 'handled');
      expect(result.steps.first.toolResults.single.isError, isTrue);
    });
  });
}
