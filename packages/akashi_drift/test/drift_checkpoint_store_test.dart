import 'dart:io';
import 'dart:typed_data';

import 'package:akashi/akashi.dart';
import 'package:akashi_drift/akashi_drift.dart';
import 'package:test/test.dart';

/// A tiny scripted model, since akashi's `FakeLanguageModel` test support is not
/// exported. Each call to [stream] consumes the next turn.
class _FakeModel implements LanguageModel {
  _FakeModel(this._turns);

  final List<List<ModelStreamPart>> _turns;
  int _index = 0;

  @override
  String get providerId => 'fake';

  @override
  String get modelId => 'fake';

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    final turn = _index < _turns.length
        ? _turns[_index]
        : const <ModelStreamPart>[FinishPart(FinishReason.stop)];
    _index++;
    for (final part in turn) {
      yield part;
    }
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async => ModelResponse(
    message: const AssistantMessage([]),
    finishReason: FinishReason.stop,
    usage: Usage.zero,
  );
}

Tool<Object?> dangerTool() => tool<({String action}), Object?>(
  name: 'danger',
  description: 'Does something dangerous.',
  inputSchema: Schema.object(
    {'action': Schema.string()},
    required: ['action'],
    fromJson: (json) => (action: json['action']! as String),
  ),
  execute: (input, ctx) async => 'did it',
  needsApproval: (input, ctx) => true,
);

void main() {
  group('DriftCheckpointStore', () {
    test('round-trips a checkpoint containing every part subtype', () async {
      final store = DriftCheckpointStore.memory();
      final checkpoint = AgentCheckpoint(
        id: 'run',
        step: 1,
        status: CheckpointStatus.suspended,
        messages: [
          const SystemMessage('sys'),
          UserMessage.text('hi'),
          AssistantMessage([
            const ReasoningPart('thinking', signature: 'sig'),
            const TextPart('text'),
            ImagePart(
              bytes: Uint8List.fromList([1, 2, 3]),
              mediaType: 'image/png',
            ),
            const ToolCallPart(
              toolCallId: 'c1',
              toolName: 'danger',
              input: {'a': 1},
            ),
          ]),
          const ToolMessage([
            ToolResultPart(
              toolCallId: 'c1',
              toolName: 'danger',
              output: {'ok': true},
            ),
          ]),
        ],
        pendingApproval: const ToolCallPart(
          toolCallId: 'c1',
          toolName: 'danger',
          input: {'a': 1},
        ),
        resolvedResults: const [
          ToolResultPart(toolCallId: 'c0', toolName: 'safe', output: 'r'),
        ],
      );

      await store.save(checkpoint);
      final loaded = await store.load('run');

      expect(loaded, isNotNull);
      expect(loaded!.step, 1);
      expect(loaded.status, CheckpointStatus.suspended);
      expect(loaded.messages, hasLength(4));
      expect(loaded.pendingApproval!.toolName, 'danger');
      expect(loaded.resolvedResults.single.output, 'r');
      await store.close();
    });

    test(
      'returns null for an unknown id and keeps last write per id',
      () async {
        final store = DriftCheckpointStore.memory();
        expect(await store.load('missing'), isNull);
        await store.save(const AgentCheckpoint(id: 'x', step: 0, messages: []));
        await store.save(const AgentCheckpoint(id: 'x', step: 5, messages: []));
        expect((await store.load('x'))!.step, 5);
        await store.close();
      },
    );

    test(
      'suspends, then resumes across a fresh store reading the same file',
      () async {
        final dir = await Directory.systemTemp.createTemp('akashi_drift_test');
        final file = File('${dir.path}/runs.sqlite');
        try {
          // First "process": run suspends on approval and persists to disk.
          final store1 = DriftCheckpointStore.open(file);
          final agent1 = ToolLoopAgent<Object?>(
            model: _FakeModel([
              [
                const ToolCallCompletePart(
                  toolCallId: 'c1',
                  toolName: 'danger',
                  input: {'action': 'wipe'},
                ),
                const FinishPart(FinishReason.stop),
              ],
            ]),
            tools: [dangerTool()],
            checkpoints: store1,
            durableApproval: true,
          );
          await expectLater(
            agent1.run('go', options: const RunOptions(checkpointId: 'job')),
            throwsA(isA<Suspended>()),
          );
          await store1.close();

          // Second "process": a fresh store + agent reopen the file and resume.
          final store2 = DriftCheckpointStore.open(file);
          expect(
            (await store2.load('job'))!.status,
            CheckpointStatus.suspended,
          );

          final agent2 = ToolLoopAgent<Object?>(
            model: _FakeModel([
              [
                const TextDeltaPart('done'),
                const FinishPart(FinishReason.stop),
              ],
            ]),
            tools: [dangerTool()],
            checkpoints: store2,
            durableApproval: true,
          );
          final events = await agent2
              .resume('job', decision: const ApprovalDecision.approved())
              .toList();

          expect(events.whereType<ToolResult>().single.result.output, 'did it');
          expect(events.whereType<RunFinish>().single.text, 'done');
          await store2.close();
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );
  });
}
