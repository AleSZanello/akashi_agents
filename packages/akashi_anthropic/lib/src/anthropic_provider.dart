import 'package:akashi/akashi.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as a;

import 'claude_model.dart';

/// A [Provider] backed by Anthropic's Messages API (via `anthropic_sdk_dart`).
///
/// ```dart
/// final provider = AnthropicProvider(apiKey: Platform.environment['ANTHROPIC_API_KEY']!);
/// final model = provider.languageModel('claude-sonnet-4-5');
/// // ... use the agent ...
/// provider.close(); // release the shared HTTP connection when done
/// ```
final class AnthropicProvider implements Provider {
  /// Creates a provider from an [apiKey]. An existing [client] may be injected
  /// for testing; when injected, you own its lifecycle and [close] leaves it
  /// open.
  AnthropicProvider({required String apiKey, a.AnthropicClient? client})
    : _client = client ?? a.AnthropicClient.withApiKey(apiKey),
      _ownsClient = client == null;

  final a.AnthropicClient _client;
  final bool _ownsClient;

  @override
  String get id => 'anthropic';

  @override
  LanguageModel languageModel(String modelId) =>
      ClaudeModel(client: _client, modelId: modelId);

  /// Closes the shared underlying client, releasing its HTTP connection. A
  /// no-op when an external [client] was injected — that one's lifecycle is
  /// yours.
  void close() {
    if (_ownsClient) _client.close();
  }
}
