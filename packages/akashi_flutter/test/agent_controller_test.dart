import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A scripted model (akashi's `FakeLanguageModel` test support is not exported).
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

Tool<Object?> echoTool() => tool<({String value}), Object?>(
  name: 'echo',
  description: 'Echoes a value.',
  inputSchema: Schema.object(
    {'value': Schema.string()},
    required: ['value'],
    fromJson: (json) => (value: json['value']! as String),
  ),
  execute: (input, ctx) async => input.value,
);

/// Two turns: a tool call, then a final line of text.
_FakeModel _toolThenText(String toolName, String text) => _FakeModel([
  [
    ToolCallCompletePart(
      toolCallId: 'c1',
      toolName: toolName,
      input: const {'action': 'wipe', 'value': 'hi'},
    ),
    const FinishPart(FinishReason.stop),
  ],
  [TextDeltaPart(text), const FinishPart(FinishReason.stop)],
]);

void main() {
  testWidgets('streams text and resolves an approval dialog', (tester) async {
    final controller = AgentController<Object?>();
    final agent = ToolLoopAgent<Object?>(
      model: _FakeModel([
        [
          const ToolCallCompletePart(
            toolCallId: 'c1',
            toolName: 'danger',
            input: {'action': 'wipe'},
          ),
          const FinishPart(FinishReason.stop),
        ],
        [const TextDeltaPart('done'), const FinishPart(FinishReason.stop)],
      ]),
      tools: [dangerTool()],
      approvalHandler: controller,
    );
    controller.agent = agent;

    await tester.pumpWidget(
      MaterialApp(
        // Avoid the InkSparkle GPU shader, which flutter_tester (Impeller)
        // cannot load — unrelated to the agent logic under test.
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: AgentBuilder<Object?>(
            controller: controller,
            builder: (context, c) => Column(
              children: [
                Text('text:${c.text}'),
                if (c.pendingApproval != null)
                  TextButton(
                    onPressed: c.approve,
                    child: const Text('Approve'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // Start the run; it pauses at the approval gate.
    final run = controller.send('go');
    await tester.pumpAndSettle();

    // The pending approval surfaced as a dialog affordance.
    expect(find.text('Approve'), findsOneWidget);
    expect(controller.pendingApproval!.call.toolName, 'danger');

    // Approving resumes the run to completion.
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    await run;

    expect(find.text('text:done'), findsOneWidget);
    expect(controller.pendingApproval, isNull);
    expect(controller.isRunning, isFalse);
  });

  testWidgets('rejecting feeds an error back and the run still finishes', (
    tester,
  ) async {
    final controller = AgentController<Object?>();
    final agent = ToolLoopAgent<Object?>(
      model: _FakeModel([
        [
          const ToolCallCompletePart(
            toolCallId: 'c1',
            toolName: 'danger',
            input: {'action': 'wipe'},
          ),
          const FinishPart(FinishReason.stop),
        ],
        [const TextDeltaPart('handled'), const FinishPart(FinishReason.stop)],
      ]),
      tools: [dangerTool()],
      approvalHandler: controller,
    );
    controller.agent = agent;

    await tester.pumpWidget(
      MaterialApp(
        // Avoid the InkSparkle GPU shader, which flutter_tester (Impeller)
        // cannot load — unrelated to the agent logic under test.
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: Scaffold(
          body: AgentBuilder<Object?>(
            controller: controller,
            builder: (context, c) => Column(
              children: [
                Text('text:${c.text}'),
                if (c.pendingApproval != null)
                  TextButton(
                    onPressed: () => c.reject('no'),
                    child: const Text('Reject'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    final run = controller.send('go');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await run;

    expect(find.text('text:handled'), findsOneWidget);
    final results = controller.events.whereType<ToolResult>().toList();
    expect(results.single.result.isError, isTrue);
  });

  test('accumulates a Message transcript across a tool run', () async {
    final controller = AgentController<Object?>();
    controller.agent = ToolLoopAgent<Object?>(
      model: _toolThenText('echo', 'done'),
      tools: [echoTool()],
    );

    await controller.send('go');

    final messages = controller.messages;
    expect(messages.first, isA<UserMessage>());
    expect(
      messages.whereType<AssistantMessage>().any((m) => m.toolCalls.isNotEmpty),
      isTrue,
      reason: 'the tool-call step should be committed as an assistant message',
    );
    expect(messages.whereType<ToolMessage>(), isNotEmpty);
    expect((messages.last as AssistantMessage).text, 'done');
  });

  test('a second send continues the same transcript (multi-turn)', () async {
    final controller = AgentController<Object?>();
    controller.agent = ToolLoopAgent<Object?>(
      model: _FakeModel([
        [const TextDeltaPart('one'), const FinishPart(FinishReason.stop)],
        [const TextDeltaPart('two'), const FinishPart(FinishReason.stop)],
      ]),
    );

    await controller.send('first');
    await controller.send('second');

    final users = controller.messages.whereType<UserMessage>().toList();
    expect(users.length, 2);
    expect((controller.messages.last as AssistantMessage).text, 'two');
  });

  test('suspends durably and resumes via resume()', () async {
    final store = InMemoryCheckpointStore();
    final controller = AgentController<Object?>();
    controller.agent = ToolLoopAgent<Object?>(
      model: _toolThenText('danger', 'done'),
      tools: [dangerTool()],
      checkpoints: store,
      durableApproval: true,
    );

    await controller.send(
      'go',
      options: const RunOptions(checkpointId: 'job-1'),
    );
    expect(controller.isSuspended, isTrue);
    expect(controller.isRunning, isFalse);
    expect(controller.suspended!.pendingCall.toolName, 'danger');

    await controller.resume(
      'job-1',
      decision: const ApprovalDecision.approved(),
    );
    expect(controller.isSuspended, isFalse);
    expect(controller.text, 'done');
    expect(controller.messages.whereType<ToolMessage>(), isNotEmpty);
  });

  test(
    'dispose() rejects a pending approval and silences notifications',
    () async {
      final controller = AgentController<Object?>();
      controller.agent = ToolLoopAgent<Object?>(
        model: _toolThenText('danger', 'done'),
        tools: [dangerTool()],
        approvalHandler: controller,
      );

      final run = controller.send('go');
      // Let the run reach the in-process approval gate.
      while (controller.pendingApproval == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      // Disposing mid-run must not throw: it rejects the pending approval so the
      // loop unblocks, and the still-draining stream must not call
      // notifyListeners after dispose (which would throw a FlutterError and
      // surface as an error on the run future).
      controller.dispose();
      await expectLater(run, completes);
      expect(controller.isRunning, isFalse);
    },
  );

  test('approve() resumes a durable suspension', () async {
    final store = InMemoryCheckpointStore();
    final controller = AgentController<Object?>();
    controller.agent = ToolLoopAgent<Object?>(
      model: _toolThenText('danger', 'ok'),
      tools: [dangerTool()],
      checkpoints: store,
      durableApproval: true,
    );

    await controller.send(
      'go',
      options: const RunOptions(checkpointId: 'job-2'),
    );
    expect(controller.isSuspended, isTrue);

    controller.approve(); // fire-and-forget durable resume
    while (controller.isRunning || controller.isSuspended) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(controller.text, 'ok');
  });
}
