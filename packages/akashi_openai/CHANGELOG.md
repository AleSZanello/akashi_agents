# Changelog

## 0.2.0

Initial release — OpenAI provider adapter over `openai_dart`.

- `OpenAIProvider` + `OpenAIModel` (`LanguageModel`, `StructuredOutputCapable`
  with `jsonSchema`/`toolMode`/`promptOnly`).
- Streaming normalization of OpenAI's index-keyed tool-call argument deltas into
  `ToolCallStartPart` + `ToolCallDeltaPart` (reassembled by the loop).
- `responseFormat` → `json_schema` and `ToolChoice` → `tool_choice` mapping.
- `OpenAIEmbeddingModel` + `EmbeddingProvider`.
- Offline tests against a mock HTTP client; a runnable `example/`.
