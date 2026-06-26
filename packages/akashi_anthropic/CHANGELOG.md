# Changelog

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
