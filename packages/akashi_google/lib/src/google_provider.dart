import 'package:akashi/akashi.dart';
import 'package:googleai_dart/googleai_dart.dart' as g;

import 'gemini_embedding_model.dart';
import 'gemini_model.dart';

/// A [Provider] backed by Google's Gemini API (via `googleai_dart`).
///
/// ```dart
/// final provider = GoogleProvider(apiKey: Platform.environment['GEMINI_API_KEY']!);
/// final model = provider.languageModel('gemini-2.5-flash');
/// ```
final class GoogleProvider implements Provider, EmbeddingProvider {
  /// Creates a provider from an [apiKey]. An existing [client] may be injected
  /// (e.g. for Vertex AI configuration or testing).
  GoogleProvider({required String apiKey, g.GoogleAIClient? client})
      : _client = client ??
            g.GoogleAIClient(
              config: g.GoogleAIConfig(
                authProvider: g.ApiKeyProvider(apiKey),
              ),
            );

  final g.GoogleAIClient _client;

  @override
  String get id => 'google';

  @override
  LanguageModel languageModel(String modelId) =>
      GeminiModel(client: _client, modelId: modelId);

  @override
  EmbeddingModel? embeddingModel(String modelId) =>
      GeminiEmbeddingModel(client: _client, modelId: modelId);
}
