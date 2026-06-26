import 'package:akashi/akashi.dart';

import 'fallback_model.dart';

/// Thrown when a model reference names a provider that isn't registered.
class ProviderNotFoundException implements Exception {
  /// Creates the exception for an unknown [providerId], listing the [known] ids.
  ProviderNotFoundException(this.providerId, this.known);

  /// The provider id that could not be resolved.
  final String providerId;

  /// The provider ids that are registered.
  final Iterable<String> known;

  @override
  String toString() => 'ProviderNotFoundException: no provider "$providerId" '
      'is registered. Known providers: ${known.join(', ')}.';
}

/// Resolves `"provider/model"` strings to a [LanguageModel] by routing among the
/// providers a developer has explicitly registered.
///
/// Dart can't auto-discover providers by string (that would defeat Flutter's
/// AOT tree-shaking), so you register the providers you depend on and the
/// registry routes among *those* — only the imported SDKs ship in your app.
///
/// ```dart
/// final registry = ProviderRegistry({
///   'google': GoogleProvider(apiKey: googleKey),
///   'openai': OpenAIProvider(apiKey: openaiKey),
/// });
///
/// final model = registry.model('google/gemini-2.5-flash');
/// final resilient = registry.fallback([
///   'google/gemini-2.5-flash',
///   'openai/gpt-5.1',
/// ]);
/// ```
final class ProviderRegistry {
  /// Creates a registry from a map of provider id to [Provider].
  ///
  /// If [defaultProvider] is set, references without a `provider/` prefix
  /// resolve against it.
  ProviderRegistry(Map<String, Provider> providers, {String? defaultProvider})
      : _providers = {...providers},
        _defaultProvider = defaultProvider;

  final Map<String, Provider> _providers;
  final String? _defaultProvider;

  /// The registered provider ids.
  Iterable<String> get providerIds => _providers.keys;

  /// Add or replace a [provider] under [id].
  void register(String id, Provider provider) => _providers[id] = provider;

  /// Resolve a `"provider/model"` [reference] to a [LanguageModel].
  ///
  /// The split is on the first `/`, so model ids may themselves contain slashes.
  /// Throws [ProviderNotFoundException] for an unknown provider, or
  /// [ArgumentError] when no prefix is given and no default provider is set.
  LanguageModel model(String reference) {
    final (provider, modelId) = _resolve(reference);
    return provider.languageModel(modelId);
  }

  /// Resolve a `"provider/model"` [reference] to an [EmbeddingModel], or null
  /// when that provider does not offer embeddings (isn't an [EmbeddingProvider]).
  ///
  /// Throws the same errors as [model] for an unknown provider or a missing
  /// prefix without a default provider.
  EmbeddingModel? embeddingModel(String reference) {
    final resolved = _resolve(reference);
    final provider = resolved.$1;
    if (provider is! EmbeddingProvider) return null;
    return (provider as EmbeddingProvider).embeddingModel(resolved.$2);
  }

  (Provider, String) _resolve(String reference) {
    final slash = reference.indexOf('/');
    final String providerId;
    final String modelId;

    if (slash == -1) {
      final fallback = _defaultProvider;
      if (fallback == null) {
        throw ArgumentError.value(
          reference,
          'reference',
          'missing "provider/" prefix and no default provider is configured',
        );
      }
      providerId = fallback;
      modelId = reference;
    } else {
      providerId = reference.substring(0, slash);
      modelId = reference.substring(slash + 1);
    }

    final provider = _providers[providerId];
    if (provider == null) {
      throw ProviderNotFoundException(providerId, _providers.keys);
    }
    return (provider, modelId);
  }

  /// Build a [FallbackModel] from an ordered list of `"provider/model"`
  /// [references] (most-preferred first).
  FallbackModel fallback(
    List<String> references, {
    bool Function(Object error)? shouldFailover,
  }) {
    if (references.isEmpty) {
      throw ArgumentError.value(
        references,
        'references',
        'fallback() needs at least one model reference',
      );
    }
    return FallbackModel(
      [for (final reference in references) model(reference)],
      shouldFailover: shouldFailover,
    );
  }
}
