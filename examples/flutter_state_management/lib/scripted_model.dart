import 'package:akashi/akashi.dart';

/// A stand-in [LanguageModel] so these examples run with no API key.
///
/// Swap it for a real provider model — e.g. `akashi_google`'s `GeminiModel`
/// via `GoogleProvider(apiKey: ...).languageModel('gemini-2.5-flash')` — and
/// every recipe in this package is unchanged: they only ever touch the
/// provider-agnostic [Agent] surface.
class ScriptedModel implements LanguageModel {
  @override
  String get providerId => 'scripted';

  @override
  String get modelId => 'scripted';

  // Streamed in chunks so the live "in-flight text" path is exercised.
  static const _reply = ['Hello ', 'from ', 'Akashi!'];

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    for (final chunk in _reply) {
      yield TextDeltaPart(chunk);
    }
    yield const FinishPart(FinishReason.stop);
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async => ModelResponse(
    message: const AssistantMessage([TextPart('Hello from Akashi!')]),
    finishReason: FinishReason.stop,
    usage: Usage.zero,
  );
}
