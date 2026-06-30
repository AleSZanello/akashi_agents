import 'document.dart';

/// A retrieval request.
///
/// A value object (rather than bare parameters) so backends can grow — metadata
/// filters, hybrid/keyword search — without breaking the [Retriever] contract.
final class RetrievalQuery {
  /// Creates a retrieval query for [text], returning at most [topK] hits.
  const RetrievalQuery({
    required this.text,
    this.topK = 4,
    this.filter = const {},
  });

  /// The natural-language query to embed and search with.
  final String text;

  /// The maximum number of hits to return.
  final int topK;

  /// A metadata equality filter applied to candidate chunks. The built-in
  /// [VectorStore] keeps only chunks whose [Chunk.metadata] matches every entry
  /// here; external backends may interpret it natively.
  final Map<String, Object?> filter;
}

/// One scored hit from a [Retriever].
final class RetrievedChunk {
  /// Pairs a [chunk] with its relevance [score].
  const RetrievedChunk({required this.chunk, required this.score});

  /// The retrieved chunk.
  final Chunk chunk;

  /// Relevance; semantics are backend-defined. For the built-in store this is
  /// cosine similarity in `[-1, 1]`, higher = more relevant.
  final double score;
}

/// The read side of RAG, and the single seam an agent consumes: turn a text
/// query into the most relevant chunks.
///
/// The built-in [KnowledgeBase] and any external service (pgvector, Pinecone,
/// Vertex AI RAG Engine, a plain HTTP endpoint) satisfy this same interface, so
/// they drop into [retrievalTool] interchangeably.
abstract interface class Retriever {
  /// Return up to [RetrievalQuery.topK] chunks most relevant to the query.
  Future<List<RetrievedChunk>> retrieve(RetrievalQuery query);
}
