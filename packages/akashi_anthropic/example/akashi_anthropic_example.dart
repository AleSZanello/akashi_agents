// A tiny end-to-end example of the Anthropic adapter: a streaming agent that
// calls a typed tool. Run with `dart run example/akashi_anthropic_example.dart`
// (needs ANTHROPIC_API_KEY).
import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_anthropic/akashi_anthropic.dart';

Future<void> main() async {
  final apiKey = Platform.environment['ANTHROPIC_API_KEY'];
  if (apiKey == null) {
    stderr.writeln('Set ANTHROPIC_API_KEY to run this example.');
    exit(64);
  }

  final provider = AnthropicProvider(apiKey: apiKey);
  final agent = ToolLoopAgent<Object?>(
    model: provider.languageModel('claude-haiku-4-5-20251001'),
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
