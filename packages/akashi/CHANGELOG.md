# Changelog

## 0.3.0

Multi-agent + durable-execution milestone (additive; one noted sealed-union
extension).

- **Subagent-as-tool** — `Agent.asTool(...)` (extension) turns any agent into a
  `Tool` a parent can call, running the child fresh with isolated history and
  tools.
- **Handoffs** — `Handoff`/`handoff(...)` expose `transfer_to_<name>` tools; the
  loop switches the active agent's model/instructions/tools while preserving
  history, emitting a new `HandoffEvent`. **API note:** `HandoffEvent` is a new
  subtype of the sealed `AgentEvent` — exhaustive `switch`es without a `default`
  must add a case.
- **First-class escalation** — `EscalationPolicy` objects
  (`escalateOnToolErrors`, `escalateAfterSteps`, `escalateOnLowConfidence`,
  `escalateWhen`) folded into a `prepareStep` hook via `escalate([...])`.
- **Message/Part serialization** — `partToJson`/`partFromJson`,
  `messageToJson`/`messageFromJson`, version-tagged `messagesToJson`, and
  `checkpointToJson`/`checkpointFromJson`. Total encoding (non-JSON tool output
  degrades to a flagged string).
- **Durable human-in-the-loop** — `ToolLoopAgent(durableApproval: true)` with a
  `CheckpointStore` persists a `suspended` checkpoint and throws `Suspended`
  instead of blocking; `resume(checkpointId, decision: ...)` re-enters the
  suspended step. `AgentCheckpoint` gains additive `pendingApproval`,
  `resolvedResults`, and `status` (`CheckpointStatus`) fields.
- **Adapter helpers** — `partsToText` (flatten a message's parts to text) and
  `encodeToolOutput` (string-or-JSON-encode a tool result), shared by the
  first-party provider adapters and available to anyone writing their own.

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
