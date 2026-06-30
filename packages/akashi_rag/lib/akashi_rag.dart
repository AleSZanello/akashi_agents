/// Retrieval-augmented generation for Akashi.
///
/// One [Retriever] contract is the seam an agent consumes — and *both* the
/// built-in path and an external/"standard" RAG service satisfy it. The built-in
/// path is a [KnowledgeBase]: it pairs a core `EmbeddingModel` with a
/// [VectorStore] (the pure-Dart [InMemoryVectorStore] by default) and a
/// [Chunker] to ingest [Document]s and answer text queries — offline, no keys.
///
/// Wire retrieval into an agent with [retrievalTool], which exposes any
/// [Retriever] as an Akashi `Tool` the model can call.
library;

export 'src/chunker.dart';
export 'src/document.dart';
export 'src/integration.dart';
export 'src/knowledge_base.dart';
export 'src/retrieval.dart';
export 'src/vector_store.dart';
