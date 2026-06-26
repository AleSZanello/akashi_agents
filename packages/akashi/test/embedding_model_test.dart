import 'package:test/test.dart';

import 'support/fake_embedding_model.dart';

void main() {
  group('EmbeddingModel', () {
    test('returns one vector per input with the expected dimensionality',
        () async {
      final model = FakeEmbeddingModel(dimensions: 4);

      final vectors = await model.embed(['a', 'bb', 'ccc']);

      expect(vectors, hasLength(3));
      expect(vectors.every((v) => v.length == 4), isTrue);
      // Different inputs produce different leading components.
      expect(vectors[0].first, isNot(vectors[1].first));
      expect(model.calls.single, ['a', 'bb', 'ccc']);
    });
  });
}
