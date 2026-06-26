# akashi

Provider-neutral **core** of the [Akashi](https://github.com/Alezanello/akashi_agents)
agent framework for Dart & Flutter. Pure Dart — no provider SDKs, no build step
required.

You almost always pair this with a provider adapter such as
[`akashi_google`](https://pub.dev/packages/akashi_google).

## What's in here

- **`ToolLoopAgent`** — a streaming tool-loop agent. `stream()` is the
  primitive; `run()` collects over it, so streaming and buffered paths can
  never diverge.
- **`Agent<TDeps>`** — the agent contract (an interface, not just a class), so
  custom loops (durable, multi-agent) can drop in later without changing callers.
- **`tool<I, TDeps>(...)`** — define a tool from a description, a typed input
  `Schema<I>`, and an `execute` callback that receives typed input plus a typed
  `ToolContext<TDeps>` (dependency injection).
- **`Schema<T>`** — a zero-codegen runtime schema builder. Optional `build_runner`
  codegen (`akashi_gen`, later) emits the same type.
- **Sealed unions** — `Message`/`Part` and `AgentEvent` for exhaustive `switch`.
- **`StopCondition`** — composable stop conditions (`stepCountIs`, `hasText`,
  `hasToolCall`).

## Example

```dart
import 'package:akashi/akashi.dart';

class Deps {
  Deps(this.weather);
  final WeatherApi weather;
}

final getWeather = tool<({String city}), Deps>(
  name: 'get_weather',
  description: 'Current weather for a city.',
  inputSchema: Schema.object(
    {'city': Schema.string(description: 'City name')},
    required: ['city'],
    fromJson: (j) => (city: j['city']! as String),
  ),
  execute: (input, ctx) async {
    final w = await ctx.deps.weather.current(input.city);
    return {'tempC': w.tempC, 'summary': w.summary};
  },
);

// Pair with a provider adapter to get a `LanguageModel`, then:
final agent = ToolLoopAgent<Deps>(
  model: model,
  instructions: 'Help users dress for the weather.',
  tools: [getWeather],
  stopWhen: [stepCountIs(8), hasText()],
);

final result = await agent.run('What should I wear in Bogotá today?',
    deps: Deps(weatherApi));
print(result.text);
```

Streaming, with an exhaustive `switch`:

```dart
await for (final event in agent.stream('Tell me a 3-sentence story.')) {
  switch (event) {
    case TextDelta(:final text):       stdout.write(text);
    case ToolCallReady(:final call):   print('\n[tool: ${call.toolName}]');
    case RunFinish(:final usage):      print('\n(${usage.totalTokens} tokens)');
    case ErrorEvent(:final error):     stderr.writeln('error: $error');
    default:                            break;
  }
}
```

## Status

v0.1. See the [repository roadmap](https://github.com/Alezanello/akashi_agents)
for multi-agent orchestration and durable execution (v0.2–v0.3).

## License

MIT.
