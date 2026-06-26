import 'package:akashi/akashi.dart';
import 'package:openai_dart/openai_dart.dart' as o;

/// An [EmbeddingModel] over an OpenAI embedding model (e.g.
/// `text-embedding-3-small`).
final class OpenAIEmbeddingModel implements EmbeddingModel {
  /// Creates an OpenAI embedding model bound to a [client] and [modelId].
  OpenAIEmbeddingModel({required o.OpenAIClient client, required this.modelId})
    : _client = client;

  final o.OpenAIClient _client;

  @override
  final String modelId;

  @override
  String get providerId => 'openai';

  @override
  Future<List<List<double>>> embed(List<String> inputs) async {
    final response = await _client.embeddings.create(
      o.EmbeddingRequest(
        model: modelId,
        input: o.EmbeddingInput.textList(inputs),
      ),
    );
    // The API may return items out of order; sort by index to match `inputs`.
    final data = [...response.data]..sort((a, b) => a.index.compareTo(b.index));
    return [for (final item in data) item.embedding];
  }
}
