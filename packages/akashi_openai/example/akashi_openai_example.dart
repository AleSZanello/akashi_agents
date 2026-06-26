// A tiny end-to-end example of the OpenAI adapter: a streaming agent that
// calls a typed tool. Run with `dart run example/akashi_openai_example.dart`
// (needs OPENAI_API_KEY).
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_openai/akashi_openai.dart';

Future<void> main() async {
  final apiKey = Platform.environment['OPENAI_API_KEY'];
  if (apiKey == null) {
    stderr.writeln('Set OPENAI_API_KEY to run this example.');
    exit(64);
  }

  final provider = OpenAIProvider(apiKey: apiKey);
  final agent = ToolLoopAgent<Object?>(
    model: provider.languageModel('gpt-4o-mini'),
    tools: [
      tool<({String city}), Object?>(
        name: 'get_weather',
        description: 'Current weather for a city.',
        inputSchema: Schema.object<({String city})>(
          {'city': Schema.string()},
          required: ['city'],
          fromJson: (j) => (city: j['city']! as String),
        ),
        execute: (input, ctx) => 'It is 7°C and rainy in ${input.city}.',
      ),
    ],
  );

  await for (final event in agent.stream('What should I wear in Oslo today?')) {
    switch (event) {
      case TextDelta(:final text):
        stdout.write(text);
      case ToolResult(:final result):
        stdout.writeln('\n[tool ${result.toolName} -> ${result.output}]');
      case RunFinish():
        stdout.writeln();
      default:
        break;
    }
  }
}
