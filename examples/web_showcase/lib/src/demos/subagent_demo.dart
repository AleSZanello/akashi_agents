import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';

import '../scripted_model.dart';
import '../widgets/chat_panel.dart';
import 'demo.dart';

final subagentDemo = Demo(
  id: 'subagent-as-tool',
  title: 'Subagent as a tool',
  tagline: 'Delegate to an isolated child agent',
  pillar: Pillar.multiAgent,
  icon: Icons.account_tree_outlined,
  blurb:
      'The core multi-agent primitive. `Agent.asTool` turns a whole agent '
      'into a tool. The child runs with its OWN fresh context and its own tools '
      '(none of which leak to the parent) and returns just its final text. Here '
      'an orchestrator delegates to a research subagent that runs its own search.',
  builder: (_) => const _SubagentDemo(),
  source: _source,
);

class _SubagentDemo extends StatefulWidget {
  const _SubagentDemo();

  @override
  State<_SubagentDemo> createState() => _SubagentDemoState();
}

class _SubagentDemoState extends State<_SubagentDemo> {
  late final AgentController controller;

  @override
  void initState() {
    super.initState();

    // The CHILD: a researcher with its own model and its own web_search tool.
    final search = tool<({String query}), Object?>(
      name: 'web_search',
      description: 'Search the web.',
      inputSchema: Schema.object(
        {'query': Schema.string()},
        required: ['query'],
        fromJson: (json) => (query: json['query']! as String),
      ),
      execute: (input, ctx) async =>
          '3 sources agree: Dart isolates have no shared memory; '
          'they communicate via message passing over ports.',
    );
    final researcher = ToolLoopAgent<Object?>(
      model: ScriptedModel(
        respond: (request, _) {
          final result = lastToolResult(request);
          if (result != null) {
            return Turn(
              text:
                  'Findings: ${result.output} '
                  'This makes them safe for true parallelism.',
            );
          }
          return Turn(
            toolCalls: [
              ToolCallSpec('web_search', {'query': lastUserText(request)}),
            ],
          );
        },
      ),
      tools: [search],
      instructions: 'Investigate the question concisely and report findings.',
    );

    // Expose the researcher to the parent as a single `research` tool.
    final researchTool = researcher.asTool<({String question}), Object?>(
      name: 'research',
      description: 'Investigate a question and report findings.',
      inputSchema: Schema.object(
        {'question': Schema.string()},
        required: ['question'],
        fromJson: (json) => (question: json['question']! as String),
      ),
      deps: (input, ctx) => null,
      promptBuilder: (input) => input.question,
    );

    // The PARENT orchestrator only sees the `research` tool, not web_search.
    final orchestrator = ToolLoopAgent<Object?>(
      model: ScriptedModel(
        respond: (request, _) {
          final result = lastToolResult(request);
          if (result != null) {
            return Turn(text: 'My researcher looked into it. ${result.output}');
          }
          return Turn(
            reasoning:
                'I’ll delegate the investigation to my research subagent '
                'so it works in its own isolated context.',
            toolCalls: [
              ToolCallSpec('research', {'question': lastUserText(request)}),
            ],
          );
        },
      ),
      tools: [researchTool],
      instructions: 'Delegate research, then summarize for the user.',
    );

    controller = AgentController(agent: orchestrator);
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
      placeholder: 'Ask a question to research…',
      emptyHint: 'Ask something — the orchestrator delegates to a subagent.',
      suggestions: const [
        'How do Dart isolates work?',
        'Research async vs isolates',
      ],
    );
  }
}

const _source = r'''
// CHILD: a researcher agent with its own model + its own tools.
final researcher = ToolLoopAgent<Object?>(
  model: smallModel,
  tools: [webSearch],
  instructions: 'Investigate concisely and report findings.',
);

// Turn the whole agent into a single tool the parent can call.
final researchTool = researcher.asTool<({String question}), Object?>(
  name: 'research',
  description: 'Investigate a question and report findings.',
  inputSchema: Schema.object(
    {'question': Schema.string()},
    required: ['question'],
    fromJson: (j) => (question: j['question']! as String),
  ),
  deps: (input, ctx) => null,          // map parent deps -> child deps
  promptBuilder: (input) => input.question,
);

// PARENT: sees only `research`. The child's web_search tool stays hidden,
// and the child runs with a FRESH, isolated message history.
final orchestrator = ToolLoopAgent<Object?>(model: bigModel, tools: [researchTool]);
''';
