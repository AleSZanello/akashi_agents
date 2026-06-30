import 'package:akashi/akashi.dart';

/// A deterministic bag-of-words [EmbeddingModel] for offline tests.
///
/// Each input becomes a term-frequency vector over a fixed [vocabulary], so
/// texts that share words get a higher cosine similarity — enough to assert
/// retrieval ordering without a network or API key. Records every [embed] call
/// in [calls] for assertions.
final class BagOfWordsEmbedder implements EmbeddingModel {
  /// Creates an embedder over the given [vocabulary].
  BagOfWordsEmbedder(this.vocabulary);

  /// The terms that define each vector's dimensions.
  final List<String> vocabulary;

  /// The inputs of every [embed] call, in order.
  final List<List<String>> calls = [];

  @override
  String get providerId => 'fake';

  @override
  String get modelId => 'bag-of-words';

  @override
  Future<List<List<double>>> embed(List<String> inputs) async {
    calls.add(List.of(inputs));
    return [for (final input in inputs) _vectorize(input)];
  }

  List<double> _vectorize(String text) {
    final counts = <String, int>{};
    for (final word in text.toLowerCase().split(RegExp('[^a-z0-9]+'))) {
      if (word.isEmpty) continue;
      counts[word] = (counts[word] ?? 0) + 1;
    }
    return [for (final term in vocabulary) (counts[term] ?? 0).toDouble()];
  }
}
