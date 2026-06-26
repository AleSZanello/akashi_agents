import 'package:akashi/akashi.dart';

/// A [LanguageModel] that wraps an ordered list of models and fails over to the
/// next one when a call fails.
///
/// Because `FallbackModel` *is a* [LanguageModel], an agent is unaware it is a
/// chain — that is the whole point of the provider abstraction.
///
/// Streaming has one important rule: failover only happens **before** any part
/// has been emitted. Once tokens have streamed, switching models would produce
/// duplicated or garbled output, so a mid-stream failure is rethrown.
///
/// ```dart
/// final model = FallbackModel([
///   primaryProvider.languageModel('gemini-2.5-flash'),
///   backupProvider.languageModel('gpt-5.1'),
/// ], shouldFailover: (e) => e is! ArgumentError);
/// ```
final class FallbackModel implements LanguageModel {
  /// Creates a fallback chain from [models] (most-preferred first).
  ///
  /// [shouldFailover] decides whether a given error triggers a failover
  /// (defaults to failing over on any error).
  FallbackModel(
    List<LanguageModel> models, {
    bool Function(Object error)? shouldFailover,
  })  : _models = List.unmodifiable(models),
        _shouldFailover = shouldFailover ?? _always {
    if (models.isEmpty) {
      throw ArgumentError.value(
        models,
        'models',
        'FallbackModel needs at least one model',
      );
    }
  }

  final List<LanguageModel> _models;
  final bool Function(Object error) _shouldFailover;

  static bool _always(Object error) => true;

  /// The models in this chain, most-preferred first.
  List<LanguageModel> get models => _models;

  /// The most-preferred model.
  LanguageModel get primary => _models.first;

  @override
  String get providerId => primary.providerId;

  @override
  String get modelId => primary.modelId;

  @override
  Future<ModelResponse> generate(ModelRequest request) async {
    for (var i = 0; i < _models.length; i++) {
      try {
        return await _models[i].generate(request);
      } catch (e) {
        if (i == _models.length - 1 || !_shouldFailover(e)) rethrow;
      }
    }
    throw StateError('FallbackModel.generate reached an unreachable state');
  }

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    for (var i = 0; i < _models.length; i++) {
      var emitted = false;
      try {
        await for (final part in _models[i].stream(request)) {
          emitted = true;
          yield part;
        }
        return; // completed without error
      } catch (e) {
        final isLast = i == _models.length - 1;
        // Can't recover once output has started, on the last model, or when the
        // error is not a failover trigger.
        if (emitted || isLast || !_shouldFailover(e)) rethrow;
        // otherwise: fall over to the next model
      }
    }
  }
}
