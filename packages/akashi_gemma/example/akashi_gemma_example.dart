// Running an Akashi agent against an on-device model.
//
// On a real device you build a flutter_gemma chat and wrap it:
//
// ```dart
// import 'package:flutter_gemma/flutter_gemma.dart';
//
// final inference = await FlutterGemmaPlugin.instance.createModel(/* ... */);
// final chat = await inference.createChat(/* tools, temperature, ... */);
// final model = GemmaModel(FlutterGemmaBackend(chat));
//
// // Pair on-device primary with a cloud backup (akashi_gateway):
// // final model = FallbackModel([GemmaModel(...), geminiModel]);
//
// final agent = ToolLoopAgent(model: model, tools: [getWeather]);
// await agent.run('What should I wear in Oslo?');
// ```
//
// The block below runs the same loop offline with a scripted backend (the
// flutter_gemma binding is device-gated), proving the normalization end to end.
import 'package:akashi/akashi.dart';
import 'package:akashi_gemma/akashi_gemma.dart';

class ScriptedBackend implements GemmaBackend {
  ScriptedBackend(this._turns);

  final List<List<GemmaChunk>> _turns;
  int _index = 0;

  @override
  Stream<GemmaChunk> generate(
    List<Message> messages, {
    List<ToolSpec> tools = const [],
  }) async* {
    final turn = _index < _turns.length ? _turns[_index] : const <GemmaChunk>[];
    _index++;
    for (final chunk in turn) {
      yield chunk;
    }
  }
}

final getWeather = tool<({String city}), Object?>(
  name: 'get_weather',
  description: 'Weather for a city.',
  inputSchema: Schema.object(
    {'city': Schema.string()},
    required: ['city'],
    fromJson: (json) => (city: json['city']! as String),
  ),
  execute: (input, ctx) async => 'cold in ${input.city}',
);

Future<void> main() async {
  final model = GemmaModel(
    ScriptedBackend([
      [
        const GemmaFunctionCallChunk('get_weather', {'city': 'Oslo'}),
      ],
      [const GemmaTextChunk('Bring a coat.')],
    ]),
  );

  final agent = ToolLoopAgent<Object?>(model: model, tools: [getWeather]);
  final result = await agent.run('What should I wear in Oslo?');
  print(result.text); // Bring a coat.
}
