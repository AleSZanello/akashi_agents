# Changelog

## 0.3.0

- Initial release of the on-device adapter.
- `GemmaModel` implements `LanguageModel` over a `GemmaBackend` seam,
  normalizing on-device tokens → `TextDeltaPart`, thinking → `ReasoningDeltaPart`,
  and function calls → `ToolCallCompletePart`. No HTTP — proves the contract is
  not transport-bound. Pairs with `akashi_gateway`'s `FallbackModel`. Streaming
  honors `request.cancel` to stop long on-device generation.
- `FlutterGemmaBackend` wraps flutter_gemma 1.x's `InferenceChat` for real device
  inference (including parallel function calls); the `GemmaBackend` seam keeps
  normalization testable offline. Requires Dart ≥3.12 / Flutter ≥3.44.
- `GemmaProvider` mints `GemmaModel`s over a shared backend.
