# Changelog

## 0.2.0

- `ProviderRegistry.embeddingModel("provider/model")` resolves an
  `EmbeddingModel` from a provider that implements `EmbeddingProvider`, or
  returns null when it does not.

## 0.1.0

Initial release.

- `ProviderRegistry` — resolve `"provider/model"` strings to a `LanguageModel`,
  with an optional default provider and a `fallback()` helper.
- `FallbackModel` — a `LanguageModel` that fails over across an ordered chain of
  models (failover only before any streamed output; mid-stream failures are
  rethrown).
- `ProviderNotFoundException` for unregistered providers.
