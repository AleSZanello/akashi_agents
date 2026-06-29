# Changelog

## 0.3.0

- Coordinated 0.3.0 release (tracks `akashi` 0.3.0).
- `AnthropicProvider.close()` releases the shared HTTP client (a no-op when an
  external client was injected).
- Complete `FinishReason` mapping: `tool_use` → `toolCalls` and `refusal` →
  `contentFilter`, instead of collapsing everything but `max_tokens` to `stop`.
- Streaming now honors `request.cancel`, stopping the upstream drain on
  cancellation.
- Uses the shared `partsToText` / `encodeToolOutput` helpers from `akashi` core.

## 0.2.0

Initial release — Anthropic (Claude) provider adapter over `anthropic_sdk_dart`.

- `AnthropicProvider` + `ClaudeModel` (`LanguageModel`, `StructuredOutputCapable`
  with `toolMode`/`promptOnly`).
- Content-block streaming normalization: text → `TextDeltaPart`, thinking →
  `ReasoningDeltaPart` (carrying the block signature), `tool_use` →
  `ToolCallStartPart` + `input_json` `ToolCallDeltaPart`.
- Leading `SystemMessage`s map to the top-level `system` field; `ToolChoice` →
  Anthropic `tool_choice`; a default `max_tokens` is supplied when unset.
- Offline tests against a mock HTTP client; a runnable `example/`.

Note: reasoning signatures are surfaced on the way out, but `anthropic_sdk_dart`
5.x exposes no thinking *input* block, so prior thinking is not re-sent on
subsequent turns.
