import 'package:akashi/akashi.dart';

import 'chunker.dart';
import 'document.dart';
import 'retrieval.dart';
import 'vector_store.dart';

/// The high-level RAG façade for the built-in path: it pairs a core
/// [EmbeddingModel] with a [VectorStore] to ingest [Document]s and answer text
/// queries. It is the only place embeddings and storage meet, and it *is* a
/// [Retriever] — so it drops straight into [retrievalTool].
///
/// ```dart
/// final kb = KnowledgeBase(
///   embedder: registry.embeddingModel('google/text-embedding-004')!,
///   store: InMemoryVectorStore(),
/// );
/// await kb.addDocuments(docs);
/// final hits = await kb.retrieve(const RetrievalQuery(text: 'how do refunds work?'));
/// ```
final class KnowledgeBase implements Retriever {
  /// Creates a knowledge base over [embedder] and [store].
  ///
  /// [chunker] splits documents on ingest (defaults to [RecursiveChunker]).
  /// [embedBatchSize] caps how many chunk texts are sent to [EmbeddingModel.embed]
  /// in a single call.
  KnowledgeBase({
    required this.embedder,
    required this.store,
    this.chunker = const RecursiveChunker(),
    this.embedBatchSize = 64,
  }) : assert(embedBatchSize > 0, 'embedBatchSize must be positive');

  /// The model that turns text into vectors (reused from core `akashi`).
  final EmbeddingModel embedder;

  /// The backing index.
  final VectorStore store;

  /// The splitter applied to each [Document] on ingest.
  final Chunker chunker;

  /// The maximum number of chunk texts embedded per [EmbeddingModel.embed] call.
  final int embedBatchSize;

  /// Chunk → embed (batched) → upsert each of [documents]. Documents that chunk
  /// to nothing (empty/whitespace text) are skipped.
  Future<void> addDocuments(List<Document> documents) async {
    final chunks = [
      for (final document in documents) ...chunker.chunk(document),
    ];
    if (chunks.isEmpty) return;

    final embedded = <EmbeddedChunk>[];
    for (var start = 0; start < chunks.length; start += embedBatchSize) {
      final end = start + embedBatchSize <= chunks.length
          ? start + embedBatchSize
          : chunks.length;
      final batch = chunks.sublist(start, end);
      final vectors = await embedder.embed([for (final c in batch) c.text]);
      for (var i = 0; i < batch.length; i++) {
        embedded.add(EmbeddedChunk(chunk: batch[i], embedding: vectors[i]));
      }
    }
    await store.upsert(embedded);
  }

  /// Convenience for ingesting a single [document].
  Future<void> addDocument(Document document) => addDocuments([document]);

  /// Remove every chunk derived from [documentId].
  Future<void> removeDocument(String documentId) =>
      store.deleteDocument(documentId);

  @override
  Future<List<RetrievedChunk>> retrieve(RetrievalQuery query) async {
    final vectors = await embedder.embed([query.text]);
    return store.search(
      vectors.single,
      topK: query.topK,
      filter: query.filter,
    );
  }
}
