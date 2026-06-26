import 'package:akashi/akashi.dart';
import 'package:googleai_dart/googleai_dart.dart' as g;

/// An [EmbeddingModel] over a Gemini embedding model (e.g.
/// `text-embedding-004`), normalizing Gemini's embedding response into a plain
/// `List<List<double>>`.
final class GeminiEmbeddingModel implements EmbeddingModel {
  /// Creates a Gemini embedding model bound to a [client] and [modelId].
  GeminiEmbeddingModel({
    required g.GoogleAIClient client,
    required this.modelId,
  }) : _client = client;

  final g.GoogleAIClient _client;

  @override
  final String modelId;

  @override
  String get providerId => 'google';

  @override
  Future<List<List<double>>> embed(List<String> inputs) async {
    // Gemini's batch endpoint is a thin wrapper over embedContent; embed each
    // input concurrently and preserve input order.
    final responses = await Future.wait([
      for (final input in inputs)
        _client.models.embedContent(
          model: modelId,
          request: g.EmbedContentRequest(
            content: g.Content(parts: [g.TextPart(input)]),
          ),
        ),
    ]);
    return [for (final response in responses) response.embedding.values];
  }
}
