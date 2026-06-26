import 'package:akashi/akashi.dart';
import 'package:akashi_gateway/akashi_gateway.dart';
import 'package:test/test.dart';

final class _EmbedProvider implements Provider, EmbeddingProvider {
  @override
  String get id => 'embed';

  @override
  LanguageModel languageModel(String modelId) => throw UnimplementedError();

  @override
  EmbeddingModel? embeddingModel(String modelId) =>
      _FakeEmbeddingModel(modelId);
}

final class _PlainProvider implements Provider {
  @override
  String get id => 'plain';

  @override
  LanguageModel languageModel(String modelId) => throw UnimplementedError();
}

final class _FakeEmbeddingModel implements EmbeddingModel {
  _FakeEmbeddingModel(this.modelId);

  @override
  String get providerId => 'embed';

  @override
  final String modelId;

  @override
  Future<List<List<double>>> embed(List<String> inputs) async => [
        for (final _ in inputs) const [0.0, 1.0]
      ];
}

void main() {
  group('ProviderRegistry.embeddingModel', () {
    test('resolves an embedding model from an EmbeddingProvider', () {
      final registry = ProviderRegistry({'embed': _EmbedProvider()});

      final model = registry.embeddingModel('embed/text-embedding-3');

      expect(model, isNotNull);
      expect(model!.modelId, 'text-embedding-3');
    });

    test('returns null when the provider does not offer embeddings', () {
      final registry = ProviderRegistry({'plain': _PlainProvider()});

      expect(registry.embeddingModel('plain/anything'), isNull);
    });

    test('throws for an unknown provider', () {
      final registry = ProviderRegistry({'embed': _EmbedProvider()});

      expect(
        () => registry.embeddingModel('nope/x'),
        throwsA(isA<ProviderNotFoundException>()),
      );
    });
  });
}
