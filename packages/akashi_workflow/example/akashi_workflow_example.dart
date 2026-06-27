// A runnable, key-free example: plan → fan-out research → synthesize, all
// orchestrated deterministically by a Workflow over fake models.
//
//   dart run example/akashi_workflow_example.dart
import 'package:akashi/akashi.dart';
import 'package:akashi_workflow/akashi_workflow.dart';

void main() async {
  final wf = Workflow(
    maxConcurrency: 2, // only 2 researchers run at once
    defaultRetry:
        const RetryPolicy(maxAttempts: 3, initialDelay: Duration.zero),
  );

  // Narrate progress from the event stream.
  wf.events.listen((event) {
    final line = switch (event) {
      TaskStarted() => '▶ ${event.label} (attempt ${event.attempt})',
      TaskSucceeded() => '✓ ${event.label}',
      TaskFailed() => '✗ ${event.label} (willRetry: ${event.willRetry})',
      TaskRetrying() => '↻ ${event.label} in ${event.delay.inMilliseconds}ms',
    };
    print(line);
  });

  // 1. PLAN — a fixed set of subtopics (could be an objectTask in real use).
  final subtopics = ['isolates', 'event loop', 'async/await'];
  print('Planned ${subtopics.length} subtopics.\n');

  // 2. FAN-OUT — one researcher agent per subtopic, bounded to maxConcurrency.
  //    `flaky` fails on its first attempt to show retries kicking in.
  final researcher = ToolLoopAgent(model: _CannedModel('a concise finding'));
  var flakyArmed = true;
  final findings = await wf.parallelSettled([
    for (final topic in subtopics)
      Task<String>(
        (ctx) async {
          if (topic == 'event loop' && flakyArmed) {
            flakyArmed = false;
            throw StateError('transient lookup failure');
          }
          final result = await researcher.run(
            'Research: $topic',
            options: RunOptions(cancel: ctx.cancel),
          );
          return '$topic — ${result.text}';
        },
        label: 'research:$topic',
      ),
  ]);

  final ok = findings.where((r) => r.ok).map((r) => r.value).toList();
  print('\nGathered ${ok.length}/${subtopics.length} findings.\n');

  // 3. SYNTHESIZE — one writer agent merges the findings.
  final writer = ToolLoopAgent(model: _CannedModel('A tidy synthesis.'));
  final report = await wf.run(
    agentTask(writer, 'Synthesize:\n${ok.join('\n')}', label: 'synthesize'),
  );

  print('\n=== REPORT ===\n$report');
  wf.dispose();
}

/// A fake model that returns a canned line — no network, no key.
class _CannedModel implements LanguageModel {
  _CannedModel(this.text);
  final String text;

  @override
  String get providerId => 'fake';
  @override
  String get modelId => 'canned';

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    yield TextDeltaPart(text);
    yield const FinishPart(FinishReason.stop);
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async => ModelResponse(
        message: AssistantMessage([TextPart(text)]),
        finishReason: FinishReason.stop,
        usage: Usage.zero,
      );
}
