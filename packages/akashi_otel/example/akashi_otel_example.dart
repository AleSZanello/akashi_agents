// Wires an OtelTracer into an agent and prints the exported spans. Runs fully
// offline with a scripted model: `dart run example/akashi_otel_example.dart`.
import 'package:akashi/akashi.dart';
import 'package:akashi_otel/akashi_otel.dart';
import 'package:opentelemetry/sdk.dart' as otel;

/// A minimal exporter that prints each finished span's name and parent.
final class _PrintingExporter implements otel.SpanExporter {
  @override
  void export(List<otel.ReadOnlySpan> spans) {
    for (final span in spans) {
      print('span: ${span.name} (parent ${span.parentSpanId})');
    }
  }

  @override
  void forceFlush() {}
  @override
  void shutdown() {}
}

/// A scripted model: call a tool, then answer.
final class _ScriptedModel implements LanguageModel {
  _ScriptedModel(this._turns);
  final List<List<ModelStreamPart>> _turns;
  int _i = 0;
  @override
  String get providerId => 'fake';
  @override
  String get modelId => 'fake';
  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    final turn = _i < _turns.length
        ? _turns[_i]
        : const [FinishPart(FinishReason.stop)];
    _i++;
    for (final part in turn) {
      yield part;
    }
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async =>
      throw UnimplementedError();
}

Future<void> main() async {
  final provider = otel.TracerProviderBase(
    processors: [otel.SimpleSpanProcessor(_PrintingExporter())],
  );
  final agent = ToolLoopAgent<Object?>(
    model: _ScriptedModel([
      [
        const ToolCallCompletePart(
          toolCallId: 'c1',
          toolName: 'ping',
          input: {},
        ),
        const FinishPart(FinishReason.stop),
      ],
      [const TextDeltaPart('pong'), const FinishPart(FinishReason.stop)],
    ]),
    tools: [
      tool<Map<String, Object?>, Object?>(
        name: 'ping',
        description: 'Returns pong.',
        inputSchema: Schema.raw<Map<String, Object?>>({
          'type': 'object',
        }, (j) => <String, Object?>{}),
        execute: (input, ctx) => 'pong',
      ),
    ],
    tracer: OtelTracer(provider.getTracer('akashi')),
  );

  await agent.run('ping the tool');
}
