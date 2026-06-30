// A self-contained tour of akashi_rag: build a KnowledgeBase, give an agent a
// retrieval tool over it, and answer a question grounded in the indexed docs.
//
// It runs offline with NO API key: a bag-of-words embedder stands in for a real
// embedding model, and a scripted model stands in for a real LLM. To go live,
// swap `_BagOfWordsEmbedder` for `provider.embeddingModel('text-embedding-004')`
// and `_ScriptedModel` for `provider.languageModel('gemini-2.5-flash')` (see the
// comment at the bottom).
//
// Run with: dart run example/akashi_rag_example.dart
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_rag/akashi_rag.dart';

Future<void> main() async {
  // 1. Build a knowledge base and index a tiny corpus.
  final kb = KnowledgeBase(
    embedder: _BagOfWordsEmbedder(const [
      'refund',
      'refunds',
      'shipping',
      'ship',
      'warranty',
      'days',
      'return',
    ]),
    store: InMemoryVectorStore(),
  );
  await kb.addDocuments(const [
    Document(
      id: 'refunds',
      text: 'Refunds are processed within 5 business days of approval.',
      metadata: {'source': 'refunds'},
    ),
    Document(
      id: 'shipping',
      text: 'Orders ship within 1 to 2 days via standard post.',
      metadata: {'source': 'shipping'},
    ),
    Document(
      id: 'warranty',
      text: 'Every product carries a 2 year limited warranty.',
      metadata: {'source': 'warranty'},
    ),
  ]);

  // 2. Give an agent a retrieval tool over the knowledge base.
  final agent = ToolLoopAgent<Object?>(
    model: _ScriptedModel([
      [
        const ToolCallCompletePart(
          toolCallId: 'c1',
          toolName: 'search_knowledge_base',
          input: {'query': 'how long do refunds take'},
        ),
        const FinishPart(FinishReason.stop),
      ],
      [
        const TextDeltaPart('Refunds are processed within 5 business days.'),
        const FinishPart(FinishReason.stop),
      ],
    ]),
    instructions: 'Answer using the knowledge base. Cite the snippet you used.',
    tools: [retrievalTool(kb)],
  );

  // 3. Run a query end to end.
  await for (final event in agent.stream('How long do refunds take?')) {
    switch (event) {
      case ToolResult(:final result):
        stdout.writeln('[retrieved]\n${result.output}\n');
      case TextDelta(:final text):
        stdout.write(text);
      case RunFinish():
        stdout.writeln();
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Going live — swap the fakes for real providers (akashi_google shown):
  //
  //   final provider = GoogleProvider(apiKey: Platform.environment['GEMINI_API_KEY']!);
  //   final kb = KnowledgeBase(
  //     embedder: provider.embeddingModel('text-embedding-004')!,
  //     store: InMemoryVectorStore(),
  //   );
  //   final agent = ToolLoopAgent(
  //     model: provider.languageModel('gemini-2.5-flash'),
  //     tools: [retrievalTool(kb)],
  //   );
  //
  // Scaling ingestion — for a large corpus, express chunk → embed → upsert as an
  // akashi_workflow Pipeline (in your own code; akashi_rag depends only on akashi):
  //
  //   final ingest = Pipeline.input<Document>()
  //       .stage('chunk', (doc, _) async => chunker.chunk(doc))
  //       .stage('embed', (chunks, _) async => /* embed + zip into EmbeddedChunks */)
  //       .stage('store', (embedded, _) async { await store.upsert(embedded); });
  //   await workflow.pipeline(documents, ingest); // bounded concurrency + retries
  // ---------------------------------------------------------------------------
}

/// A deterministic bag-of-words embedder so the example needs no API key.
final class _BagOfWordsEmbedder implements EmbeddingModel {
  _BagOfWordsEmbedder(this.vocabulary);

  final List<String> vocabulary;

  @override
  String get providerId => 'fake';

  @override
  String get modelId => 'bag-of-words';

  @override
  Future<List<List<double>>> embed(List<String> inputs) async => [
        for (final input in inputs)
          [
            for (final term in vocabulary)
              input.toLowerCase().contains(term) ? 1.0 : 0.0,
          ],
      ];
}

/// A scripted stand-in [LanguageModel]: first turn calls the retrieval tool, the
/// second answers.
final class _ScriptedModel implements LanguageModel {
  _ScriptedModel(this._turns);

  final List<List<ModelStreamPart>> _turns;
  int _index = 0;

  @override
  String get providerId => 'scripted';

  @override
  String get modelId => 'scripted';

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    final turn = _index < _turns.length
        ? _turns[_index]
        : const <ModelStreamPart>[FinishPart(FinishReason.stop)];
    _index++;
    for (final part in turn) {
      yield part;
    }
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async =>
      const ModelResponse(
        message: AssistantMessage([]),
        finishReason: FinishReason.stop,
        usage: Usage.zero,
      );
}
