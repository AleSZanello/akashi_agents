import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';

import '../scripted_model.dart';
import '../widgets/chat_panel.dart';
import 'demo.dart';

final approvalDemo = Demo(
  id: 'human-in-the-loop',
  title: 'Human-in-the-loop',
  tagline: 'Approve or deny risky tool calls',
  pillar: Pillar.foundations,
  icon: Icons.verified_user_outlined,
  blurb: 'A tool can opt into approval via `needsApproval`. `AgentController` '
      'is itself the agent’s `ApprovalHandler`: the loop pauses, the UI surfaces '
      'the pending call, and your Approve/Deny choice resumes it. Denials are '
      'fed back to the model as an error result.',
  builder: (_) => const _ApprovalDemo(),
  source: _source,
);

/// A sensitive tool that pauses for human approval before running.
Tool<Object?> _sendEmailTool() => tool<({String to, String subject}), Object?>(
      name: 'send_email',
      description: 'Send an email on the user’s behalf.',
      inputSchema: Schema.object(
        {'to': Schema.string(), 'subject': Schema.string()},
        required: ['to', 'subject'],
        fromJson: (json) =>
            (to: json['to']! as String, subject: json['subject']! as String),
      ),
      execute: (input, ctx) async => 'sent to ${input.to}',
      needsApproval: (input, ctx) => true,
    );

class _ApprovalDemo extends StatefulWidget {
  const _ApprovalDemo();

  @override
  State<_ApprovalDemo> createState() => _ApprovalDemoState();
}

class _ApprovalDemoState extends State<_ApprovalDemo> {
  late final AgentController controller;

  @override
  void initState() {
    super.initState();
    final model = ScriptedModel(
      respond: (request, _) {
        final result = lastToolResult(request);
        if (result != null) {
          return Turn(
            text: result.isError
                ? 'Understood — I won’t send anything. Want to revise it first?'
                : 'Done! Your email is on its way. ✅',
          );
        }
        return Turn(
          reasoning: 'This will contact someone on the user’s behalf, so I '
              'should request approval before sending.',
          toolCalls: [
            ToolCallSpec('send_email', {
              'to': 'team@akashi.dev',
              'subject': 'Ship the showcase 🚀',
            }),
          ],
        );
      },
    );
    // The controller IS the ApprovalHandler — wire it in, then attach the agent.
    controller = AgentController();
    controller.agent = ToolLoopAgent(
      model: model,
      tools: [_sendEmailTool()],
      approvalHandler: controller,
      instructions: 'Help the user with email. Sending requires approval.',
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
      placeholder: 'e.g. “email the team about the launch”',
      emptyHint: 'Ask the agent to send an email — it will pause for approval.',
      suggestions: const [
        'Email the team about the launch',
        'Send a thank-you note',
      ],
    );
  }
}

const _source = r'''
// 1. A tool opts into human approval.
final sendEmail = tool<({String to, String subject}), Object?>(
  name: 'send_email',
  /* ...inputSchema... */
  execute: (input, ctx) => mailer.send(input.to, input.subject),
  needsApproval: (input, ctx) => true, // pause before running
);

// 2. The controller is also the ApprovalHandler.
final controller = AgentController();
controller.agent = ToolLoopAgent(
  model: model,
  tools: [sendEmail],
  approvalHandler: controller, // <- the loop asks the controller
);

// 3. The UI surfaces controller.pendingApproval and resolves it:
FilledButton(onPressed: controller.approve, child: const Text('Approve'));
OutlinedButton(onPressed: () => controller.reject('Denied'), child: const Text('Deny'));
''';
