import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:akashi_rag/akashi_rag.dart';
import 'package:flutter/material.dart';

import '../scripted_model.dart';
import '../widgets/chat_panel.dart';
import 'demo.dart';

final ragDemo = Demo(
  id: 'rag',
  title: 'Retrieval (RAG)',
  tagline: 'Ground answers in a knowledge base',
  pillar: Pillar.foundations,
  icon: Icons.menu_book_outlined,
  blurb:
      'A `KnowledgeBase` (a fake embedder + an in-memory vector store) indexes a '
      'tiny FAQ. Exposed to the agent as a retrieval tool, the model searches it, '
      'and answers from the chunk that comes back. Same `Retriever` seam an '
      'external/"standard" RAG service would plug into — here it runs fully '
      'in-browser, no network.',
  builder: (_) => const _RagDemo(),
  source: _source,
);

/// The little FAQ corpus the agent retrieves from.
const _corpus = [
  Document(
    id: 'refunds',
    text:
        'Refunds are issued to the original payment method within 5 business '
        'days of approval.',
    metadata: {'source': 'refunds'},
  ),
  Document(
    id: 'shipping',
    text:
        'Orders ship within 1 to 2 business days and arrive in about a week '
        'via standard delivery.',
    metadata: {'source': 'shipping'},
  ),
  Document(
    id: 'warranty',
    text:
        'Every product is covered by a 2 year limited warranty against '
        'manufacturing defects.',
    metadata: {'source': 'warranty'},
  ),
  Document(
    id: 'account',
    text:
        'To reset your password, open Settings, choose Security, and follow '
        'the email link we send you.',
    metadata: {'source': 'account'},
  ),
  Document(
    id: 'support',
    text:
        'Support is available Monday to Friday, 9am to 6pm, by chat and email.',
    metadata: {'source': 'support'},
  ),
];

class _RagDemo extends StatefulWidget {
  const _RagDemo();

  @override
  State<_RagDemo> createState() => _RagDemoState();
}

class _RagDemoState extends State<_RagDemo> {
  late final AgentController controller;

  @override
  void initState() {
    super.initState();

    final kb = KnowledgeBase(
      embedder: _BagOfWordsEmbedder(),
      store: InMemoryVectorStore(),
    );
    // Fake embedding is synchronous, so the index is ready before the first
    // message; the corpus is tiny.
    kb.addDocuments(_corpus);

    final model = ScriptedModel(
      respond: (request, _) {
        final result = lastToolResult(request);
        if (result != null) {
          final snippet = _topSnippet(result.output);
          return Turn(
            text: snippet == null
                ? 'I could not find anything relevant in the knowledge base.'
                : 'From the knowledge base: $snippet',
          );
        }
        final query = lastUserText(request).trim();
        return Turn(
          reasoning: 'Let me search the knowledge base for that.',
          toolCalls: [
            ToolCallSpec('search_knowledge_base', {
              'query': query.isEmpty ? 'refunds' : query,
            }),
          ],
        );
      },
    );

    controller = AgentController(
      agent: ToolLoopAgent(
        model: model,
        tools: [retrievalTool(kb)],
        instructions:
            'Answer using the knowledge base. Search before you answer.',
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChatPanel(
      controller: controller,
      placeholder: 'Ask about refunds, shipping, warranty…',
      emptyHint:
          'Ask a question — the agent retrieves from a tiny FAQ, then answers '
          'from what it found.',
      suggestions: const [
        'How long do refunds take?',
        'When will my order ship?',
        'Is there a warranty?',
        'I forgot my password',
      ],
    );
  }
}

/// Pull the first retrieved snippet out of [renderChunks]' output, e.g.
/// `[1] (source: refunds) Refunds are issued…` → `Refunds are issued…`.
String? _topSnippet(Object? output) {
  if (output is! String || output.isEmpty) return null;
  final first = output.split('\n').first;
  final text = first
      .replaceFirst(RegExp(r'^\[\d+\]\s*'), '')
      .replaceFirst(RegExp(r'^\(source:[^)]*\)\s*'), '')
      .trim();
  return text.isEmpty ? null : text;
}

/// A deterministic bag-of-words [EmbeddingModel] so the demo needs no network:
/// each text becomes a term-frequency vector over a fixed vocabulary, so a query
/// that shares words with a document scores higher (cosine similarity).
class _BagOfWordsEmbedder implements EmbeddingModel {
  static const _vocabulary = [
    'refund',
    'refunds',
    'payment',
    'money',
    'back',
    'ship',
    'shipping',
    'order',
    'orders',
    'delivery',
    'arrive',
    'warranty',
    'guarantee',
    'defect',
    'defects',
    'broken',
    'password',
    'reset',
    'login',
    'account',
    'security',
    'settings',
    'support',
    'hours',
    'contact',
    'help',
    'available',
  ];

  @override
  String get providerId => 'fake';

  @override
  String get modelId => 'bag-of-words';

  @override
  Future<List<List<double>>> embed(List<String> inputs) async => [
    for (final input in inputs) _vectorize(input),
  ];

  List<double> _vectorize(String text) {
    final counts = <String, int>{};
    for (final word in text.toLowerCase().split(RegExp('[^a-z0-9]+'))) {
      if (word.isEmpty) continue;
      counts[word] = (counts[word] ?? 0) + 1;
    }
    return [for (final term in _vocabulary) (counts[term] ?? 0).toDouble()];
  }
}

const _source = r'''
// A KnowledgeBase pairs an EmbeddingModel with a VectorStore; it IS a Retriever.
final kb = KnowledgeBase(
  embedder: provider.embeddingModel('text-embedding-004')!,
  store: InMemoryVectorStore(),
);
await kb.addDocuments([
  Document(id: 'refunds', text: 'Refunds are issued within 5 business days...'),
  Document(id: 'shipping', text: 'Orders ship within 1 to 2 business days...'),
]);

// Expose retrieval as a tool the model can call — model-driven RAG.
final agent = ToolLoopAgent(
  model: model,
  tools: [retrievalTool(kb)],
  instructions: 'Answer using the knowledge base. Search before you answer.',
);
controller.send('How long do refunds take?');

// Swapping in a "standard" external RAG service is the same seam:
//   class MyServiceRetriever implements Retriever { ... }
//   tools: [retrievalTool(MyServiceRetriever())]
''';
