import 'package:akashi/akashi.dart';
import 'package:akashi_rag/akashi_rag.dart';
import 'package:test/test.dart';

/// An arbitrary external retriever, to prove any [Retriever] — not just the
/// built-in [KnowledgeBase] — drops into the glue.
final class _FakeExternalRetriever implements Retriever {
  _FakeExternalRetriever(this.hits);

  final List<RetrievedChunk> hits;
  final List<RetrievalQuery> queries = [];

  @override
  Future<List<RetrievedChunk>> retrieve(RetrievalQuery query) async {
    queries.add(query);
    return hits;
  }
}

ToolContext<Object?> _toolContext() => ToolContext<Object?>(
      deps: null,
      toolCallId: 'c1',
      step: 0,
      history: const [],
      cancel: CancellationToken(),
      tracer: const NoopTracer(),
    );

RetrievedChunk _hit(String id, String text, double score, {String? source}) =>
    RetrievedChunk(
      chunk: Chunk(
        id: id,
        text: text,
        documentId: id,
        metadata: source == null ? const {} : {'source': source},
      ),
      score: score,
    );

void main() {
  group('renderChunks', () {
    test('returns a sentinel when there are no hits', () {
      expect(renderChunks(const []), 'No relevant results found.');
    });

    test('numbers hits and prefixes the source when present', () {
      final rendered = renderChunks([
        _hit('a', 'alpha', 0.9, source: 'faq'),
        _hit('b', 'beta', 0.8),
      ]);

      expect(rendered, '[1] (source: faq) alpha\n[2] beta');
    });
  });

  group('retrievalTool', () {
    test('advertises the expected name and input schema', () {
      final tool = retrievalTool<Object?>(_FakeExternalRetriever(const []));

      expect(tool.spec.name, 'search_knowledge_base');
      final schema = tool.spec.inputJsonSchema;
      expect(schema['type'], 'object');
      expect((schema['properties'] as Map).containsKey('query'), isTrue);
      expect(schema['required'], ['query']);
    });

    test('honors a custom name and topK, returning the rendered hits',
        () async {
      final retriever =
          _FakeExternalRetriever([_hit('a', 'alpha', 0.9, source: 'faq')]);
      final tool = retrievalTool<Object?>(retriever, name: 'kb', topK: 7);

      expect(tool.spec.name, 'kb');
      final output = await tool.execute({'query': 'anything'}, _toolContext());

      expect(output, '[1] (source: faq) alpha');
      expect(retriever.queries.single.text, 'anything');
      expect(retriever.queries.single.topK, 7);
    });
  });

  group('end to end', () {
    test('an agent calls the tool and answers from the retrieved context',
        () async {
      final retriever =
          _FakeExternalRetriever([_hit('a', 'Refunds take 5 days.', 0.9)]);

      final agent = ToolLoopAgent<Object?>(
        model: _ScriptedModel([
          [
            const ToolCallCompletePart(
              toolCallId: 'c1',
              toolName: 'search_knowledge_base',
              input: {'query': 'refunds'},
            ),
            const FinishPart(FinishReason.stop),
          ],
          [
            const TextDeltaPart('Refunds take 5 business days.'),
            const FinishPart(FinishReason.stop),
          ],
        ]),
        tools: [retrievalTool(retriever)],
      );

      final toolOutputs = <Object?>[];
      var finalText = '';
      await for (final event in agent.stream('How long do refunds take?')) {
        switch (event) {
          case ToolResult(:final result):
            toolOutputs.add(result.output);
          case RunFinish(:final text):
            finalText = text;
          default:
            break;
        }
      }

      expect(retriever.queries.single.text, 'refunds');
      expect(toolOutputs.single, '[1] Refunds take 5 days.');
      expect(finalText, 'Refunds take 5 business days.');
    });
  });
}

/// A scripted stand-in [LanguageModel] so the end-to-end test runs offline.
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
