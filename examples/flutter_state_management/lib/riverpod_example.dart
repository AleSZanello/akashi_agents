// Riverpod and akashi both export a `Provider`; here we want Riverpod's, so we
// hide akashi's (its LLM-provider interface, unused in this recipe).
import 'package:akashi/akashi.dart' hide Provider;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_state.dart';
import 'chat_ui.dart';
import 'scripted_model.dart';

// ── State manager glue ──────────────────────────────────────────────────────
//
// The agent is plain `package:akashi` — no Flutter, no AgentController. The
// Notifier consumes `agent.stream(...)` directly and folds events with the
// framework-agnostic `foldEvent` reducer.

/// Exposes the agent to the rest of the app. Swap [ScriptedModel] for a real
/// provider model (e.g. `akashi_google`'s `GeminiModel`).
final agentProvider = Provider<Agent<void>>((ref) {
  return ToolLoopAgent<void>(
    model: ScriptedModel(),
    instructions: 'You are a helpful assistant.',
  );
});

/// Drives the agent and reduces its event stream into [ChatState].
final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  Future<void> send(String prompt) async {
    if (state.isRunning || prompt.isEmpty) return;
    final agent = ref.read(agentProvider);
    state = startUserTurn(state, prompt);
    try {
      // Pass the full transcript so each turn carries the prior context.
      await for (final event in agent.stream(state.messages)) {
        state = foldEvent(state, event);
      }
    } finally {
      state = state.copyWith(isRunning: false);
    }
  }
}

// ── UI ──────────────────────────────────────────────────────────────────────

/// Run this recipe on its own with `flutter run -t lib/riverpod_example.dart`.
void main() =>
    runApp(const ProviderScope(child: MaterialApp(home: RiverpodChatScreen())));

class RiverpodChatScreen extends ConsumerStatefulWidget {
  const RiverpodChatScreen({super.key});

  @override
  ConsumerState<RiverpodChatScreen> createState() => _RiverpodChatScreenState();
}

class _RiverpodChatScreenState extends ConsumerState<RiverpodChatScreen> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    ref.read(chatProvider.notifier).send(_input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Akashi × Riverpod')),
      body: Column(
        children: [
          Expanded(child: Transcript(state: state)),
          Composer(controller: _input, onSend: _send),
        ],
      ),
    );
  }
}
