import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';

import '../scripted_model.dart';
import '../theme.dart';
import '../widgets/chat_panel.dart';
import 'demo.dart';

final escalationDemo = Demo(
  id: 'model-escalation',
  title: 'Model escalation',
  tagline: 'Start cheap, escalate when it’s hard',
  pillar: Pillar.multiAgent,
  icon: Icons.trending_up,
  blurb: 'The cost/quality lever. Run on a cheap model and let an '
      '`EscalationPolicy` swap in a stronger one when the task proves hard. Here '
      '`escalateOnToolErrors(afterErrors: 1)` upgrades the model the moment a '
      'tool call fails — the next step runs on the stronger model.',
  builder: (_) => const _EscalationDemo(),
  source: _source,
);

class _EscalationDemo extends StatefulWidget {
  const _EscalationDemo();

  @override
  State<_EscalationDemo> createState() => _EscalationDemoState();
}

class _EscalationDemoState extends State<_EscalationDemo> {
  late final AgentController controller;

  @override
  void initState() {
    super.initState();

    // A flaky tool that fails — this is what trips the escalation policy.
    final flaky = tool<({String topic}), Object?>(
      name: 'knowledge_base',
      description: 'Look up an answer in the knowledge base.',
      inputSchema: Schema.object(
        {'topic': Schema.string()},
        required: ['topic'],
        fromJson: (json) => (topic: json['topic']! as String),
      ),
      execute: (input, ctx) async => throw StateError('knowledge base timeout'),
    );

    final cheap = ScriptedModel(
      modelId: 'flash-cheap',
      respond: (request, _) => Turn(
        toolCalls: [
          ToolCallSpec('knowledge_base', {'topic': lastUserText(request)}),
        ],
      ),
    );
    final strong = ScriptedModel(
      modelId: 'pro-strong',
      respond: (request, _) => const Turn(
        text: 'Now on the stronger model — I’ll answer directly without the '
            'knowledge base: isolates give you parallelism without shared '
            'mutable state, communicating only via messages.',
      ),
    );

    controller = AgentController(
      agent: ToolLoopAgent(
        model: cheap,
        tools: [flaky],
        prepareStep: escalate([
          escalateOnToolErrors(to: strong, afterErrors: 1),
        ]),
        instructions: 'Answer using the knowledge base when possible.',
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
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AkashiColors.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AkashiColors.border),
          ),
          child: const Row(
            children: [
              Icon(Icons.bolt, size: 18, color: AkashiColors.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Starts on flash-cheap. The knowledge_base tool fails once → '
                  'the policy escalates → the next step runs on pro-strong.',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: AkashiColors.textSecondary,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ChatPanel(
            controller: controller,
            placeholder: 'Ask a question…',
            emptyHint: 'Ask something — watch the tool fail, then the upgrade.',
            suggestions: const [
              'Explain isolates',
              'What is structured concurrency?',
            ],
          ),
        ),
      ],
    );
  }
}

const _source = r'''
final cheap = model('flash');  // start here
final strong = model('pro');   // escalate to this

final agent = ToolLoopAgent(
  model: cheap,
  tools: [knowledgeBase],
  // Compose escalation policies into a prepareStep hook.
  prepareStep: escalate([
    escalateOnToolErrors(to: strong, afterErrors: 1),
    // also available: escalateAfterSteps(...), escalateOnLowConfidence(...)
  ]),
);

// Step 0 runs on `cheap` and the tool fails. Before step 1, the policy fires
// and swaps the model to `strong`, which answers directly.
''';
