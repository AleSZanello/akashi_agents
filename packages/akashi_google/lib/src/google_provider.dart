import 'package:akashi/akashi.dart';
import 'package:googleai_dart/googleai_dart.dart' as g;

import 'gemini_embedding_model.dart';
import 'gemini_model.dart';

/// A [Provider] backed by Google's Gemini API (via `googleai_dart`).
///
/// ```dart
/// final provider = GoogleProvider(apiKey: Platform.environment['GEMINI_API_KEY']!);
/// final model = provider.languageModel('gemini-2.5-flash');
/// // ... use the agent ...
/// provider.close(); // release the shared HTTP connection when done
/// ```
final class GoogleProvider implements Provider, EmbeddingProvider {
  /// Creates a provider from an [apiKey]. An existing [client] may be injected
  /// (e.g. for Vertex AI configuration or testing); when injected, you own its
  /// lifecycle and [close] leaves it open.
  GoogleProvider({required String apiKey, g.GoogleAIClient? client})
      : _client = client ??
            g.GoogleAIClient(
              config: g.GoogleAIConfig(
                authProvider: g.ApiKeyProvider(apiKey),
              ),
            ),
        _ownsClient = client == null;

  final g.GoogleAIClient _client;
  final bool _ownsClient;

  @override
  String get id => 'google';

  @override
  LanguageModel languageModel(String modelId) =>
      GeminiModel(client: _client, modelId: modelId);

  @override
  EmbeddingModel? embeddingModel(String modelId) =>
      GeminiEmbeddingModel(client: _client, modelId: modelId);

  /// Closes the shared underlying client, releasing its HTTP connection. A
  /// no-op when an external [client] was injected — that one's lifecycle is
  /// yours.
  void close() {
    if (_ownsClient) _client.close();
  }
}
