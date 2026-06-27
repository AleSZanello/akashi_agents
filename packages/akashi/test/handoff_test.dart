import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

import 'support/fake_language_model.dart';

Tool<Object?> refundTool() => tool<({String orderId}), Object?>(
      name: 'refund',
      description: 'Issue a refund for an order.',
      inputSchema: Schema.object(
        {'orderId': Schema.string()},
        required: ['orderId'],
        fromJson: (json) => (orderId: json['orderId']! as String),
      ),
      execute: (input, ctx) async => 'refunded ${input.orderId}',
    );

void main() {
  group('handoffs', () {
    test('triage transfers control to a specialist', () async {
      final billingModel = FakeLanguageModel([
        [
          const TextDeltaPart('billing handled'),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final billing = ToolLoopAgent<Object?>(
        model: billingModel,
        name: 'billing',
        instructions: 'You are billing.',
        tools: [refundTool()],
      );

      final triageModel = FakeLanguageModel([
        [
          const ToolCallCompletePart(
            toolCallId: 't1',
            toolName: 'transfer_to_billing',
            input: {},
          ),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final triage = ToolLoopAgent<Object?>(
        model: triageModel,
        name: 'triage',
        instructions: 'You triage.',
        handoffs: [handoff(billing, name: 'billing')],
      );

      final events = await triage.stream('I want a refund').toList();

      // Exactly one handoff, triage -> billing.
      final handoffs = events.whereType<HandoffEvent>().toList();
      expect(handoffs, hasLength(1));
      expect(handoffs.single.from, 'triage');
      expect(handoffs.single.to, 'billing');

      // Triage advertised the transfer tool to the model.
      expect(
        triageModel.requests.first.tools.map((t) => t.name),
        contains('transfer_to_billing'),
      );

      // The post-handoff request went to the specialist's model, carried the
      // specialist's tools, and swapped in the specialist's instructions.
      final billingRequest = billingModel.requests.single;
      expect(billingRequest.tools.map((t) => t.name), contains('refund'));
      expect(billingRequest.messages.first, isA<SystemMessage>());
      expect(
        (billingRequest.messages.first as SystemMessage).text,
        'You are billing.',
      );

      // History is preserved: the original user prompt and the transfer call's
      // ack result both survive into the specialist's context.
      final userTexts = billingRequest.messages
          .whereType<UserMessage>()
          .expand((m) => m.content)
          .whereType<TextPart>()
          .map((p) => p.text);
      expect(userTexts, contains('I want a refund'));
      expect(
        billingRequest.messages.whereType<ToolMessage>(),
        isNotEmpty,
      );

      // The specialist produced the final answer.
      expect((events.last as RunFinish).text, 'billing handled');
    });

    test('no handoffs leaves the request tools unchanged', () async {
      final model = FakeLanguageModel([
        [const TextDeltaPart('hi'), const FinishPart(FinishReason.stop)],
      ]);
      final agent = ToolLoopAgent<Object?>(model: model, tools: [refundTool()]);
      await agent.run('go');
      expect(model.requests.first.tools.map((t) => t.name), ['refund']);
    });
  });
}
