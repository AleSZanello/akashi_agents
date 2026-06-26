/// A model that turns text into vector embeddings — the small, self-contained
/// contract RAG and memory build on.
///
/// Kept separate from `LanguageModel` so a provider can add embeddings without
/// touching the language-model surface. A vector-store abstraction is out of
/// scope; this is just the embedding call.
abstract interface class EmbeddingModel {
  /// The owning provider's id.
  String get providerId;

  /// This embedding model's id.
  String get modelId;

  /// Embed each of [inputs], returning one vector per input in the same order.
  Future<List<List<double>>> embed(List<String> inputs);
}

/// An optional capability a `Provider` may also implement to mint
/// [EmbeddingModel]s.
///
/// Separate from `Provider` so adding it never breaks existing implementers;
/// `ProviderRegistry.embeddingModel` checks `provider is EmbeddingProvider`.
abstract interface class EmbeddingProvider {
  /// Resolve an embedding model by its provider-specific [modelId], or null if
  /// this provider offers none.
  EmbeddingModel? embeddingModel(String modelId);
}
