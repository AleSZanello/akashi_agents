import 'package:akashi/akashi.dart';
import 'package:akashi_otel/akashi_otel.dart';
import 'package:opentelemetry/sdk.dart' as otel;
import 'package:test/test.dart';

/// Captures finished spans in memory for assertions.
final class _CapturingExporter implements otel.SpanExporter {
  final List<otel.ReadOnlySpan> spans = [];

  @override
  void export(List<otel.ReadOnlySpan> spans) => this.spans.addAll(spans);

  @override
  void forceFlush() {}

  @override
  void shutdown() {}
}

Tool<Object?> _echoTool() => tool<({String text}), Object?>(
  name: 'echo',
  description: 'Echoes text.',
  inputSchema: Schema.object<({String text})>(
    {'text': Schema.string()},
    required: ['text'],
    fromJson: (j) => (text: j['text']! as String),
  ),
  execute: (input, ctx) => 'echo: ${input.text}',
);

/// A scripted model: turn 1 calls `echo`, turn 2 answers.
final class _ScriptedModel implements LanguageModel {
  _ScriptedModel(this._turns);
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
        : const [FinishPart(FinishReason.stop)];
    _index++;
    for (final part in turn) {
      yield part;
    }
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async =>
      throw UnimplementedError();
}

void main() {
  group('OtelTracer', () {
    test('exports a run -> step -> tool span tree', () async {
      final exporter = _CapturingExporter();
      final provider = otel.TracerProviderBase(
        processors: [otel.SimpleSpanProcessor(exporter)],
      );
      final tracer = OtelTracer(provider.getTracer('akashi'));

      final model = _ScriptedModel([
        [
          const ToolCallCompletePart(
            toolCallId: 'c1',
            toolName: 'echo',
            input: {'text': 'hi'},
          ),
          const FinishPart(FinishReason.stop),
        ],
        [const TextDeltaPart('done'), const FinishPart(FinishReason.stop)],
      ]);
      final agent = ToolLoopAgent<Object?>(
        model: model,
        tools: [_echoTool()],
        tracer: tracer,
      );

      await agent.run('go');

      final spans = exporter.spans;
      final names = spans.map((s) => s.name).toSet();
      expect(names, containsAll(['agent.run', 'agent.step', 'tool.echo']));

      final run = spans.firstWhere((s) => s.name == 'agent.run');
      final steps = spans.where((s) => s.name == 'agent.step').toList();
      final toolSpan = spans.firstWhere((s) => s.name == 'tool.echo');
      final runId = run.spanContext.spanId.toString();

      // Every step is a child of the run; the tool is a child of some step.
      expect(steps.every((s) => s.parentSpanId.toString() == runId), isTrue);
      expect(
        steps.any(
          (s) =>
              s.spanContext.spanId.toString() ==
              toolSpan.parentSpanId.toString(),
        ),
        isTrue,
      );
    });
  });
}
