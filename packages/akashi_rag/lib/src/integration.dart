import 'package:akashi/akashi.dart';

import 'retrieval.dart';

/// Render retrieved [hits] into a compact, model-friendly context block.
///
/// Each hit is numbered and prefixed with its `source` metadata (when present),
/// so a model can cite which snippet it used. Returns a short sentinel when
/// there are no hits, rather than an empty string the model might ignore.
String renderChunks(List<RetrievedChunk> hits) {
  if (hits.isEmpty) return 'No relevant results found.';
  final buffer = StringBuffer();
  for (var i = 0; i < hits.length; i++) {
    final hit = hits[i];
    final source = hit.chunk.metadata['source'];
    final label = source == null ? '' : ' (source: $source)';
    buffer.writeln('[${i + 1}]$label ${hit.chunk.text}');
  }
  return buffer.toString().trimRight();
}

/// Expose a [Retriever] as an Akashi [Tool] the model can call — model-driven
/// RAG, where the agent itself decides when to look something up.
///
/// A thin wrapper over the core `tool` factory: the model calls it with a
/// `query`, the tool retrieves the top [topK] chunks and returns them via
/// [render] (defaults to [renderChunks]). Works with any `TDeps` because
/// [retriever] is captured in the closure.
///
/// ```dart
/// final agent = ToolLoopAgent(model: model, tools: [retrievalTool(kb)]);
/// ```
Tool<TDeps> retrievalTool<TDeps>(
  Retriever retriever, {
  String name = 'search_knowledge_base',
  String description =
      'Search the knowledge base for information relevant to a query.',
  int topK = 4,
  String Function(List<RetrievedChunk> hits) render = renderChunks,
}) {
  return tool<({String query}), TDeps>(
    name: name,
    description: description,
    inputSchema: Schema.object<({String query})>(
      {
        'query': Schema.string(
          description: 'Natural-language search query.',
        ),
      },
      required: ['query'],
      fromJson: (json) => (query: json['query']! as String),
    ),
    execute: (input, ctx) async {
      final hits = await retriever
          .retrieve(RetrievalQuery(text: input.query, topK: topK));
      return render(hits);
    },
  );
}
