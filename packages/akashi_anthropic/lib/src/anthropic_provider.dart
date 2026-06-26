import 'package:akashi/akashi.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as a;

import 'claude_model.dart';

/// A [Provider] backed by Anthropic's Messages API (via `anthropic_sdk_dart`).
///
/// ```dart
/// final provider = AnthropicProvider(apiKey: Platform.environment['ANTHROPIC_API_KEY']!);
/// final model = provider.languageModel('claude-sonnet-4-5');
/// ```
final class AnthropicProvider implements Provider {
  /// Creates a provider from an [apiKey]. An existing [client] may be injected
  /// for testing.
  AnthropicProvider({required String apiKey, a.AnthropicClient? client})
    : _client = client ?? a.AnthropicClient.withApiKey(apiKey);

  final a.AnthropicClient _client;

  @override
  String get id => 'anthropic';

  @override
  LanguageModel languageModel(String modelId) =>
      ClaudeModel(client: _client, modelId: modelId);
}
