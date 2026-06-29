import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';

import '../scripted_model.dart';
import '../theme.dart';
import '../widgets/chat_panel.dart';
import 'demo.dart';

final stateManagementDemo = Demo(
  id: 'state-management',
  title: 'Bring your own state manager',
  tagline: 'Riverpod · Bloc · AgentController',
  pillar: Pillar.durableFlutter,
  icon: Icons.alt_route,
  blurb:
      'The agent is plain `package:akashi` — it exposes a `Stream<AgentEvent>` '
      '(`agent.stream`) and a `Future<RunResult>` (`agent.run`), the universal '
      'interface every state manager already consumes. `akashi_flutter`’s '
      '`AgentController` is the batteries-included path, but nothing forces it: '
      'this panel runs on `AgentController`, while the Code tab folds the '
      'identical run into Riverpod and Bloc. Same agent — pick your stack.',
  builder: (_) => const _StateManagementDemo(),
  source: _source,
);

class _StateManagementDemo extends StatefulWidget {
  const _StateManagementDemo();

  @override
  State<_StateManagementDemo> createState() => _StateManagementDemoState();
}

class _StateManagementDemoState extends State<_StateManagementDemo> {
  late final AgentController controller;

  @override
  void initState() {
    super.initState();
    final model = ScriptedModel(
      respond: (request, _) {
        final q = lastUserText(request);
        return Turn(
          text:
              'You asked: “$q”.\n\n'
              'This bubble is driven by AgentController, but the agent itself is '
              'Flutter-agnostic — it only emits a Stream<AgentEvent>. The Code '
              'tab shows this exact run folded into a Riverpod Notifier and a '
              'Bloc Cubit instead. The state manager is your choice; the agent '
              'never changes.',
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
    return Column(
      children: [
        const _StackBadges(),
        const SizedBox(height: 12),
        Expanded(
          child: ChatPanel(
            controller: controller,
            placeholder: 'Ask how Akashi fits your stack…',
            emptyHint:
                'This panel runs on AgentController — the Code tab wires the '
                'same agent through Riverpod and Bloc.',
            suggestions: const [
              'Does Akashi work with Riverpod?',
              'How do I use this with Bloc?',
              'What does the agent actually expose?',
            ],
          ),
        ),
      ],
    );
  }
}

/// A static "works with" header: AgentController drives this live panel; the
/// Code tab shows Riverpod and Bloc consuming the same `Stream<AgentEvent>`.
class _StackBadges extends StatelessWidget {
  const _StackBadges();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AkashiColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AkashiColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: const [
              Text(
                'Same agent, your state manager:',
                style: TextStyle(
                  color: AkashiColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              _Badge(label: 'AgentController', live: true),
              _Badge(label: 'Riverpod'),
              _Badge(label: 'Bloc'),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Riverpod and Bloc drive the identical run — see the Code tab.',
            style: TextStyle(color: AkashiColors.textFaint, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.live = false});

  final String label;

  /// Whether this manager is the one driving the live panel.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final color = live ? AkashiColors.accent : AkashiColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: live
            ? AkashiColors.accent.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: live
              ? AkashiColors.accent.withValues(alpha: 0.6)
              : AkashiColors.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AkashiColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontFamilyFallback: kMonoFontFamilyFallback,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

const _source = r'''
// The agent is plain `package:akashi`. It exposes a universal interface —
//   agent.stream(prompt) -> Stream<AgentEvent>
//   agent.run(prompt)    -> Future<RunResult>
// — that any state manager can consume. akashi_flutter is optional.

// ── akashi_flutter (batteries included): AgentController is a ChangeNotifier ──
final controller = AgentController(agent: agent);
AgentBuilder(
  controller: controller,
  builder: (context, c) => MessageListView(messages: c.messages),
);
controller.send('Hello');

// ── Riverpod: a Notifier folds the same event stream ──
class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  Future<void> send(String prompt) async {
    final agent = ref.read(agentProvider);
    state = startUserTurn(state, prompt);
    try {
      await for (final event in agent.stream(state.messages)) {
        state = foldEvent(state, event);          // shared reducer
      }
    } finally {
      state = state.copyWith(isRunning: false);
    }
  }
}

// ── Bloc: a Cubit emits the same reduced state ──
class ChatCubit extends Cubit<ChatState> {
  ChatCubit(this._agent) : super(const ChatState());
  final Agent<void> _agent;

  Future<void> send(String prompt) async {
    emit(startUserTurn(state, prompt));
    try {
      await for (final event in _agent.stream(state.messages)) {
        if (isClosed) return;
        emit(foldEvent(state, event));            // the same shared reducer
      }
    } finally {
      if (!isClosed) emit(state.copyWith(isRunning: false));
    }
  }
}

// startUserTurn + foldEvent are framework-agnostic reducers shared by both.
// Full runnable example (analyzer-clean, with tests):
//   examples/flutter_state_management
''';
