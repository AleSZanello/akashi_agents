import 'package:akashi/akashi.dart';

/// The text of the most recent user message in [request], or `''`.
String lastUserText(ModelRequest request) {
  final users = request.messages.whereType<UserMessage>();
  if (users.isEmpty) return '';
  return users.last.content.whereType<TextPart>().map((p) => p.text).join();
}

/// The last [ToolResultPart] in [request]'s history, or null — lets a scripted
/// model branch on "first step" (a user message) vs "after a tool ran".
ToolResultPart? lastToolResult(ModelRequest request) {
  for (final message in request.messages.reversed) {
    if (message is ToolMessage) {
      final results = message.content.whereType<ToolResultPart>();
      if (results.isNotEmpty) return results.last;
    }
    if (message is UserMessage) return null; // newer user turn — fresh step
  }
  return null;
}

/// One scripted model turn — what the fake model "says" for a single step of the
/// agent loop. Each call to [ScriptedModel.stream] consumes the next turn.
class Turn {
  const Turn({
    this.reasoning,
    this.text,
    this.toolCalls = const [],
    this.finishReason = FinishReason.stop,
  });

  /// Optional reasoning ("thinking") streamed before the text.
  final String? reasoning;

  /// Optional assistant text, streamed word-by-word for a typewriter effect.
  final String? text;

  /// Tool calls the model requests this turn (drives the loop's tool phase).
  final List<ToolCallSpec> toolCalls;

  /// Why this turn ends. The loop continues while there are tool calls.
  final FinishReason finishReason;
}

/// A tool call without a hand-managed id — [ScriptedModel] assigns ids.
class ToolCallSpec {
  const ToolCallSpec(this.name, this.input);
  final String name;
  final Map<String, Object?> input;
}

/// A fully client-side [LanguageModel] that replays a script of [Turn]s with
/// realistic streaming — no network, no API key. The substrate for every demo.
///
/// Provide either a static list of [turns] (consumed in order) or a [respond]
/// callback that builds a turn from the live request + turn index, so a demo can
/// react to what the user typed.
class ScriptedModel implements LanguageModel {
  ScriptedModel({
    required Turn Function(ModelRequest request, int index) respond,
    this.modelId = 'scripted',
    this.providerId = 'fake',
    this.chunkDelay = const Duration(milliseconds: 26),
    // ignore: prefer_initializing_formals
  }) : _respond = respond;

  /// Build a model that replays [turns] in order; later steps yield a bare stop.
  factory ScriptedModel.turns(
    List<Turn> turns, {
    String modelId = 'scripted',
    Duration chunkDelay = const Duration(milliseconds: 26),
  }) => ScriptedModel(
    modelId: modelId,
    chunkDelay: chunkDelay,
    respond: (_, index) =>
        index < turns.length ? turns[index] : const Turn(text: ''),
  );

  final Turn Function(ModelRequest request, int index) _respond;

  @override
  final String modelId;

  @override
  final String providerId;

  /// Delay between streamed word chunks — the typewriter cadence.
  final Duration chunkDelay;

  int _turnIndex = 0;
  int _callSeq = 0;

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    final turn = _respond(request, _turnIndex++);

    final reasoning = turn.reasoning;
    if (reasoning != null && reasoning.isNotEmpty) {
      await for (final chunk in _chunks(reasoning, request)) {
        yield ReasoningDeltaPart(chunk);
      }
    }

    final text = turn.text;
    if (text != null && text.isNotEmpty) {
      await for (final chunk in _chunks(text, request)) {
        yield TextDeltaPart(chunk);
      }
    }

    for (final call in turn.toolCalls) {
      yield ToolCallCompletePart(
        toolCallId: 'call_${_callSeq++}',
        toolName: call.name,
        input: call.input,
      );
    }

    yield FinishPart(turn.finishReason);
  }

  /// Yield [text] in small word-sized chunks, pausing [chunkDelay] between them
  /// and bailing out early if the run is cancelled.
  Stream<String> _chunks(String text, ModelRequest request) async* {
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      if (request.cancel.isCancelled) return;
      await Future<void>.delayed(chunkDelay);
      yield i == 0 ? words[i] : ' ${words[i]}';
    }
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async {
    final turn = _respond(request, _turnIndex++);
    return ModelResponse(
      message: AssistantMessage([
        if (turn.text != null) TextPart(turn.text!),
        for (final call in turn.toolCalls)
          ToolCallPart(
            toolCallId: 'call_${_callSeq++}',
            toolName: call.name,
            input: call.input,
          ),
      ]),
      finishReason: turn.finishReason,
      usage: Usage.zero,
    );
  }
}
