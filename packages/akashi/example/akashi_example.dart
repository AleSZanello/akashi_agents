// A self-contained tour of the akashi core: a streaming `ToolLoopAgent` that
// calls a typed tool — driven by a scripted in-process model, so it runs with no
// API key. Swap `ScriptedModel` for a real provider adapter (akashi_google,
// akashi_openai, akashi_anthropic, ...) to talk to a live LLM.
//
// Run with: dart run example/akashi_example.dart
import 'dart:io';

import 'package:akashi/akashi.dart';

/// A scripted stand-in [LanguageModel] so the example runs offline: the first
/// turn calls `get_weather`, the second answers.
class ScriptedModel implements LanguageModel {
  ScriptedModel(this._turns);

  final List<List<ModelStreamPart>> _turns;
  int _index = 0;

  @override
  String get providerId => 'scripted';

  @override
  String get modelId => 'scripted';

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    final turn = _index < _turns.length
        ? _turns[_index]
        : const <ModelStreamPart>[FinishPart(FinishReason.stop)];
    _index++;
    for (final part in turn) {
      yield part;
    }
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async => ModelResponse(
        message: const AssistantMessage([]),
        finishReason: FinishReason.stop,
        usage: Usage.zero,
      );
}

Future<void> main() async {
  final agent = ToolLoopAgent<Object?>(
    model: ScriptedModel([
      [
        const ToolCallCompletePart(
          toolCallId: 'c1',
          toolName: 'get_weather',
          input: {'city': 'Oslo'},
        ),
        const FinishPart(FinishReason.stop),
      ],
      [
        const TextDeltaPart('Bring a warm coat — it is cold in Oslo.'),
        const FinishPart(FinishReason.stop),
      ],
    ]),
    instructions: 'You are a terse weather assistant.',
    tools: [
      tool<({String city}), Object?>(
        name: 'get_weather',
        description: 'Current weather for a city.',
        inputSchema: Schema.object<({String city})>(
          {'city': Schema.string()},
          required: ['city'],
          fromJson: (j) => (city: j['city']! as String),
        ),
        execute: (input, ctx) async => 'It is 4°C and clear in ${input.city}.',
      ),
    ],
  );

  await for (final event in agent.stream('What should I wear in Oslo?')) {
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
