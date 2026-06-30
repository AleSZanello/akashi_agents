import 'package:akashi_rag/akashi_rag.dart';
import 'package:test/test.dart';

import 'support/bag_of_words_embedder.dart';

void main() {
  group('KnowledgeBase', () {
    BagOfWordsEmbedder embedder() => BagOfWordsEmbedder(
          const [
            'cat',
            'dog',
            'fish',
            'bird',
            'rocket',
            'planet',
            'star',
            'space'
          ],
        );

    const pets = Document(
      id: 'pets',
      text: 'cat dog fish bird',
      metadata: {'source': 'pets'},
    );
    const astronomy = Document(
      id: 'astronomy',
      text: 'rocket planet star space',
      metadata: {'source': 'astronomy'},
    );

    test('retrieves the topically-closest document first', () async {
      final kb =
          KnowledgeBase(embedder: embedder(), store: InMemoryVectorStore());
      await kb.addDocuments([pets, astronomy]);

      final hits =
          await kb.retrieve(const RetrievalQuery(text: 'tell me about a cat'));

      expect(hits.first.chunk.documentId, 'pets');
      expect(hits.first.score, greaterThan(0));
    });

    test('removeDocument drops that document from results', () async {
      final store = InMemoryVectorStore();
      final kb = KnowledgeBase(embedder: embedder(), store: store);
      await kb.addDocuments([pets, astronomy]);

      await kb.removeDocument('pets');

      expect(await store.count, 1);
      final hits = await kb.retrieve(const RetrievalQuery(text: 'cat'));
      expect(hits.every((h) => h.chunk.documentId != 'pets'), isTrue);
    });

    test('skips documents that chunk to nothing', () async {
      final store = InMemoryVectorStore();
      final kb = KnowledgeBase(embedder: embedder(), store: store);

      await kb.addDocuments([const Document(id: 'blank', text: '   '), pets]);

      expect(await store.count, 1);
    });

    test('embeds in batches but indexes every chunk', () async {
      final store = InMemoryVectorStore();
      final embed = embedder();
      final kb =
          KnowledgeBase(embedder: embed, store: store, embedBatchSize: 1);

      await kb.addDocuments([pets, astronomy]);

      // Two single-chunk docs with embedBatchSize 1 => two embed calls on ingest.
      expect(embed.calls.where((c) => c.length == 1), hasLength(2));
      expect(await store.count, 2);
    });
  });
}
