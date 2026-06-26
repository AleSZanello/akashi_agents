// Akashi v0.2 combined example.
//
// Wires one agent with: provider routing (ProviderRegistry), an OpenTelemetry
// tracer, an in-process approval gate, an in-memory checkpoint store, and
// structured output. Runs offline with a scripted model unless an API key is
// set, in which case it routes to that provider.
//
//   dart run                              # offline (scripted model)
//   GEMINI_API_KEY=... dart run           # routes to google/gemini-2.5-flash
//   OPENAI_API_KEY=... dart run           # routes to openai/gpt-4o-mini
//   ANTHROPIC_API_KEY=... dart run        # routes to anthropic/claude-haiku-4-5-20251001
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_anthropic/akashi_anthropic.dart';
import 'package:akashi_gateway/akashi_gateway.dart';
import 'package:akashi_google/akashi_google.dart';
import 'package:akashi_openai/akashi_openai.dart';
import 'package:akashi_otel/akashi_otel.dart';
import 'package:opentelemetry/sdk.dart' as otel;

void main() async {
  final env = Platform.environment;

  // 1. Provider routing — register whichever providers have a key.
  final providers = <String, Provider>{
    if (env['GEMINI_API_KEY'] case final key?)
      'google': GoogleProvider(apiKey: key),
    if (env['OPENAI_API_KEY'] case final key?)
      'openai': OpenAIProvider(apiKey: key),
    if (env['ANTHROPIC_API_KEY'] case final key?)
      'anthropic': AnthropicProvider(apiKey: key),
  };
  final registry = ProviderRegistry(providers);

  final modelRef = switch (providers.keys.firstOrNull) {
    'google' => 'google/gemini-2.5-flash',
    'openai' => 'openai/gpt-4o-mini',
    'anthropic' => 'anthropic/claude-haiku-4-5-20251001',
    _ => null,
  };
  final LanguageModel model = modelRef == null
      ? _ScriptedModel()
      : registry.model(modelRef);
  stdout.writeln('Model: ${modelRef ?? 'scripted (offline)'}\n');

  // 2. Observability — export the run/step/tool span tree.
  final tracer = OtelTracer(
    otel.TracerProviderBase(
      processors: [otel.SimpleSpanProcessor(_PrintingExporter())],
    ).getTracer('akashi'),
  );

  // 3. A sensitive tool, gated by human approval.
  final bookFlight = tool<({String destination}), Object?>(
    name: 'book_flight',
    description: 'Books a flight to a destination.',
    inputSchema: Schema.object<({String destination})>(
      {'destination': Schema.string()},
      required: ['destination'],
      fromJson: (j) => (destination: j['destination']! as String),
    ),
    execute: (input, ctx) => 'Booked a flight to ${input.destination}.',
    needsApproval: (input, ctx) => true,
  );

  final agent = ToolLoopAgent<Object?>(
    model: model,
    tools: [bookFlight],
    tracer: tracer,
    checkpoints: InMemoryCheckpointStore(),
    approvalHandler: CallbackApprovalHandler<Object?>((call) {
      stdout.writeln('  [approval] allow ${call.toolName}(${call.input})? yes');
      return true;
    }),
  );

  // 4. Stream a run that triggers the approval gate.
  stdout.writeln('--- streaming run ---');
  await for (final event in agent.stream(
    'Book me a flight to Tokyo.',
    options: const RunOptions(checkpointId: 'trip-42'),
  )) {
    switch (event) {
      case TextDelta(:final text):
        stdout.write(text);
      case ToolResult(:final result):
        stdout.writeln('  [tool] ${result.toolName} -> ${result.output}');
      case RunFinish(:final text):
        stdout.writeln('\nfinal: $text');
      default:
        break;
    }
  }

  // 5. Structured output — the strategy is picked from the model's
  // StructuredOutputCapable declaration (native JSON schema, tool mode, or
  // prompt-only) with a validate/repair safety net.
  stdout.writeln('\n--- structured output ---');
  final summary = await agent.generateObject(
    'Summarize the trip as JSON.',
    schema: Output.object<({String city, int nights})>(
      {'city': Schema.string(), 'nights': Schema.integer()},
      required: ['city', 'nights'],
      fromJson: (j) =>
          (city: j['city']! as String, nights: (j['nights']! as num).toInt()),
    ),
  );
  stdout.writeln('city=${summary.object.city} nights=${summary.object.nights}');
}

/// Prints each finished span — stands in for a real OTLP exporter.
final class _PrintingExporter implements otel.SpanExporter {
  @override
  void export(List<otel.ReadOnlySpan> spans) {
    for (final span in spans) {
      stdout.writeln('  [span] ${span.name}');
    }
  }

  @override
  void forceFlush() {}
  @override
  void shutdown() {}
}

/// An offline scripted model: book a flight, answer, then emit trip JSON.
final class _ScriptedModel implements LanguageModel {
  final List<List<ModelStreamPart>> _turns = [
    [
      const ToolCallCompletePart(
        toolCallId: 'c1',
        toolName: 'book_flight',
        input: {'destination': 'Tokyo'},
      ),
      const FinishPart(FinishReason.stop),
    ],
    [
      const TextDeltaPart('All set — enjoy Tokyo!'),
      const FinishPart(FinishReason.stop),
    ],
    [
      const TextDeltaPart('{"city":"Tokyo","nights":5}'),
      const FinishPart(FinishReason.stop),
    ],
  ];
  int _index = 0;

  @override
  String get providerId => 'scripted';
  @override
  String get modelId => 'scripted-1';

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
  Future<ModelResponse> generate(ModelRequest request) async {
    final text = StringBuffer();
    final calls = <ToolCallPart>[];
    await for (final part in stream(request)) {
      switch (part) {
        case TextDeltaPart(text: final delta):
          text.write(delta);
        case ToolCallCompletePart(
          :final toolCallId,
          :final toolName,
          :final input,
        ):
          calls.add(
            ToolCallPart(
              toolCallId: toolCallId,
              toolName: toolName,
              input: input,
            ),
          );
        default:
          break;
      }
    }
    return ModelResponse(
      message: AssistantMessage([
        if (text.isNotEmpty) TextPart(text.toString()),
        ...calls,
      ]),
      finishReason: FinishReason.stop,
      usage: Usage.zero,
    );
  }
}
