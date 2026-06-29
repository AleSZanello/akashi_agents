# akashi_openai

**OpenAI** provider adapter for the [Akashi](https://github.com/Alezanello/akashi_agents)
agent framework. Wraps [`openai_dart`](https://pub.dev/packages/openai_dart)
behind Akashi's `LanguageModel` contract, normalizing OpenAI's streamed content
and index-keyed tool-call argument deltas into Akashi's `ModelStreamPart` union.
Points at any OpenAI-compatible server via `baseUrl`.

```dart
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_openai/akashi_openai.dart';

Future<void> main() async {
  final provider = OpenAIProvider(
    apiKey: Platform.environment['OPENAI_API_KEY']!,
  );

  final agent = ToolLoopAgent(
    model: provider.languageModel('gpt-4o-mini'),
    instructions: 'You are a terse assistant.',
  );

  await for (final event in agent.stream('Say hello in three languages.')) {
    if (event is TextDelta) stdout.write(event.text);
  }
  provider.close(); // release the shared HTTP connection when done
}
```

Tool calling, streaming, structured output, embeddings, and stop conditions all
come from the core [`akashi`](https://pub.dev/packages/akashi) package — this
adapter only translates between Akashi's provider contract and the OpenAI API.

See [`example/akashi_openai_example.dart`](example/akashi_openai_example.dart)
for a tool-using agent end to end.

## Status

v0.3.

## License

MIT.
