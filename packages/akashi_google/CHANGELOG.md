# Changelog

## 0.3.0

- Coordinated 0.3.0 release (tracks `akashi` 0.3.0).
- `GoogleProvider.close()` releases the shared HTTP client (a no-op when an
  external client was injected).
- Complete `FinishReason` mapping: the safety / recitation / blocklist family
  now surfaces as `contentFilter` instead of `other`.
- Streaming now honors `request.cancel`, stopping the upstream drain on
  cancellation.

## 0.2.0

- Structured output: `GeminiModel` declares `StructuredOutputCapable`
  (`jsonSchema`/`toolMode`/`promptOnly`) and wires `JsonResponseFormat` onto
  Gemini's `responseMimeType` + `responseSchema`.
- `ToolChoice` mapping: `auto`/`any`/`none`/specific now map to
  `toolConfig.functionCallingConfig` (with `allowedFunctionNames` for a specific
  tool); previously only `auto` was honored.
- Embeddings: `GoogleProvider` implements `EmbeddingProvider`, returning a
  `GeminiEmbeddingModel` over `embedContent`.
- First offline `test/` (against a mock HTTP client) and a runnable `example/`.

## 0.1.0

Initial release.

- `GoogleProvider` and a Gemini `LanguageModel` over `googleai_dart` 8.x.
- Maps Akashi `ModelRequest` (messages, tools, tool choice) to Gemini
  `generateContent` / `streamGenerateContent`.
- Normalizes streamed text, function calls, finish reason, and usage metadata
  into Akashi's `ModelStreamPart` union.
