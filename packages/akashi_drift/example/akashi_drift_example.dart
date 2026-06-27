// Durable human-in-the-loop with a SQLite checkpoint store.
//
// Run offline with: dart run example/akashi_drift_example.dart
//
// A run suspends when a tool needs approval — persisting its state to SQLite and
// throwing `Suspended` instead of blocking. A *fresh* agent then reopens the
// database and resumes the run with the human's decision. This is the pattern
// for serverless/edge, where a run can span separate requests or processes.
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_drift/akashi_drift.dart';

/// A scripted stand-in model so the example runs without an API key.
class ScriptedModel implements LanguageModel {
  ScriptedModel(this._turns);

  final List<List<ModelStreamPart>> _turns;
  int _index = 0;

  @override
  String get providerId => 'scripted';

  @override
  String get modelId => 'scripted';

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

final deleteFiles = tool<({String path}), Object?>(
  name: 'delete_files',
  description: 'Permanently delete files under a path.',
  inputSchema: Schema.object(
    {'path': Schema.string()},
    required: ['path'],
    fromJson: (json) => (path: json['path']! as String),
  ),
  execute: (input, ctx) async => 'deleted ${input.path}',
  needsApproval: (input, ctx) => true, // gate this behind a human
);

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('akashi_drift_example');
  final file = File('${dir.path}/runs.sqlite');

  // --- "Request 1": the run starts and suspends on the approval gate. ---
  final store1 = DriftCheckpointStore.open(file);
  final agent1 = ToolLoopAgent<Object?>(
    model: ScriptedModel([
      [
        const ToolCallCompletePart(
          toolCallId: 'c1',
          toolName: 'delete_files',
          input: {'path': '/tmp/cache'},
        ),
        const FinishPart(FinishReason.stop),
      ],
    ]),
    tools: [deleteFiles],
    checkpoints: store1,
    durableApproval: true,
  );

  try {
    await agent1.run(
      'Clean up the cache.',
      options: const RunOptions(checkpointId: 'job-42'),
    );
  } on Suspended catch (s) {
    stdout.writeln(
      'Suspended run "${s.checkpointId}" — '
      'awaiting approval for ${s.pendingCall.toolName}'
      '(${s.pendingCall.input}).',
    );
  }
  await store1.close();

  // --- "Request 2": a fresh agent reopens the DB and resumes (approved). ---
  final store2 = DriftCheckpointStore.open(file);
  final agent2 = ToolLoopAgent<Object?>(
    model: ScriptedModel([
      [
        const TextDeltaPart('Done — cache cleared.'),
        const FinishPart(FinishReason.stop),
      ],
    ]),
    tools: [deleteFiles],
    checkpoints: store2,
    durableApproval: true,
  );

  await for (final event in agent2.resume(
    'job-42',
    decision: const ApprovalDecision.approved(),
  )) {
    if (event is ToolResult) {
      stdout.writeln('Tool result: ${event.result.output}');
    } else if (event is RunFinish) {
      stdout.writeln('Final: ${event.text}');
    }
  }
  await store2.close();

  await dir.delete(recursive: true);
}
