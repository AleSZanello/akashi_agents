# Changelog

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
