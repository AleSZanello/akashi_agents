import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

import 'support/fake_language_model.dart';

Tool<Object?> _dangerTool() => tool<Map<String, Object?>, Object?>(
      name: 'danger',
      description: 'A tool that requires approval.',
      inputSchema: Schema.raw<Map<String, Object?>>(
        {'type': 'object'},
        (j) => (j! as Map).cast<String, Object?>(),
      ),
      execute: (input, ctx) => 'did the dangerous thing',
      needsApproval: (input, ctx) => true,
    );

List<List<ModelStreamPart>> _callThenFinish(String finalText) => [
      [
        const ToolCallCompletePart(
            toolCallId: 'c1', toolName: 'danger', input: {}),
        const FinishPart(FinishReason.stop),
      ],
      [TextDeltaPart(finalText), const FinishPart(FinishReason.stop)],
    ];

void main() {
  group('approval', () {
    test('emits ApprovalRequest and rejects when no handler is configured',
        () async {
      final model = FakeLanguageModel(_callThenFinish('skipped it'));
      final agent =
          ToolLoopAgent<Object?>(model: model, tools: [_dangerTool()]);

      final events = await agent.stream('go').toList();

      expect(events.whereType<ApprovalRequest>(), hasLength(1));
      final result = events.whereType<ToolResult>().single.result;
      expect(result.isError, isTrue);
      // The error result was fed back to the model on the next turn.
      expect(
        model.requests[1].messages
            .whereType<ToolMessage>()
            .expand((m) => m.content.whereType<ToolResultPart>())
            .any((r) => r.isError),
        isTrue,
      );
    });

    test('CallbackApprovalHandler approves the call', () async {
      final model = FakeLanguageModel(_callThenFinish('done'));
      final agent = ToolLoopAgent<Object?>(
        model: model,
        tools: [_dangerTool()],
        approvalHandler: CallbackApprovalHandler<Object?>((_) => true),
      );

      final events = await agent.stream('go').toList();

      final result = events.whereType<ToolResult>().single.result;
      expect(result.isError, isFalse);
      expect(result.output, 'did the dangerous thing');
    });

    test('CallbackApprovalHandler rejects with a reason', () async {
      final model = FakeLanguageModel(_callThenFinish('skipped'));
      final agent = ToolLoopAgent<Object?>(
        model: model,
        tools: [_dangerTool()],
        approvalHandler: CallbackApprovalHandler<Object?>(
          (_) => false,
          reasonFor: (_) => 'user declined',
        ),
      );

      final events = await agent.stream('go').toList();

      final result = events.whereType<ToolResult>().single.result;
      expect(result.isError, isTrue);
      expect(result.output, 'user declined');
    });
  });
}
