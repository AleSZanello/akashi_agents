import 'package:akashi/akashi.dart';

import 'gemma_backend.dart';

/// An on-device [LanguageModel] backed by a [GemmaBackend].
///
/// Proves the `LanguageModel` contract is not HTTP-bound: this normalizes a
/// local engine's token/function-call stream onto Akashi's [ModelStreamPart]
/// union exactly like a cloud adapter, so the same agent loop runs fully
/// offline. Pairs naturally with `akashi_gateway`'s `FallbackModel`
/// (on-device primary, cloud backup).
///
/// ```dart
/// final model = GemmaModel(FlutterGemmaBackend(chat));
/// final agent = ToolLoopAgent(model: model, tools: tools);
/// ```
class GemmaModel implements LanguageModel {
  /// Wraps a [backend] (the concrete on-device engine).
  GemmaModel(this.backend, {this.modelId = 'gemma', this.providerId = 'gemma'});

  /// The on-device engine.
  final GemmaBackend backend;

  @override
  final String modelId;

  @override
  final String providerId;

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    var callIndex = 0;
    await for (final chunk in backend.generate(
      request.messages,
      tools: request.tools,
    )) {
      // On-device generation can be long; stop draining if the run is cancelled.
      if (request.cancel.isCancelled) break;
      switch (chunk) {
        case GemmaTextChunk(:final text):
          yield TextDeltaPart(text);
        case GemmaReasoningChunk(:final text):
          yield ReasoningDeltaPart(text);
        case GemmaFunctionCallChunk(:final name, :final args):
          yield ToolCallCompletePart(
            toolCallId: 'gemma-call-${callIndex++}',
            toolName: name,
            input: args,
          );
      }
    }
    yield const FinishPart(FinishReason.stop);
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async {
    final text = StringBuffer();
    final reasoning = StringBuffer();
    final calls = <ToolCallPart>[];
    var reason = FinishReason.stop;

    await for (final part in stream(request)) {
      switch (part) {
        case TextDeltaPart(text: final delta):
          text.write(delta);
        case ReasoningDeltaPart(text: final delta):
          reasoning.write(delta);
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
        case FinishPart(reason: final r):
          reason = r;
        case ToolCallStartPart():
        case ToolCallDeltaPart():
        case UsagePart():
          break;
      }
    }

    return ModelResponse(
      message: AssistantMessage([
        if (reasoning.isNotEmpty) ReasoningPart(reasoning.toString()),
        if (text.isNotEmpty) TextPart(text.toString()),
        ...calls,
      ]),
      finishReason: reason,
      usage: Usage.zero,
    );
  }
}

/// A [Provider] minting [GemmaModel]s over a shared [GemmaBackend].
class GemmaProvider implements Provider {
  /// Creates a provider over [backend].
  GemmaProvider(this.backend, {this.id = 'gemma'});

  /// The on-device engine shared by minted models.
  final GemmaBackend backend;

  @override
  final String id;

  @override
  LanguageModel languageModel(String modelId) =>
      GemmaModel(backend, modelId: modelId, providerId: id);
}
