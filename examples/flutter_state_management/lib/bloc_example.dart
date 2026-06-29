import 'package:akashi/akashi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'chat_state.dart';
import 'chat_ui.dart';
import 'scripted_model.dart';

// ── State manager glue ──────────────────────────────────────────────────────
//
// The agent is plain `package:akashi` — no Flutter, no AgentController. The
// Cubit consumes `agent.stream(...)` directly and folds events with the
// framework-agnostic `foldEvent` reducer.

class ChatCubit extends Cubit<ChatState> {
  ChatCubit(this._agent) : super(const ChatState());

  final Agent<void> _agent;

  Future<void> send(String prompt) async {
    if (state.isRunning || prompt.isEmpty) return;
    emit(startUserTurn(state, prompt));
    try {
      // Pass the full transcript so each turn carries the prior context.
      await for (final event in _agent.stream(state.messages)) {
        if (isClosed) return; // The screen was disposed mid-stream.
        emit(foldEvent(state, event));
      }
    } finally {
      if (!isClosed) emit(state.copyWith(isRunning: false));
    }
  }
}

// ── UI ──────────────────────────────────────────────────────────────────────

/// Run this recipe on its own with `flutter run -t lib/bloc_example.dart`.
void main() => runApp(const MaterialApp(home: BlocChatScreen()));

class BlocChatScreen extends StatelessWidget {
  const BlocChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ChatCubit>(
      create: (_) => ChatCubit(
        ToolLoopAgent<void>(
          model: ScriptedModel(),
          instructions: 'You are a helpful assistant.',
        ),
      ),
      child: const _BlocChatView(),
    );
  }
}

class _BlocChatView extends StatefulWidget {
  const _BlocChatView();

  @override
  State<_BlocChatView> createState() => _BlocChatViewState();
}

class _BlocChatViewState extends State<_BlocChatView> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    context.read<ChatCubit>().send(_input.text);
    _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Akashi × Bloc')),
      body: Column(
        children: [
          Expanded(
            child: BlocBuilder<ChatCubit, ChatState>(
              builder: (context, state) => Transcript(state: state),
            ),
          ),
          Composer(controller: _input, onSend: _send),
        ],
      ),
    );
  }
}
