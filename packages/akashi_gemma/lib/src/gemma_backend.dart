import 'package:akashi/akashi.dart';

/// A normalized chunk from an on-device Gemma generation. The vendor surface
/// (flutter_gemma's `ModelResponse`) is mapped onto this so the agent-facing
/// [GemmaModel] never imports flutter_gemma and is fully testable offline.
sealed class GemmaChunk {
  const GemmaChunk();
}

/// A streamed text token.
final class GemmaTextChunk extends GemmaChunk {
  /// Wraps a text [text] token.
  const GemmaTextChunk(this.text);

  /// The token text.
  final String text;
}

/// A streamed "thinking" / reasoning token.
final class GemmaReasoningChunk extends GemmaChunk {
  /// Wraps a reasoning [text] token.
  const GemmaReasoningChunk(this.text);

  /// The reasoning text.
  final String text;
}

/// A model-emitted function (tool) call.
final class GemmaFunctionCallChunk extends GemmaChunk {
  /// Wraps a call to [name] with decoded [args].
  const GemmaFunctionCallChunk(this.name, this.args);

  /// The tool name.
  final String name;

  /// The decoded arguments.
  final Map<String, Object?> args;
}

/// The seam between [GemmaModel] and a concrete on-device engine.
///
/// Implement this over flutter_gemma (`FlutterGemmaBackend`) for real inference,
/// or with a fake for tests. [generate] produces the model's output for the
/// given [messages] (the agent loop's full history) as a stream of [GemmaChunk]s.
abstract interface class GemmaBackend {
  /// Generate a turn for [messages]; [tools] are the tool specs advertised this
  /// turn (on-device engines typically bind tools at session creation, so an
  /// implementation may ignore them).
  Stream<GemmaChunk> generate(List<Message> messages, {List<ToolSpec> tools});
}
