# Changelog

## 0.1.0

- Initial release of retrieval-augmented generation for Akashi.
- `Retriever` — the single read-side contract agents consume; the built-in
  `KnowledgeBase` and any external/"standard" RAG service satisfy it the same way.
- `Document` / `Chunk` / `EmbeddedChunk` value types, plus `RetrievalQuery` /
  `RetrievedChunk`.
- `Chunker` with `RecursiveChunker` (boundary-aware, the default) and
  `FixedSizeChunker` (sliding window). Character-based sizing with overlap.
- `VectorStore` contract and `InMemoryVectorStore` — a pure-Dart, brute-force
  cosine-similarity index with metadata filtering and `toJson` / `fromJson`
  persistence. Runs offline with no dependencies.
- `KnowledgeBase` — the built-in façade pairing a core `EmbeddingModel` with a
  `VectorStore`: chunk → embed (batched) → upsert on ingest, embed → search on
  retrieve. Implements `Retriever`.
- `retrievalTool` — wraps a `Retriever` as an Akashi `Tool` (model-driven
  retrieval), and `renderChunks` for a model-friendly context block.
