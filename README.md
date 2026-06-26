# Akashi Agents

**A provider-neutral agent framework for Dart & Flutter.**

Most "Agents as a Service" frameworks — Vercel's `eve`/AI SDK, OpenAI Agents SDK,
Pydantic AI, LangGraph, Mastra — live in Python and TypeScript. Akashi brings the
same primitives to Dart so the ~80%-Flutter teams of the world can build agents
without leaving their language.

Akashi does **not** try to be "the first Dart agent framework" (that ship has
sailed — see `langchain_dart`, `dartantic_ai`, and Google's official Genkit Dart).
Instead it leads with the two lanes those tools under-serve:

- **Multi-agent orchestration** — subagent-as-tool with isolated context,
  handoffs, and per-step model escalation.
- **Durability** — checkpoint/resume and human-in-the-loop pauses as a core
  concern, not a bolt-on.

It stays **provider-neutral** (no vendor hardcoded), leans on Dart 3 **sealed
classes + exhaustive `switch`** for message/event modelling, and uses
`Stream<T>` as the native substrate for streaming.

## Status

🚧 **v0.2 — production single-agent.** Beyond the v0.1 core, this milestone adds
reliable structured output (provider-native JSON schema → tool mode → prompt,
with a validate/repair safety net), `prepareStep` context helpers, in-memory
checkpoints + resume, in-process human-in-the-loop approval, embeddings, parallel
tool execution, OpenTelemetry tracing, MCP tools, optional `build_runner`
codegen, cross-platform (web) streaming, and OpenAI + Anthropic adapters
alongside Gemini — all provider-neutral and offline-tested. Multi-agent
orchestration, durable cross-process execution, and Flutter integration (v0.3)
are next.

## Monorepo layout

| Package | Status | Purpose |
|---|---|---|
| [`akashi`](packages/akashi) | v0.2 | Pure-Dart core: agent loop, tools, schema, sealed message/event unions, provider + embedding contracts, structured-output strategy, context helpers, in-memory checkpoints + HITL, parallel tools, cross-platform SSE. No provider SDKs. |
| [`akashi_google`](packages/akashi_google) | v0.2 | Gemini adapter over `googleai_dart` — structured output, tool choice, embeddings. |
| [`akashi_openai`](packages/akashi_openai) | v0.2 | OpenAI adapter over `openai_dart`. |
| [`akashi_anthropic`](packages/akashi_anthropic) | v0.2 | Anthropic adapter over `anthropic_sdk_dart` (thinking + tool_use). |
| [`akashi_gateway`](packages/akashi_gateway) | v0.2 | Model routing (`provider/model` strings) + `FallbackModel` + embedding routing. |
| [`akashi_mcp`](packages/akashi_mcp) | v0.2 | Model Context Protocol tools over `dart_mcp`. |
| [`akashi_otel`](packages/akashi_otel) | v0.2 | OpenTelemetry tracing exporter. |
| [`akashi_gen`](packages/akashi_gen) | v0.2 | Optional `build_runner` codegen for tool input schemas. |
| `akashi_ollama` | stub | Ollama adapter over `ollama_dart`. |
| `akashi_gemma` | stub (v0.3) | On-device inference over `flutter_gemma`. |
| `akashi_drift` | stub (v0.3) | Durable SQLite checkpoint store over `drift`. |
| `akashi_flutter` | stub (v0.3) | Reactive controllers, widgets, Isolate offload. |
| [`examples/cli_quickstart`](examples/cli_quickstart) | v0.1 | Streaming Gemini agent that calls a typed tool. |
| [`examples/production_agent`](examples/production_agent) | v0.2 | Combined example: provider routing, structured output, OTel tracing, approval gate, checkpoints. |

## Quick start

```dart
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_google/akashi_google.dart';

void main() async {
  final agent = ToolLoopAgent(
    model: GoogleProvider(apiKey: Platform.environment['GEMINI_API_KEY']!)
        .languageModel('gemini-2.5-flash'),
    instructions: 'You are a terse assistant.',
  );

  await for (final event in agent.stream('Write a haiku about Dart isolates.')) {
    if (event is TextDelta) stdout.write(event.text);
  }
}
```

See [`examples/cli_quickstart`](examples/cli_quickstart) for a tool-using,
streaming agent end to end.

## Developing

This is a [Dart pub workspace](https://dart.dev/tools/pub/workspaces) driven by
[Melos](https://melos.invertase.dev):

```bash
dart pub get              # resolves the whole workspace
dart analyze              # analyze everything
melos run test            # run all package tests
```

## Roadmap

- **v0.1** — core + Gemini adapter + CLI demo (the vertical slice).
- **v0.2** — structured output + self-repair, `prepareStep`, codegen, OpenAI/
  Anthropic adapters, MCP, OTel, embeddings, parallel tools, cross-platform
  streaming, in-memory checkpoints + HITL. ← *here*
- **v0.3** — multi-agent (subagent-as-tool, handoffs), durable checkpoints,
  Flutter integration, on-device Gemma.

## License

MIT — see [LICENSE](LICENSE).
