import 'package:akashi/akashi.dart';

/// Immutable view-state for a streaming agent chat, independent of any state
/// manager. [startUserTurn] and [foldEvent] are pure reducers over it, so the
/// Riverpod and Bloc recipes share identical, framework-agnostic logic and
/// differ only in how they *store* the result.
class ChatState {
  const ChatState({
    this.messages = const [],
    this.streamingText = '',
    this.isRunning = false,
    this.error,
  });

  /// The committed transcript: user, assistant, and tool messages.
  final List<Message> messages;

  /// The current step's in-flight assistant text, not yet committed to
  /// [messages]. Render it as a live bubble while [isRunning].
  final String streamingText;

  /// Whether a run is currently streaming.
  final bool isRunning;

  /// The last error the run surfaced, if any.
  final Object? error;

  ChatState copyWith({
    List<Message>? messages,
    String? streamingText,
    bool? isRunning,
    Object? error,
  }) => ChatState(
    messages: messages ?? this.messages,
    streamingText: streamingText ?? this.streamingText,
    isRunning: isRunning ?? this.isRunning,
    error: error ?? this.error,
  );
}

/// Appends a user turn and clears the in-flight buffers, ready for a new run.
/// Call this before driving `agent.stream(state.messages)`.
ChatState startUserTurn(ChatState state, String prompt) => ChatState(
  messages: [...state.messages, UserMessage.text(prompt)],
  streamingText: '',
  isRunning: true,
);

/// Folds a single [AgentEvent] into [state]. This mirrors how
/// `AgentController` (akashi_flutter's `ChangeNotifier`) builds its transcript:
/// live [TextDelta] text accumulates into [ChatState.streamingText], and each
/// finished step's messages are committed to [ChatState.messages].
ChatState foldEvent(ChatState state, AgentEvent event) => switch (event) {
  TextDelta(:final text) => state.copyWith(
    streamingText: state.streamingText + text,
  ),
  StepFinish(:final result) => ChatState(
    messages: [...state.messages, ..._stepMessages(result)],
    isRunning: true,
    error: state.error,
  ),
  ErrorEvent(:final error) => ChatState(
    messages: state.messages,
    streamingText: state.streamingText,
    isRunning: true,
    error: error,
  ),
  _ => state,
};

/// The committed messages for a finished step — assistant text plus any tool
/// calls, then any tool results. The same shape `AgentController` builds.
List<Message> _stepMessages(StepResult result) => [
  if (result.text.isNotEmpty || result.toolCalls.isNotEmpty)
    AssistantMessage([
      if (result.text.isNotEmpty) TextPart(result.text),
      ...result.toolCalls,
    ]),
  if (result.toolResults.isNotEmpty) ToolMessage(result.toolResults),
];
