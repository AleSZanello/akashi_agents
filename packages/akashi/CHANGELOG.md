# Changelog

## 0.2.0

Production single-agent milestone (additive — no 0.1.0 API breaks).

- Structured output strategy selection in `generateObject`: native
  `jsonSchema` → `toolMode` (forced `final_answer` tool) → `promptOnly`, with
  the validate/repair loop as the universal safety net.
- `StructuredOutputMode` enum and the optional `StructuredOutputCapable`
  capability interface a `LanguageModel` may also implement to declare support.
- `RunOptions.responseFormat` is now threaded into the model request.
- `Output<T>` convenience schemas (`Output.object`/`Output.array`/
  `Output.choice`), drop-in for `generateObject(schema: ...)`.
- Context-engineering helpers for `prepareStep`: `keepLastMessages`,
  `summarizeOlderThan`, and `escalateAfterErrors`.
- `InMemoryCheckpointStore` and `ToolLoopAgent.resume(checkpointId)` to resume a
  checkpointed run from its persisted message history.
- `CallbackApprovalHandler` — an in-process human-in-the-loop approval handler
  backed by a callback.
- `ConsoleTracer` — prints the `run -> step -> tool` span tree for local
  debugging.
- `EmbeddingModel` and the optional `EmbeddingProvider` capability for RAG /
  memory vectors (adapters implement them; `akashi_gateway` resolves them via
  `ProviderRegistry.embeddingModel`).
- Parallel tool execution: a step's tool calls now run concurrently by default
  (`ToolLoopAgent(parallelToolCalls: ...)`, default `true`). Approvals are still
  resolved sequentially, and `ToolResult` events are emitted in call-index order
  once the step's tools settle (previously interleaved with execution).
- `ReasoningDeltaPart.signature` (optional, additive) carries provider reasoning
  signatures (e.g. Anthropic thinking blocks); the loop folds the last signature
  into the accumulated `ReasoningPart`.
- Cross-platform SSE: the SSE line parser is now a pure, platform-agnostic unit
  (`parseSseBytes`/`parseSseLines`), and `HttpSseTransport` selects a streaming
  client per platform via conditional import (a `fetch`-based client on the web,
  where the default client cannot stream response bodies).

## 0.1.0

Initial release — the first working vertical slice.

- Runtime `Schema<T>` builder (string/integer/number/boolean/array/object/raw)
  with `decode` and non-throwing `validate`.
- Sealed `Message` / `Part` and `AgentEvent` unions for exhaustive `switch`.
- `Provider` / `LanguageModel` contract with the low-level `ModelStreamPart`
  union every adapter normalizes to.
- `Tool` + the typed `tool<I, TDeps>` factory and `ToolContext<TDeps>`
  (typed dependency injection).
- Composable `StopCondition`s: `stepCountIs`, `hasText`, `hasToolCall`.
- `Agent<TDeps>` interface + `ToolLoopAgent` streaming tool loop
  (`stream` is the primitive; `run` collects over it).
- `Tracer` interface + `NoopTracer`; pluggable `SseTransport`.
- Seams (no-op in 0.1) for `prepareStep`, checkpointing, and tool approval.
