import 'package:akashi/akashi.dart';
import 'package:akashi_workflow/akashi_workflow.dart';
import 'package:test/test.dart';

/// A trivial model that echoes a fixed line, so agentTask can be exercised
/// without a network key.
class _EchoModel implements LanguageModel {
  _EchoModel(this.reply);
  final String reply;

  @override
  String get providerId => 'fake';
  @override
  String get modelId => 'echo';

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    yield TextDeltaPart(reply);
    yield const FinishPart(FinishReason.stop);
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async => ModelResponse(
        message: AssistantMessage([TextPart(reply)]),
        finishReason: FinishReason.stop,
        usage: Usage.zero,
      );
}

void main() {
  test('agentTask runs an agent and returns its text', () async {
    final wf = Workflow(maxConcurrency: 3);
    final agents = {
      'a': ToolLoopAgent(model: _EchoModel('alpha')),
      'b': ToolLoopAgent(model: _EchoModel('beta')),
      'c': ToolLoopAgent(model: _EchoModel('gamma')),
    };
    final results = await wf.parallel([
      for (final entry in agents.entries)
        agentTask(entry.value, 'go', label: entry.key),
    ]);
    expect(results, ['alpha', 'beta', 'gamma']);
    wf.dispose();
  });

  test('fans out agents through a pipeline synthesis', () async {
    final wf = Workflow(maxConcurrency: 4);
    final researcher = ToolLoopAgent(model: _EchoModel('finding'));

    final pipeline = Pipeline.input<String>().stage<String>(
      'research',
      (topic, ctx) async {
        final result = await researcher.run(
          topic,
          options: RunOptions(cancel: ctx.cancel),
        );
        return '$topic→${result.text}';
      },
    );

    final results = await wf.pipeline(['x', 'y'], pipeline);
    expect(results.map((r) => r.value), ['x→finding', 'y→finding']);
    wf.dispose();
  });
}
