# akashi_gateway

Model routing and provider fallback for the [Akashi](https://github.com/Alezanello/akashi_agents)
agent framework.

This is a thin **runtime routing layer** that sits on top of Akashi's
per-provider adapter packages — it routes among the providers you import, it
does **not** bundle every vendor SDK.

## ProviderRegistry

Resolve `"provider/model"` strings against the providers you register:

```dart
import 'package:akashi/akashi.dart';
import 'package:akashi_gateway/akashi_gateway.dart';
import 'package:akashi_google/akashi_google.dart';

final registry = ProviderRegistry({
  'google': GoogleProvider(apiKey: googleKey),
  // 'openai': OpenAIProvider(apiKey: openaiKey),  // add what you import
});

final agent = ToolLoopAgent(
  model: registry.model('google/gemini-2.5-flash'),
  instructions: 'You are helpful.',
);
```

> Dart can't auto-discover providers by string (that would defeat Flutter's AOT
> tree-shaking), so you register the providers you depend on and the registry
> routes among *those*. Only the SDKs you import ship in your app.

## FallbackModel

A `LanguageModel` that fails over across an ordered chain — the agent never knows
it's a chain:

```dart
final resilient = registry.fallback([
  'google/gemini-2.5-flash',
  'openai/gpt-5.1',
], shouldFailover: (e) => e is! ArgumentError);

final agent = ToolLoopAgent(model: resilient, ...);
```

Failover happens only **before** any streamed output. Once tokens have started
flowing, switching models would garble the output, so a mid-stream failure is
rethrown.

## Status

v0.1.

## License

MIT.
