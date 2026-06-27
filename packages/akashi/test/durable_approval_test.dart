import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

import 'support/fake_language_model.dart';

Tool<Object?> dangerTool() => tool<({String action}), Object?>(
      name: 'danger',
      description: 'Does something dangerous.',
      inputSchema: Schema.object(
        {'action': Schema.string()},
        required: ['action'],
        fromJson: (json) => (action: json['action']! as String),
      ),
      execute: (input, ctx) async => 'did the dangerous thing',
      needsApproval: (input, ctx) => true,
    );

ToolLoopAgent<Object?> durableAgent(
  LanguageModel model,
  CheckpointStore store,
) =>
    ToolLoopAgent<Object?>(
      model: model,
      tools: [dangerTool()],
      checkpoints: store,
      durableApproval: true,
    );

List<ModelStreamPart> _callDanger(String id) => [
      ToolCallCompletePart(
          toolCallId: id, toolName: 'danger', input: const {'action': 'wipe'}),
      const FinishPart(FinishReason.stop),
    ];

void main() {
  group('durable approval', () {
    test('suspends on approval and resumes approved on a fresh agent',
        () async {
      final store = InMemoryCheckpointStore();
      final a1 = durableAgent(FakeLanguageModel([_callDanger('c1')]), store);

      // The run suspends (throws) instead of blocking in memory.
      await expectLater(
        a1
            .stream('go', options: const RunOptions(checkpointId: 'job'))
            .toList(),
        throwsA(isA<Suspended>()),
      );
      final cp = store.checkpoints['job']!;
      expect(cp.status, CheckpointStatus.suspended);
      expect(cp.pendingApproval!.toolName, 'danger');

      // Drop a1; a fresh agent resumes. m2 serves the step after the tool runs.
      final m2 = FakeLanguageModel([
        [const TextDeltaPart('done'), const FinishPart(FinishReason.stop)],
      ]);
      final events = await durableAgent(m2, store)
          .resume('job', decision: const ApprovalDecision.approved())
          .toList();

      final result = events.whereType<ToolResult>().single.result;
      expect(result.isError, isFalse);
      expect(result.output, 'did the dangerous thing');
      expect(events.whereType<RunFinish>().single.text, 'done');
      // The tool result was fed forward into the post-resume model call.
      expect(m2.requests.first.messages.whereType<ToolMessage>(), isNotEmpty);
    });

    test('resumes rejected with an error result fed back to the model',
        () async {
      final store = InMemoryCheckpointStore();
      final a1 = durableAgent(FakeLanguageModel([_callDanger('c1')]), store);

      await expectLater(
        a1.run('go', options: const RunOptions(checkpointId: 'job2')),
        throwsA(isA<Suspended>()),
      );

      final m2 = FakeLanguageModel([
        [
          const TextDeltaPart('handled rejection'),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final events = await durableAgent(m2, store)
          .resume('job2',
              decision: const ApprovalDecision.rejected('not allowed'))
          .toList();

      final result = events.whereType<ToolResult>().single.result;
      expect(result.isError, isTrue);
      expect(result.output, 'not allowed');
      expect(events.whereType<RunFinish>().single.text, 'handled rejection');
    });

    test('resume rejects a checkpoint that is not awaiting approval', () async {
      final store = InMemoryCheckpointStore();
      await store
          .save(const AgentCheckpoint(id: 'plain', step: 0, messages: []));
      final agent = durableAgent(FakeLanguageModel(const []), store);
      expect(
        () => agent
            .resume('plain', decision: const ApprovalDecision.approved())
            .toList(),
        throwsStateError,
      );
    });
  });
}
