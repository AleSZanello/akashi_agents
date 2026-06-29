import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';

import 'chat_state.dart';

/// Renders a [ChatState] with akashi_flutter's [MessageListView] plus a live
/// bubble for the in-flight streaming text. Reused by both recipes: state lives
/// in your state manager, rendering is reused from the framework.
class Transcript extends StatelessWidget {
  const Transcript({required this.state, super.key});

  final ChatState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: MessageListView(
            messages: state.messages,
            padding: const EdgeInsets.all(16),
          ),
        ),
        if (state.isRunning && state.streamingText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(state.streamingText),
            ),
          ),
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '${state.error}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

/// A text input plus a send button.
class Composer extends StatelessWidget {
  const Composer({required this.controller, required this.onSend, super.key});

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: (_) => onSend(),
              decoration: const InputDecoration(hintText: 'Message'),
            ),
          ),
          IconButton(icon: const Icon(Icons.send), onPressed: onSend),
        ],
      ),
    );
  }
}
