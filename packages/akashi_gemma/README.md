# akashi_gemma

**On-device** `LanguageModel` for the [Akashi](https://github.com/Alezanello/akashi_agents)
agent framework, backed by [`flutter_gemma`](https://pub.dev/packages/flutter_gemma).
Proves Akashi's `LanguageModel` contract is not HTTP-bound: run agents fully
offline, or as the primary in a cloud `FallbackModel` (via `akashi_gateway`).

```dart
import 'package:akashi/akashi.dart';
import 'package:akashi_gemma/akashi_gemma.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

final inference = await FlutterGemmaPlugin.instance.createModel(/* ... */);
final chat = await inference.createChat(/* tools, temperature, ... */);
final model = GemmaModel(FlutterGemmaBackend(chat));

final agent = ToolLoopAgent(model: model, tools: [getWeather]);
await agent.run('What should I wear in Oslo?');
```

The `GemmaBackend` seam keeps normalization testable offline (a scripted
backend), while `FlutterGemmaBackend` drives real device inference — including
parallel function calls. Streaming honors `request.cancel` to stop long
on-device generations. Requires Dart ≥3.12 / Flutter ≥3.44.

See [`example/akashi_gemma_example.dart`](example/akashi_gemma_example.dart) for
the offline scripted version that runs without a device.

## Status

v0.3. Resolves standalone (own lockfile, `akashi` path-overridden) because it
depends on the Flutter SDK and `flutter_gemma`.

## License

MIT.
