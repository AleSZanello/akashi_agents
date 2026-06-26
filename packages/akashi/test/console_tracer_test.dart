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
  group('ConsoleTracer', () {
    test('writes the run -> step -> tool span tree to its sink', () async {
      final lines = <String>[];
      final model = FakeLanguageModel([
        [
          const ToolCallCompletePart(
              toolCallId: 'c1', toolName: 'echo', input: {'text': 'hi'}),
          const FinishPart(FinishReason.stop),
        ],
        [const TextDeltaPart('done'), const FinishPart(FinishReason.stop)],
      ]);
      final agent = ToolLoopAgent<Object?>(
        model: model,
        tools: [_echoTool()],
        tracer: ConsoleTracer(sink: lines.add),
      );

      await agent.run('go');

      expect(lines.any((l) => l.contains('agent.run')), isTrue);
      expect(lines.any((l) => l.contains('agent.step')), isTrue);
      expect(lines.any((l) => l.contains('tool.echo')), isTrue);
      // Tool spans are nested deeper than the run span.
      final runLine = lines.firstWhere((l) => l.contains('▶ agent.run'));
      final toolLine = lines.firstWhere((l) => l.contains('▶ tool.echo'));
      expect(toolLine.indexOf('▶'), greaterThan(runLine.indexOf('▶')));
    });
  });
}
