import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

import 'support/fake_language_model.dart';

Tool<Object?> _echoTool() => tool<({String text}), Object?>(
      name: 'echo',
      description: 'Echoes the given text.',
      inputSchema: Schema.object<({String text})>(
        {'text': Schema.string()},
        required: ['text'],
        fromJson: (j) => (text: j['text']! as String),
      ),
      execute: (input, ctx) => 'echo: ${input.text}',
    );

void main() {
  group('InMemoryCheckpointStore + resume', () {
    test('a fresh agent resumes a checkpointed run with prior history',
        () async {
      final store = InMemoryCheckpointStore();

      // First agent: calls a tool, then stops (simulating the process ending).
      final model1 = FakeLanguageModel([
        [
          const ToolCallCompletePart(
              toolCallId: 'c1', toolName: 'echo', input: {'text': 'hi'}),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final agent1 = ToolLoopAgent<Object?>(
        model: model1,
        tools: [_echoTool()],
        checkpoints: store,
        stopWhen: [hasToolCall('echo')],
      );

      await agent1.run('start',
          options: const RunOptions(checkpointId: 'job-1'));

      final checkpoint = store.checkpoints['job-1'];
      expect(checkpoint, isNotNull);
      expect(checkpoint!.step, 0);
      expect(checkpoint.messages.whereType<ToolMessage>(), isNotEmpty);

      // A brand-new agent (new model instance) resumes from the store.
      final model2 = FakeLanguageModel([
        [const TextDeltaPart('all done'), const FinishPart(FinishReason.stop)],
      ]);
      final agent2 = ToolLoopAgent<Object?>(
        model: model2,
        tools: [_echoTool()],
        checkpoints: store,
      );

      final events = await agent2.resume('job-1').toList();

      expect(events.whereType<RunFinish>().single.text, 'all done');
      // The resumed model saw the prior tool call + result.
      final firstRequest = model2.requests.first;
      expect(firstRequest.messages.whereType<ToolMessage>(), isNotEmpty);
      expect(
        firstRequest.messages
            .whereType<AssistantMessage>()
            .any((m) => m.toolCalls.isNotEmpty),
        isTrue,
      );
    });

    test('resume throws without a checkpoint store', () {
      final agent = ToolLoopAgent<Object?>(model: FakeLanguageModel(const []));
      expect(agent.resume('nope').toList(), throwsA(isA<StateError>()));
    });

    test('resume throws when the id is unknown', () {
      final agent = ToolLoopAgent<Object?>(
        model: FakeLanguageModel(const []),
        checkpoints: InMemoryCheckpointStore(),
      );
      expect(agent.resume('missing').toList(), throwsA(isA<StateError>()));
    });
  });
}
