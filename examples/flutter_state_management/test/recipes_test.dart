// Behavioral validation: drive the real Cubit and Notifier over the offline
// ScriptedModel agent and assert the event stream folds into the transcript
// exactly as the rendering layer expects.
import 'package:akashi/akashi.dart' hide Provider;
import 'package:akashi_state_management_examples/bloc_example.dart';
import 'package:akashi_state_management_examples/chat_state.dart';
import 'package:akashi_state_management_examples/riverpod_example.dart';
import 'package:akashi_state_management_examples/scripted_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Agent<void> buildAgent() =>
    ToolLoopAgent<void>(model: ScriptedModel(), instructions: 'be helpful');

void expectFoldedTranscript(ChatState state) {
  // The run settled: no in-flight flags left dangling.
  expect(state.isRunning, isFalse);
  expect(state.streamingText, isEmpty);
  expect(state.error, isNull);
  // User turn + one committed assistant turn.
  expect(state.messages, hasLength(2));
  expect(state.messages.first, isA<UserMessage>());
  final assistant = state.messages.last;
  expect(assistant, isA<AssistantMessage>());
  expect((assistant as AssistantMessage).text, 'Hello from Akashi!');
}

void main() {
  test('Bloc Cubit folds a streamed run into the transcript', () async {
    final cubit = ChatCubit(buildAgent());
    addTearDown(cubit.close);

    await cubit.send('hi');

    expectFoldedTranscript(cubit.state);
  });

  test('Riverpod Notifier folds a streamed run into the transcript', () async {
    final container = ProviderContainer(
      overrides: [agentProvider.overrideWithValue(buildAgent())],
    );
    addTearDown(container.dispose);

    await container.read(chatProvider.notifier).send('hi');

    expectFoldedTranscript(container.read(chatProvider));
  });

  test('a guard blocks re-entrant sends while a run is in flight', () async {
    final cubit = ChatCubit(buildAgent());
    addTearDown(cubit.close);

    final first = cubit.send('hi');
    // Fired before the first run settled: must be ignored, not interleaved.
    await cubit.send('again');
    await first;

    expect(cubit.state.messages, hasLength(2));
  });
}
