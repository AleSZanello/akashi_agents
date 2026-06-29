# akashi_anthropic

**Anthropic (Claude)** provider adapter for the [Akashi](https://github.com/Alezanello/akashi_agents)
agent framework. Wraps [`anthropic_sdk_dart`](https://pub.dev/packages/anthropic_sdk_dart)
behind Akashi's `LanguageModel` contract, normalizing Claude's content blocks
(text, thinking, `tool_use`) into Akashi's `ModelStreamPart` union.

```dart
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_anthropic/akashi_anthropic.dart';

Future<void> main() async {
  final provider = AnthropicProvider(
    apiKey: Platform.environment['ANTHROPIC_API_KEY']!,
  );

  final agent = ToolLoopAgent(
    model: provider.languageModel('claude-haiku-4-5-20251001'),
    instructions: 'You are a terse assistant.',
  );

  await for (final event in agent.stream('Say hello in three languages.')) {
    if (event is TextDelta) stdout.write(event.text);
  }
  provider.close(); // release the shared HTTP connection when done
}
```

Tool calling, streaming, structured output, and stop conditions all come from the
core [`akashi`](https://pub.dev/packages/akashi) package — this adapter only
translates between Akashi's provider contract and the Anthropic Messages API.

See [`example/akashi_anthropic_example.dart`](example/akashi_anthropic_example.dart)
for a tool-using agent end to end.

## Status

v0.3.

## License

MIT.
