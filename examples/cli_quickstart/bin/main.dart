import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_gateway/akashi_gateway.dart';
import 'package:akashi_google/akashi_google.dart';

/// A trivial dependency the agent's tools can reach (Akashi's typed DI).
class AppDeps {
  AppDeps(this.weather);
  final WeatherApi weather;
}

/// A stand-in weather service.
class WeatherApi {
  Future<({double tempC, String summary})> current(String city) async {
    // A real implementation would hit a network API here.
    return (tempC: 14.0, summary: 'light rain in $city');
  }
}

/// A tool defined with a typed record input and typed dependencies.
final getWeather = tool<({String city}), AppDeps>(
  name: 'get_weather',
  description: 'Get the current weather for a city.',
  inputSchema: Schema.object(
    {'city': Schema.string(description: 'The city name, e.g. "Bogotá".')},
    required: ['city'],
    fromJson: (json) => (city: json['city']! as String),
  ),
  execute: (input, ctx) async {
    final weather = await ctx.deps.weather.current(input.city);
    return {'tempC': weather.tempC, 'summary': weather.summary};
  },
);

Future<void> main() async {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    stderr.writeln(
      'Set GEMINI_API_KEY to run this example against Gemini.\n'
      'The agent loop itself is covered offline by the tests in '
      'packages/akashi (a FakeLanguageModel drives it with no network).',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  // Register only the providers you import; the registry routes among them by
  // "provider/model" string. (You can also pass a model directly, e.g.
  // GoogleProvider(apiKey: apiKey).languageModel('gemini-2.5-flash').)
  final registry = ProviderRegistry({'google': GoogleProvider(apiKey: apiKey)});

  final agent = ToolLoopAgent<AppDeps>(
    model: registry.model('google/gemini-2.5-flash'),
    instructions: 'You help users dress for the weather. Be concise.',
    tools: [getWeather],
    stopWhen: [stepCountIs(8), hasText()],
  );

  final deps = AppDeps(WeatherApi());

  await for (final event in agent.stream(
    'What should I wear in Bogotá today?',
    deps: deps,
  )) {
    switch (event) {
      case TextDelta(:final text):
        stdout.write(text);
      case ToolCallReady(:final call):
        stdout.writeln('\n[calling ${call.toolName}(${call.input})]');
      case ToolResult(:final result):
        stdout.writeln('[result: ${result.output}]');
      case RunFinish(:final usage):
        stdout.writeln('\n\n— done (${usage.totalTokens} tokens)');
      case ErrorEvent(:final error):
        stderr.writeln('\n[error: $error]');
      default:
        break;
    }
  }
}
