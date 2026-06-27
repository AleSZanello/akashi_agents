import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';

import '../scripted_model.dart';
import '../widgets/chat_panel.dart';
import 'demo.dart';

final handoffDemo = Demo(
  id: 'handoffs',
  title: 'Handoffs',
  tagline: 'Transfer control between agents',
  pillar: Pillar.multiAgent,
  icon: Icons.swap_horiz,
  blurb: 'A handoff is a control *transfer*, not a subroutine. A triage agent '
      'exposes `transfer_to_<name>` tools; when it calls one, the loop swaps the '
      'active agent (model + instructions + tools) for the rest of the '
      'conversation while the message history carries across.',
  builder: (_) => const _HandoffDemo(),
  source: _source,
);

class _HandoffDemo extends StatefulWidget {
  const _HandoffDemo();

  @override
  State<_HandoffDemo> createState() => _HandoffDemoState();
}

class _HandoffDemoState extends State<_HandoffDemo> {
  late final AgentController controller;

  @override
  void initState() {
    super.initState();

    final refund = tool<({String orderId}), Object?>(
      name: 'issue_refund',
      description: 'Issue a refund for an order.',
      inputSchema: Schema.object(
        {'orderId': Schema.string()},
        required: ['orderId'],
        fromJson: (json) => (orderId: json['orderId']! as String),
      ),
      execute: (input, ctx) async => 'refunded order ${input.orderId}',
    );

    final billing = ToolLoopAgent<Object?>(
      model: ScriptedModel(
        respond: (request, _) => const Turn(
          text: 'Billing here 💳 — I can see your account. I’ve queued the '
              'refund and you’ll see it in 3–5 business days. Anything else?',
        ),
      ),
      tools: [refund],
      instructions: 'You are the billing specialist.',
    );

    final tech = ToolLoopAgent<Object?>(
      model: ScriptedModel(
        respond: (request, _) => const Turn(
          text: 'Tech support here 🛠 — let’s fix that. Try signing out and '
              'back in; if the error persists, clear the app cache and retry.',
        ),
      ),
      instructions: 'You are the technical support specialist.',
    );

    final triage = ToolLoopAgent<Object?>(
      model: ScriptedModel(
        respond: (request, _) {
          final q = lastUserText(request).toLowerCase();
          final billingIntent = q.contains('refund') ||
              q.contains('charge') ||
              q.contains('bill') ||
              q.contains('pay');
          return Turn(
            reasoning: 'Routing this to the right specialist…',
            toolCalls: [
              ToolCallSpec(
                billingIntent ? 'transfer_to_billing' : 'transfer_to_tech',
                const {},
              ),
            ],
          );
        },
      ),
      instructions: 'Route the user to the correct specialist.',
      handoffs: [
        handoff(billing, name: 'billing'),
        handoff(tech, name: 'tech'),
      ],
    );

    controller = AgentController(agent: triage);
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
      placeholder: 'Describe your issue…',
      emptyHint: 'Ask about a refund or a bug — triage routes you to a specialist.',
      suggestions: const [
        'I want a refund for order 4242',
        'The app keeps crashing on launch',
      ],
    );
  }
}

const _source = r'''
final billing = ToolLoopAgent<Object?>(
  model: model, tools: [refund], instructions: 'You are the billing specialist.');
final tech = ToolLoopAgent<Object?>(
  model: model, instructions: 'You are technical support.');

// The triage agent advertises transfer_to_billing / transfer_to_tech tools.
final triage = ToolLoopAgent<Object?>(
  model: model,
  instructions: 'Route the user to the correct specialist.',
  handoffs: [
    handoff(billing, name: 'billing'),
    handoff(tech, name: 'tech'),
  ],
);

// When the model calls transfer_to_billing, the loop emits a HandoffEvent and
// swaps the active agent — billing answers next, with the history intact.
controller.send('I want a refund for order 4242');
''';
