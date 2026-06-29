# Changelog

## 0.3.0

- Coordinated 0.3.0 release (tracks `akashi` 0.3.0).
- `OpenAIProvider.close()` releases the shared HTTP client (a no-op when an
  external client was injected).
- Complete `FinishReason` mapping: `tool_calls` / `function_call` → `toolCalls`
  and `content_filter` → `contentFilter`, instead of only `length`-or-`stop`.
- Streaming now honors `request.cancel`, stopping the upstream drain on
  cancellation.
- Malformed tool-call arguments are preserved under `_raw` rather than silently
  decoded to an empty map.
- Uses the shared `partsToText` / `encodeToolOutput` helpers from `akashi` core.

## 0.2.0

Initial release — OpenAI provider adapter over `openai_dart`.

- `OpenAIProvider` + `OpenAIModel` (`LanguageModel`, `StructuredOutputCapable`
  with `jsonSchema`/`toolMode`/`promptOnly`).
- Streaming normalization of OpenAI's index-keyed tool-call argument deltas into
  `ToolCallStartPart` + `ToolCallDeltaPart` (reassembled by the loop).
- `responseFormat` → `json_schema` and `ToolChoice` → `tool_choice` mapping.
- `OpenAIEmbeddingModel` + `EmbeddingProvider`.
- Offline tests against a mock HTTP client; a runnable `example/`.
