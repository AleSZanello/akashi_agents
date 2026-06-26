import 'package:akashi/akashi.dart';
import 'package:openai_dart/openai_dart.dart' as o;

import 'openai_embedding_model.dart';
import 'openai_model.dart';

/// A [Provider] backed by OpenAI's chat + embeddings APIs (via `openai_dart`).
///
/// ```dart
/// final provider = OpenAIProvider(apiKey: Platform.environment['OPENAI_API_KEY']!);
/// final model = provider.languageModel('gpt-4o');
/// ```
final class OpenAIProvider implements Provider, EmbeddingProvider {
  /// Creates a provider from an [apiKey] (optionally pointing at a [baseUrl] for
  /// OpenAI-compatible servers). An existing [client] may be injected for
  /// testing.
  OpenAIProvider({
    required String apiKey,
    String? baseUrl,
    o.OpenAIClient? client,
  }) : _client =
           client ??
           o.OpenAIClient.withApiKey(
             apiKey,
             baseUrl: baseUrl ?? 'https://api.openai.com/v1',
           );

  final o.OpenAIClient _client;

  @override
  String get id => 'openai';

  @override
  LanguageModel languageModel(String modelId) =>
      OpenAIModel(client: _client, modelId: modelId);

  @override
  EmbeddingModel? embeddingModel(String modelId) =>
      OpenAIEmbeddingModel(client: _client, modelId: modelId);
}
