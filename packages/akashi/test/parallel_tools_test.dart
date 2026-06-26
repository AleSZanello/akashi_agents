import 'dart:async';

import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

import 'support/fake_language_model.dart';

final _emptyObject = Schema.raw<Map<String, Object?>>(
  {'type': 'object'},
  (j) => (j! as Map).cast<String, Object?>(),
);

Tool<Object?> _tool(
  String name,
  FutureOr<Object?> Function() run,
) =>
    tool<Map<String, Object?>, Object?>(
      name: name,
      description: name,
      inputSchema: _emptyObject,
      execute: (input, ctx) => run(),
    );

/// A model that calls [slow] then [fast] in one turn, then answers.
FakeLanguageModel _twoCallModel() => FakeLanguageModel([
      [
        const ToolCallCompletePart(
            toolCallId: 'c1', toolName: 'slow', input: {}),
        const ToolCallCompletePart(
            toolCallId: 'c2', toolName: 'fast', input: {}),
        const FinishPart(FinishReason.stop),
      ],
      [const TextDeltaPart('done'), const FinishPart(FinishReason.stop)],
    ]);

void main() {
  group('parallel tool execution', () {
    test('runs a step\'s tools concurrently, results in call-index order',
        () async {
      // `slow` blocks until `fast` runs — so this only completes if the two
      // execute concurrently. Sequential execution would deadlock.
      final gate = Completer<void>();
      final agent = ToolLoopAgent<Object?>(
        model: _twoCallModel(),
        tools: [
          _tool('slow', () async {
            await gate.future;
            return 'slow-done';
          }),
          _tool('fast', () async {
            gate.complete();
            return 'fast-done';
          }),
        ],
      );

      final events =
          await agent.stream('go').toList().timeout(const Duration(seconds: 5));

      final results = events.whereType<ToolResult>().toList();
      expect(results.map((r) => r.result.toolName), ['slow', 'fast']);
      expect(results.map((r) => r.result.output), ['slow-done', 'fast-done']);
    });

    test('parallelToolCalls: false executes tools sequentially in order',
        () async {
      final order = <String>[];
      final agent = ToolLoopAgent<Object?>(
        model: _twoCallModel(),
        parallelToolCalls: false,
        tools: [
          _tool('slow', () async {
            order.add('slow');
            return 'slow-done';
          }),
          _tool('fast', () async {
            order.add('fast');
            return 'fast-done';
          }),
        ],
      );

      final events = await agent.stream('go').toList();

      expect(order, ['slow', 'fast']);
      final results = events.whereType<ToolResult>().toList();
      expect(results.map((r) => r.result.toolName), ['slow', 'fast']);
    });
  });
}
