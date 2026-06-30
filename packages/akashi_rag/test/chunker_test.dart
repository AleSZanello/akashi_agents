import 'package:akashi_rag/akashi_rag.dart';
import 'package:test/test.dart';

void main() {
  group('RecursiveChunker', () {
    test('splits on paragraph boundaries and assigns ids + metadata', () {
      const doc = Document(
        id: 'd',
        text: 'First paragraph.\n\nSecond paragraph.',
        metadata: {'source': 's'},
      );

      final chunks =
          const RecursiveChunker(chunkSize: 20, overlap: 0).chunk(doc);

      expect(
          chunks.map((c) => c.text), ['First paragraph.', 'Second paragraph.']);
      expect(chunks.map((c) => c.id), ['d#0', 'd#1']);
      expect(chunks.every((c) => c.documentId == 'd'), isTrue);
      expect(chunks.every((c) => c.metadata['source'] == 's'), isTrue);
    });

    test('keeps a short document as a single trimmed chunk', () {
      final chunks = const RecursiveChunker()
          .chunk(const Document(id: 'd', text: '  hello world  '));

      expect(chunks, hasLength(1));
      expect(chunks.single.text, 'hello world');
      expect(chunks.single.id, 'd#0');
    });

    test('yields no chunks for whitespace-only text', () {
      expect(
        const RecursiveChunker().chunk(const Document(id: 'd', text: '   ')),
        isEmpty,
      );
    });

    test('overlap repeats boundary tokens between consecutive chunks', () {
      // Word-level pieces with a chunkSize that holds a few of them, so a
      // non-zero overlap slides a window that repeats boundary words.
      const doc = Document(id: 'd', text: 'a b c d e f g h');

      final chunks =
          const RecursiveChunker(chunkSize: 5, overlap: 3).chunk(doc);

      expect(chunks.length, greaterThan(1));
      for (var i = 0; i < chunks.length - 1; i++) {
        final endWords = chunks[i].text.split(' ').toSet();
        final startWords = chunks[i + 1].text.split(' ').toSet();
        expect(
          endWords.intersection(startWords),
          isNotEmpty,
          reason: 'chunk $i and ${i + 1} should overlap',
        );
      }
    });
  });

  group('FixedSizeChunker', () {
    test('slides a fixed window with overlap', () {
      const doc = Document(id: 'd', text: 'abcdefghijklmnopqrst'); // 20 chars

      final chunks =
          const FixedSizeChunker(chunkSize: 10, overlap: 2).chunk(doc);

      expect(chunks.map((c) => c.text), [
        'abcdefghij',
        'ijklmnopqr',
        'qrst',
      ]);
      expect(chunks.map((c) => c.id), ['d#0', 'd#1', 'd#2']);
    });

    test('keeps a short document as one chunk', () {
      final chunks = const FixedSizeChunker(chunkSize: 100, overlap: 10)
          .chunk(const Document(id: 'd', text: 'short'));

      expect(chunks.single.text, 'short');
    });

    test('yields no chunks for whitespace-only text', () {
      expect(
        const FixedSizeChunker(chunkSize: 4, overlap: 1)
            .chunk(const Document(id: 'd', text: '   ')),
        isEmpty,
      );
    });
  });
}
