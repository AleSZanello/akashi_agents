import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';

import '../scripted_model.dart';
import '../widgets/chat_panel.dart';
import 'demo.dart';

final streamingChatDemo = Demo(
  id: 'streaming-chat',
  title: 'Streaming chat',
  tagline: 'Token streaming → reactive UI',
  pillar: Pillar.foundations,
  icon: Icons.chat_bubble_outline,
  blurb:
      'A `ToolLoopAgent` streams every token over a `Stream<AgentEvent>`. '
      '`AgentController` folds those deltas into observable state, and '
      '`AgentBuilder` rebuilds the UI — so the reply types out live with no '
      'manual setState plumbing.',
  builder: (_) => const _StreamingChatDemo(),
  source: _source,
);

class _StreamingChatDemo extends StatefulWidget {
  const _StreamingChatDemo();

  @override
  State<_StreamingChatDemo> createState() => _StreamingChatDemoState();
}

class _StreamingChatDemoState extends State<_StreamingChatDemo> {
  late final AgentController controller;

  @override
  void initState() {
    super.initState();
    final model = ScriptedModel(
      respond: (request, _) {
        final q = lastUserText(request);
        return Turn(
          text:
              'You said: “$q”.\n\n'
              'Every token you see is arriving as a TextDelta event over a '
              'Stream<AgentEvent>. AgentController accumulates them and notifies '
              'its listeners, so this bubble repaints as the words land — that '
              'is the whole Flutter-reactive story in one screen.',
        );
      },
    );
    controller = AgentController(
      agent: ToolLoopAgent(
        model: model,
        instructions: 'You are Akashi, a concise, friendly assistant.',
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
      placeholder: 'Ask Akashi anything…',
      emptyHint: 'Type a message or tap a suggestion to watch it stream.',
      suggestions: const [
        'Explain Dart isolates simply',
        'Write a haiku about streams',
        'What can Akashi do?',
      ],
    );
  }
}

const _source = r'''
// AgentController IS the bridge between an agent's event stream and your widgets.
final controller = AgentController(
  agent: ToolLoopAgent(
    model: model, // any LanguageModel — here a client-side ScriptedModel
    instructions: 'You are Akashi, a concise, friendly assistant.',
  ),
);

// Rebuild whenever the controller folds in a new TextDelta:
AgentBuilder(
  controller: controller,
  builder: (context, c) => Text(c.text), // c.text grows token-by-token
);

// Kick off a streamed run; the UI updates itself.
controller.send('Explain Dart isolates simply');
''';
