import 'package:akashi/akashi.dart';
import 'package:openai_dart/openai_dart.dart' as o;

import 'openai_embedding_model.dart';
import 'openai_model.dart';

/// A [Provider] backed by OpenAI's chat + embeddings APIs (via `openai_dart`).
///
/// ```dart
/// final provider = OpenAIProvider(apiKey: Platform.environment['OPENAI_API_KEY']!);
/// final model = provider.languageModel('gpt-4o');
/// // ... use the agent ...
/// provider.close(); // release the shared HTTP connection when done
/// ```
final class OpenAIProvider implements Provider, EmbeddingProvider {
  /// Creates a provider from an [apiKey] (optionally pointing at a [baseUrl] for
  /// OpenAI-compatible servers). An existing [client] may be injected for
  /// testing; when injected, you own its lifecycle and [close] leaves it open.
  OpenAIProvider({
    required String apiKey,
    String? baseUrl,
    o.OpenAIClient? client,
  }) : _client =
           client ??
           o.OpenAIClient.withApiKey(
             apiKey,
             baseUrl: baseUrl ?? 'https://api.openai.com/v1',
           ),
       _ownsClient = client == null;

  final o.OpenAIClient _client;
  final bool _ownsClient;

  @override
  String get id => 'openai';

  @override
  LanguageModel languageModel(String modelId) =>
      OpenAIModel(client: _client, modelId: modelId);

  @override
  EmbeddingModel? embeddingModel(String modelId) =>
      OpenAIEmbeddingModel(client: _client, modelId: modelId);

  /// Closes the shared underlying client, releasing its HTTP connection. Call
  /// when done with the provider and the models it minted. A no-op when an
  /// external [client] was injected — that one's lifecycle is yours.
  void close() {
    if (_ownsClient) _client.close();
  }
}
