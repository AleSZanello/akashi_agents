import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

import 'support/fake_language_model.dart';

Tool<Object?> failingTool() => tool<({String x}), Object?>(
      name: 'do_it',
      description: 'Always throws.',
      inputSchema: Schema.object(
        {'x': Schema.string()},
        required: ['x'],
        fromJson: (json) => (x: json['x']! as String),
      ),
      execute: (input, ctx) async => throw StateError('boom'),
    );

void main() {
  group('escalation', () {
    test('escalates to the bigger model after enough tool errors', () async {
      final cheap = FakeLanguageModel([
        [
          const ToolCallCompletePart(
              toolCallId: 'a', toolName: 'do_it', input: {'x': '1'}),
          const FinishPart(FinishReason.stop),
        ],
        [
          const ToolCallCompletePart(
              toolCallId: 'b', toolName: 'do_it', input: {'x': '2'}),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final bigger = FakeLanguageModel([
        [const TextDeltaPart('escalated'), const FinishPart(FinishReason.stop)],
      ]);

      final agent = ToolLoopAgent<Object?>(
        model: cheap,
        tools: [failingTool()],
        prepareStep:
            escalate([escalateOnToolErrors(to: bigger, afterErrors: 2)]),
      );

      final result = await agent.run('go');

      expect(result.text, 'escalated');
      // Cheap handled steps 0 and 1; the bigger model handled the escalated step.
      expect(cheap.requests, hasLength(2));
      expect(bigger.requests, hasLength(1));
      // The escalated request carries the two accumulated tool errors.
      final errors = bigger.requests.single.messages
          .whereType<ToolMessage>()
          .expand((m) => m.content)
          .whereType<ToolResultPart>()
          .where((r) => r.isError);
      expect(errors, hasLength(2));
    });

    test('escalateAfterSteps swaps the model from the given step', () async {
      final cheap = FakeLanguageModel([
        [const TextDeltaPart('cheap'), const FinishPart(FinishReason.stop)],
      ]);
      final bigger = FakeLanguageModel([
        [const TextDeltaPart('big'), const FinishPart(FinishReason.stop)],
      ]);

      // afterSteps: 0 → escalate immediately, on step 0.
      final agent = ToolLoopAgent<Object?>(
        model: cheap,
        prepareStep: escalate([escalateAfterSteps(to: bigger, afterSteps: 0)]),
      );

      final result = await agent.run('go');
      expect(result.text, 'big');
      expect(cheap.requests, isEmpty);
      expect(bigger.requests, hasLength(1));
    });
  });
}
