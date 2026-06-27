import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';

import '../scripted_model.dart';
import '../widgets/chat_panel.dart';
import 'demo.dart';

final toolCallingDemo = Demo(
  id: 'tool-calling',
  title: 'Typed tool calling',
  tagline: 'Schema-typed tools, decoded for you',
  pillar: Pillar.foundations,
  icon: Icons.handyman_outlined,
  blurb: 'Tools are defined with a typed input `Schema`. The model emits a tool '
      'call, Akashi decodes the JSON into your typed record, runs `execute`, and '
      'feeds the result back so the model can answer. Watch the call chip and '
      'its result appear inline.',
  builder: (_) => const _ToolCallingDemo(),
  source: _source,
);

/// A typed weather tool — `Schema.object` decodes the model's JSON into a record.
Tool<Object?> _weatherTool() => tool<({String city}), Object?>(
      name: 'get_weather',
      description: 'Get the current weather for a city.',
      inputSchema: Schema.object(
        {'city': Schema.string()},
        required: ['city'],
        fromJson: (json) => (city: json['city']! as String),
      ),
      execute: (input, ctx) async => '18°C, partly cloudy, light breeze',
    );

class _ToolCallingDemo extends StatefulWidget {
  const _ToolCallingDemo();

  @override
  State<_ToolCallingDemo> createState() => _ToolCallingDemoState();
}

class _ToolCallingDemoState extends State<_ToolCallingDemo> {
  late final AgentController controller;

  @override
  void initState() {
    super.initState();
    final model = ScriptedModel(
      respond: (request, _) {
        final result = lastToolResult(request);
        if (result != null) {
          return Turn(
            text: 'Right now it’s ${result.output}. '
                'Want a forecast for later in the week?',
          );
        }
        final city = lastUserText(request).trim();
        return Turn(
          toolCalls: [
            ToolCallSpec('get_weather', {'city': city.isEmpty ? 'Tokyo' : city}),
          ],
        );
      },
    );
    controller = AgentController(
      agent: ToolLoopAgent(
        model: model,
        tools: [_weatherTool()],
        instructions: 'Answer weather questions by calling get_weather.',
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChatPanel(
      controller: controller,
      placeholder: 'Ask about the weather in a city…',
      emptyHint: 'Ask for the weather — the agent will call a typed tool.',
      suggestions: const [
        'Weather in Tokyo',
        'How is it in Buenos Aires?',
        'Lisbon',
      ],
    );
  }
}

const _source = r'''
// Define a tool from a typed input Schema. The raw JSON the model emits is
// decoded into your record BEFORE execute runs — fully statically typed.
final weather = tool<({String city}), Object?>(
  name: 'get_weather',
  description: 'Get the current weather for a city.',
  inputSchema: Schema.object(
    {'city': Schema.string()},
    required: ['city'],
    fromJson: (json) => (city: json['city']! as String),
  ),
  execute: (input, ctx) async => fetchWeather(input.city), // input.city is a String
);

final agent = ToolLoopAgent(model: model, tools: [weather]);

// The loop runs automatically: model -> tool call -> execute -> model -> answer.
controller.send('Weather in Tokyo');
''';
