import 'package:akashi_rag/akashi_rag.dart';
import 'package:test/test.dart';

EmbeddedChunk _chunk(
  String id,
  List<double> embedding, {
  String documentId = 'doc',
  String text = 'text',
  Map<String, Object?> metadata = const {},
}) =>
    EmbeddedChunk(
      chunk:
          Chunk(id: id, text: text, documentId: documentId, metadata: metadata),
      embedding: embedding,
    );

void main() {
  group('InMemoryVectorStore', () {
    test('upsert is idempotent by chunk id (latest wins)', () async {
      final store = InMemoryVectorStore();

      await store.upsert([
        _chunk('a', [1, 0], text: 'first')
      ]);
      await store.upsert([
        _chunk('a', [1, 0], text: 'second')
      ]);

      expect(await store.count, 1);
      final hits = await store.search([1, 0]);
      expect(hits.single.chunk.text, 'second');
    });

    test('search ranks by cosine similarity and truncates to topK', () async {
      final store = InMemoryVectorStore();
      await store.upsert([
        _chunk('aligned', [1, 0]),
        _chunk('diagonal', [1, 1]),
        _chunk('orthogonal', [0, 1]),
      ]);

      final hits = await store.search([1, 0], topK: 2);

      expect(hits.map((h) => h.chunk.id), ['aligned', 'diagonal']);
      expect(hits.first.score, closeTo(1.0, 1e-9));
      expect(hits[1].score, closeTo(0.70710678, 1e-6));
    });

    test('deleteDocument removes every chunk of that document', () async {
      final store = InMemoryVectorStore();
      await store.upsert([
        _chunk('a#0', [1, 0], documentId: 'a'),
        _chunk('a#1', [0, 1], documentId: 'a'),
        _chunk('b#0', [1, 1], documentId: 'b'),
      ]);

      await store.deleteDocument('a');

      expect(await store.count, 1);
      final hits = await store.search([1, 1]);
      expect(hits.single.chunk.documentId, 'b');
    });

    test('filter keeps only chunks matching every metadata entry', () async {
      final store = InMemoryVectorStore();
      await store.upsert([
        _chunk('en', [1, 0], metadata: {'lang': 'en'}),
        _chunk('es', [1, 0], metadata: {'lang': 'es'}),
      ]);

      final hits = await store.search([1, 0], filter: {'lang': 'es'});

      expect(hits.single.chunk.id, 'es');
    });

    test('toJson / fromJson round-trips the index', () async {
      final store = InMemoryVectorStore();
      await store.upsert([
        _chunk('a', [0.5, 0.25],
            documentId: 'd', text: 'hi', metadata: {'source': 's'}),
      ]);

      final restored = InMemoryVectorStore.fromJson(store.toJson());

      expect(await restored.count, 1);
      final hit = (await restored.search([0.5, 0.25])).single;
      expect(hit.chunk.id, 'a');
      expect(hit.chunk.text, 'hi');
      expect(hit.chunk.metadata['source'], 's');
      expect(hit.score, closeTo(1.0, 1e-9));
    });
  });
}
