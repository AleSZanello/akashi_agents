# akashi_rag

**Retrieval-augmented generation for [Akashi](https://github.com/AleSZanello/akashi_agents).**

Embed documents, index them in a vector store, and retrieve the most relevant
chunks to ground an agent's answers. The whole built-in path is **pure Dart and
runs offline** — no database, no API key — and reuses the `EmbeddingModel`
contract that already ships in core `akashi`.

The design rests on **one seam**: the `Retriever`. There is no "build a RAG *or*
connect to a standard RAG" fork — both are the same interface. The built-in
`KnowledgeBase` implements `Retriever`, and so does any external/"standard" RAG
service (pgvector, Pinecone, Vertex AI RAG Engine, a plain HTTP endpoint). The
agent only ever talks to `Retriever`, so swapping backends never touches your
agent code.

## What it gives you

- **`Retriever`** — the single read-side contract an agent consumes.
- **`KnowledgeBase`** — the built-in façade: pairs a core `EmbeddingModel` with a
  `VectorStore` and a `Chunker` to ingest `Document`s and answer text queries.
  It *is* a `Retriever`.
- **`InMemoryVectorStore`** — a pure-Dart, brute-force cosine index with metadata
  filtering and `toJson`/`fromJson` persistence. Zero dependencies.
- **`RecursiveChunker`** (boundary-aware, default) and **`FixedSizeChunker`**.
- **`retrievalTool`** — exposes any `Retriever` as a `Tool` the model can call
  (model-driven RAG).

## Quick start

```dart
import 'package:akashi/akashi.dart';
import 'package:akashi_rag/akashi_rag.dart';
import 'package:akashi_google/akashi_google.dart';

Future<void> main() async {
  final provider = GoogleProvider(apiKey: '...');

  // Built-in path: embed + store locally.
  final kb = KnowledgeBase(
    embedder: provider.embeddingModel('text-embedding-004')!,
    store: InMemoryVectorStore(),
  );
  await kb.addDocuments([
    const Document(id: 'refunds', text: 'Refunds are processed within 5 business days...'),
    const Document(id: 'shipping', text: 'Orders ship in 1–2 days via standard post...'),
  ]);

  // Give the agent a retrieval tool over the knowledge base.
  final agent = ToolLoopAgent(
    model: provider.languageModel('gemini-2.5-flash'),
    instructions: 'Answer using the knowledge base. Cite the snippet you used.',
    tools: [retrievalTool(kb)],
  );

  await for (final event in agent.stream('How long do refunds take?')) {
    if (event is TextDelta) print(event.text);
  }
}
```

See [`example/akashi_rag_example.dart`](example/akashi_rag_example.dart) for a
full run that works **with no API key** (it uses a scripted model and a fake
embedder).

## Connecting a "standard" RAG service

Because retrieval is just `Retriever`, an external service slots in behind the
same seam — it embeds and stores server-side and only needs to answer
`retrieve`:

```dart
final class MyServiceRetriever implements Retriever {
  @override
  Future<List<RetrievedChunk>> retrieve(RetrievalQuery query) async {
    // POST query.text to your RAG endpoint, map the response to RetrievedChunks.
  }
}

final agent = ToolLoopAgent(model: model, tools: [retrievalTool(MyServiceRetriever())]);
```

Concrete external backends (pgvector, Pinecone, HTTP, …) are intended to live in
their own adapter packages — exactly as the durable `CheckpointStore` contract in
core `akashi` is implemented by the separate `akashi_drift` package.

## Scaling ingestion (optional)

`KnowledgeBase.addDocuments` batches embedding calls and needs no extra
dependency. For large corpora that want bounded concurrency, retries, and
timeouts, express ingestion as an [`akashi_workflow`](../akashi_workflow)
`Pipeline` in your own code (chunk → embed → `store.upsert`) — `akashi_rag`
itself stays dependency-light (it depends only on `akashi`).

## Status

v0.4 (package `0.1.0`). Built-in in-memory retrieval, wired in as a tool.
Automatic `prepareStep` context injection, hybrid search, re-ranking, and
external backends are on the roadmap.

## License

MIT.
