import 'dart:math' as math;

import 'document.dart';
import 'retrieval.dart';

/// The write side of RAG: a vector index you upsert into and search by vector.
///
/// Deliberately vector-space only — it knows nothing about how text becomes a
/// vector. The text → vector step is owned by [KnowledgeBase], which lets an
/// external service skip [VectorStore] entirely and implement [Retriever]
/// directly. The built-in [InMemoryVectorStore] is the pure-Dart reference;
/// external indexes (pgvector, Pinecone, ...) are separate adapter packages
/// implementing this same interface.
abstract interface class VectorStore {
  /// Upsert embedded chunks, idempotent by [Chunk.id] (a repeated id replaces
  /// the prior entry).
  Future<void> upsert(List<EmbeddedChunk> chunks);

  /// Remove every chunk whose [Chunk.documentId] equals [documentId].
  Future<void> deleteDocument(String documentId);

  /// The [topK] nearest chunks to [queryVector], keeping only those whose
  /// [Chunk.metadata] matches every entry in [filter].
  Future<List<RetrievedChunk>> search(
    List<double> queryVector, {
    int topK = 4,
    Map<String, Object?> filter = const {},
  });

  /// The number of indexed chunks.
  Future<int> get count;
}

/// A pure-Dart in-memory [VectorStore]: brute-force cosine similarity over a
/// list. Zero dependencies and runs offline — the reference implementation, and
/// what makes this package's example and tests key-free. Not intended for large
/// corpora (search is O(n) per query).
final class InMemoryVectorStore implements VectorStore {
  /// Creates an empty in-memory store.
  InMemoryVectorStore();

  /// Restores a store previously captured with [toJson].
  factory InMemoryVectorStore.fromJson(Map<String, Object?> json) {
    final store = InMemoryVectorStore();
    final chunks = (json['chunks'] as List).cast<Map<String, Object?>>();
    for (final entry in chunks) {
      final chunk = entry['chunk'] as Map<String, Object?>;
      store._byId[chunk['id'] as String] = EmbeddedChunk(
        chunk: Chunk(
          id: chunk['id'] as String,
          text: chunk['text'] as String,
          documentId: chunk['documentId'] as String,
          metadata: (chunk['metadata'] as Map).cast<String, Object?>(),
        ),
        embedding: (entry['embedding'] as List)
            .map((v) => (v as num).toDouble())
            .toList(),
      );
    }
    return store;
  }

  // Keyed by chunk id so upsert is idempotent and deletes are cheap. Insertion
  // order is preserved, which keeps ranking ties stable.
  final Map<String, EmbeddedChunk> _byId = {};

  @override
  Future<void> upsert(List<EmbeddedChunk> chunks) async {
    for (final embedded in chunks) {
      _byId[embedded.chunk.id] = embedded;
    }
  }

  @override
  Future<void> deleteDocument(String documentId) async {
    _byId.removeWhere((_, value) => value.chunk.documentId == documentId);
  }

  @override
  Future<List<RetrievedChunk>> search(
    List<double> queryVector, {
    int topK = 4,
    Map<String, Object?> filter = const {},
  }) async {
    final scored = <RetrievedChunk>[];
    for (final embedded in _byId.values) {
      if (!_matchesFilter(embedded.chunk.metadata, filter)) continue;
      scored.add(RetrievedChunk(
        chunk: embedded.chunk,
        score: _cosineSimilarity(queryVector, embedded.embedding),
      ));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return topK >= scored.length ? scored : scored.sublist(0, topK);
  }

  @override
  Future<int> get count async => _byId.length;

  /// A JSON-encodable snapshot of the index, for cheap offline persistence
  /// without a database. Round-trips via [InMemoryVectorStore.fromJson].
  Map<String, Object?> toJson() => {
        'chunks': [
          for (final embedded in _byId.values)
            {
              'chunk': {
                'id': embedded.chunk.id,
                'text': embedded.chunk.text,
                'documentId': embedded.chunk.documentId,
                'metadata': embedded.chunk.metadata,
              },
              'embedding': embedded.embedding,
            },
        ],
      };

  static bool _matchesFilter(
    Map<String, Object?> metadata,
    Map<String, Object?> filter,
  ) {
    for (final entry in filter.entries) {
      if (metadata[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Cosine similarity of two equal-length vectors, in `[-1, 1]`. Returns 0 when
/// either vector is all-zero (undefined direction).
double _cosineSimilarity(List<double> a, List<double> b) {
  if (a.length != b.length) {
    throw ArgumentError(
      'vector length mismatch: ${a.length} vs ${b.length}',
    );
  }
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) return 0;
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}
