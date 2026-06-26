import 'package:akashi/akashi.dart';

/// A scripted [LanguageModel] for offline tests.
///
/// Each call to [stream]/[generate] consumes the next "turn" — a list of
/// [ModelStreamPart]s to emit. This lets a test drive the full agent loop
/// (tool calls, follow-up turns, stop conditions) with no network or API key.
///
/// ```dart
/// final model = FakeLanguageModel([
///   // turn 1: ask to call a tool
///   [
///     const ToolCallCompletePart(
///       toolCallId: 'c1', toolName: 'get_weather', input: {'city': 'Oslo'}),
///     const FinishPart(FinishReason.stop),
///   ],
///   // turn 2: final answer
///   [
///     const TextDeltaPart('Bring a coat.'),
///     const FinishPart(FinishReason.stop),
///   ],
/// ]);
/// ```
final class FakeLanguageModel
    implements LanguageModel, StructuredOutputCapable {
  /// Creates a fake model from a list of [turns].
  ///
  /// [structuredOutputModes] lets a test exercise `generateObject`'s strategy
  /// selection; it defaults to prompt-only (the universal fallback).
  FakeLanguageModel(
    this.turns, {
    this.structuredOutputModes = const {StructuredOutputMode.promptOnly},
  });

  /// The scripted turns, consumed in order.
  final List<List<ModelStreamPart>> turns;

  /// Every request the loop sent, in order (for assertions).
  final List<ModelRequest> requests = [];

  @override
  final Set<StructuredOutputMode> structuredOutputModes;

  int _index = 0;

  @override
  String get providerId => 'fake';

  @override
  String get modelId => 'fake-1';

  List<ModelStreamPart> _nextTurn(ModelRequest request) {
    requests.add(request);
    final turn = _index < turns.length
        ? turns[_index]
        : const <ModelStreamPart>[FinishPart(FinishReason.stop)];
    _index++;
    return turn;
  }

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    for (final part in _nextTurn(request)) {
      yield part;
    }
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async {
    final parts = <Part>[];
    final text = StringBuffer();
    var reason = FinishReason.stop;
    var usage = Usage.zero;

    for (final part in _nextTurn(request)) {
      switch (part) {
        case TextDeltaPart(text: final delta):
          text.write(delta);
        case ToolCallCompletePart(
            :final toolCallId,
            :final toolName,
            :final input
          ):
          parts.add(ToolCallPart(
              toolCallId: toolCallId, toolName: toolName, input: input));
        case FinishPart(reason: final r):
          reason = r;
        case UsagePart(usage: final u):
          usage = u;
        case ReasoningDeltaPart():
        case ToolCallStartPart():
        case ToolCallDeltaPart():
          break;
      }
    }

    return ModelResponse(
      message: AssistantMessage([
        if (text.isNotEmpty) TextPart(text.toString()),
        ...parts,
      ]),
      finishReason: reason,
      usage: usage,
    );
  }
}
