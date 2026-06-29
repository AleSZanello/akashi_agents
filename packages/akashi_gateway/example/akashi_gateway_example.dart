// A self-contained tour of akashi_gateway: a `FallbackModel` that fails over
// from a flaky primary to a healthy backup, plus a `ProviderRegistry` resolving
// a "provider/model" string. Runs offline with scripted fake providers — swap
// them for GoogleProvider / OpenAIProvider / AnthropicProvider for real models.
//
// Run with: dart run example/akashi_gateway_example.dart
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_gateway/akashi_gateway.dart';

/// A scripted [LanguageModel] that either always throws (to force a failover) or
/// streams one fixed line of text.
class ScriptedModel implements LanguageModel {
  ScriptedModel({
    required this.providerId,
    required this.modelId,
    this.reply = '',
    this.fails = false,
  });

  @override
  final String providerId;

  @override
  final String modelId;

  final String reply;
  final bool fails;

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    if (fails) throw StateError('$providerId is unavailable');
    yield TextDeltaPart(reply);
    yield const FinishPart(FinishReason.stop);
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async {
    if (fails) throw StateError('$providerId is unavailable');
    return ModelResponse(
      message: AssistantMessage([TextPart(reply)]),
      finishReason: FinishReason.stop,
      usage: Usage.zero,
    );
  }
}

/// A fake [Provider] minting a single scripted model.
class ScriptedProvider implements Provider {
  ScriptedProvider(this.id, {this.reply = '', this.fails = false});

  @override
  final String id;

  final String reply;
  final bool fails;

  @override
  LanguageModel languageModel(String modelId) => ScriptedModel(
        providerId: id,
        modelId: modelId,
        reply: reply,
        fails: fails,
      );
}

Future<void> main() async {
  // 1) FallbackModel: the primary fails before emitting output, so the chain
  //    fails over to the backup transparently — the agent never knows.
  final resilient = FallbackModel([
    ScriptedProvider('flaky', fails: true).languageModel('primary'),
    ScriptedProvider(
      'backup',
      reply: 'Hello from the backup model.',
    ).languageModel('stable'),
  ]);

  final agent = ToolLoopAgent<Object?>(model: resilient);
  final result = await agent.run('Say hi.');
  stdout.writeln('FallbackModel answered: ${result.text}');

  // 2) ProviderRegistry: route a "provider/model" string to a registered
  //    provider — only the SDKs you import ship in your app.
  final registry = ProviderRegistry({
    'flaky': ScriptedProvider('flaky', fails: true),
    'backup': ScriptedProvider('backup', reply: 'resolved!'),
  });
  final model = registry.model('backup/stable');
  stdout.writeln('Registry resolved: ${model.providerId}/${model.modelId}');
}
