import 'package:akashi/akashi.dart';

/// A deterministic fake [EmbeddingModel] for offline tests.
///
/// Returns a vector of [dimensions] for each input; the values encode the
/// input's length so different inputs get different vectors. Records every
/// [embed] call in [calls] for assertions.
final class FakeEmbeddingModel implements EmbeddingModel {
  /// Creates a fake embedding model emitting [dimensions]-length vectors.
  FakeEmbeddingModel({this.dimensions = 3});

  /// The length of every returned vector.
  final int dimensions;

  /// The inputs of every [embed] call, in order.
  final List<List<String>> calls = [];

  @override
  String get providerId => 'fake';

  @override
  String get modelId => 'fake-embed';

  @override
  Future<List<List<double>>> embed(List<String> inputs) async {
    calls.add(List.of(inputs));
    return [
      for (final input in inputs)
        [for (var i = 0; i < dimensions; i++) (input.length + i).toDouble()],
    ];
  }
}
