# akashi_google

Google **Gemini** provider adapter for the [Akashi](https://github.com/Alezanello/akashi_agents)
agent framework. Wraps [`googleai_dart`](https://pub.dev/packages/googleai_dart)
behind Akashi's `LanguageModel` contract.

```dart
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_google/akashi_google.dart';

void main() async {
  final provider = GoogleProvider(
    apiKey: Platform.environment['GEMINI_API_KEY']!,
  );

  final agent = ToolLoopAgent(
    model: provider.languageModel('gemini-2.5-flash'),
    instructions: 'You are a terse assistant.',
  );

  await for (final event in agent.stream('Say hello in three languages.')) {
    if (event is TextDelta) stdout.write(event.text);
  }
}
```

Tool calling, streaming, and stop conditions all come from the core
[`akashi`](https://pub.dev/packages/akashi) package — this adapter only
translates between Akashi's provider contract and the Gemini API.

## Status

v0.1.

## License

MIT.
