import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

import 'support/fake_language_model.dart';

Tool<Object?> _boomTool() => tool<Map<String, Object?>, Object?>(
      name: 'boom',
      description: 'Always fails.',
      inputSchema: Schema.raw<Map<String, Object?>>(
        {'type': 'object'},
        (j) => (j! as Map).cast<String, Object?>(),
      ),
      execute: (input, ctx) => throw StateError('boom'),
    );

void main() {
  group('keepLastMessages', () {
    test('keeps system messages and the last N others', () {
      final ctx = StepContext<Object?>(
        step: 0,
        messages: [
          const SystemMessage('sys'),
          UserMessage.text('u1'),
          const AssistantMessage([TextPart('a1')]),
          UserMessage.text('u2'),
        ],
        deps: null,
      );

      final cfg = keepLastMessages(ctx, 2);
      final messages = cfg.messages!;

      expect(messages.whereType<SystemMessage>(), hasLength(1));
      expect(messages, hasLength(3)); // system + last 2 (a1, u2)
      expect(
        messages
            .whereType<UserMessage>()
            .last
            .content
            .whereType<TextPart>()
            .single
            .text,
        'u2',
      );
    });

    test('trims what the model actually receives', () async {
      final model = FakeLanguageModel([
        [const TextDeltaPart('ok'), const FinishPart(FinishReason.stop)],
      ]);
      final agent = ToolLoopAgent<Object?>(
        model: model,
        prepareStep: (ctx) => keepLastMessages(ctx, 1),
      );

      await agent.run(<Message>[
        UserMessage.text('old1'),
        const AssistantMessage([TextPart('old2')]),
        UserMessage.text('newest'),
      ]);

      final sent = model.requests.first.messages;
      expect(sent, hasLength(1));
      expect(
        (sent.single as UserMessage).content.whereType<TextPart>().single.text,
        'newest',
      );
    });
  });

  group('escalateAfterErrors', () {
    test('swaps to the bigger model once enough tool errors accumulate',
        () async {
      final big = FakeLanguageModel([
        [const TextDeltaPart('recovered'), const FinishPart(FinishReason.stop)],
      ]);
      final small = FakeLanguageModel([
        [
          const ToolCallCompletePart(
              toolCallId: 'c1', toolName: 'boom', input: {}),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final agent = ToolLoopAgent<Object?>(
        model: small,
        tools: [_boomTool()],
        prepareStep: (ctx) =>
            escalateAfterErrors(ctx, bigger: big, afterErrors: 1),
      );

      final result = await agent.run('go');

      expect(result.text, 'recovered');
      expect(small.requests, hasLength(1)); // only step 0 used the small model
      expect(big.requests, hasLength(1)); // step 1 routed to the bigger model
    });

    test('returns null before the threshold', () {
      final ctx = StepContext<Object?>(
        step: 0,
        messages: [UserMessage.text('hi')],
        deps: null,
      );
      final big = FakeLanguageModel(const []);

      expect(escalateAfterErrors(ctx, bigger: big, afterErrors: 2), isNull);
    });
  });

  group('summarizeOlderThan', () {
    test('compacts old turns into a summary the main model sees', () async {
      final summarizer = FakeLanguageModel([
        [const TextDeltaPart('SUMMARY'), const FinishPart(FinishReason.stop)],
      ]);
      final main = FakeLanguageModel([
        [const TextDeltaPart('ok'), const FinishPart(FinishReason.stop)],
      ]);
      final agent = ToolLoopAgent<Object?>(
        model: main,
        prepareStep: (ctx) =>
            summarizeOlderThan(ctx, summarizer: summarizer, keep: 1),
      );

      await agent.run(<Message>[
        UserMessage.text('old-a'),
        UserMessage.text('old-b'),
        UserMessage.text('recent'),
      ]);

      expect(summarizer.requests, hasLength(1));
      final sent = main.requests.first.messages;
      expect(
        sent.whereType<SystemMessage>().any((m) => m.text.contains('SUMMARY')),
        isTrue,
      );
      expect(
        sent
            .whereType<UserMessage>()
            .last
            .content
            .whereType<TextPart>()
            .single
            .text,
        'recent',
      );
    });
  });
}
