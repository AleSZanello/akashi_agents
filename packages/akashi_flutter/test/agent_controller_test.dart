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
}
