# akashi_flutter

Reactive Flutter integration for the [Akashi](https://github.com/AleSZanello/akashi_agents)
agent framework. Drive an agent from your widgets, render its transcript, and
keep heavy work off the UI thread.

## What's in the box

- **`AgentController`** — a `ChangeNotifier` that drives an `Agent` and folds its
  streamed events into observable state: `text`, `events`, `messages`,
  `isRunning`, `error`, `pendingApproval`, `suspended`. It is *also* the agent's
  `ApprovalHandler`.
- **`AgentBuilder`** — rebuilds a subtree whenever the controller notifies.
- **`MessageListView`** — renders a `List<Message>` exhaustively (text,
  reasoning disclosures, tool-call chips, results, media stubs); fully
  overridable per part via `partBuilder`.
- **`offload`** — a `compute()` helper for CPU-bound stages, with the
  isolate deps-serializability contract documented.

## Quick start

```dart
final controller = AgentController<void>();
final agent = ToolLoopAgent<void>(
  model: model,            // e.g. akashi_google's GeminiModel
  tools: tools,
  approvalHandler: controller, // controller IS the ApprovalHandler
);
controller.agent = agent;  // resolve the construction-time cycle

// In your widget tree:
AgentBuilder<void>(
  controller: controller,
  builder: (context, c) => Column(children: [
    Expanded(child: MessageListView(messages: c.messages)),
    if (c.text.isNotEmpty) Text(c.text),       // live, in-flight bubble
  ]),
);

controller.send('Summarize my unread mail.');
```

`send` appends each prompt to `messages` and drives the agent over the full
history, so successive calls form a multi-turn conversation.

## Bring your own state manager (Riverpod, Bloc, …)

`AgentController` is the batteries-included path for `ChangeNotifier` /
`provider`. You don't need it for Riverpod or Bloc — the agent is plain
`package:akashi` and exposes a universal interface: `agent.stream(prompt)` (a
`Stream<AgentEvent>`) and `agent.run(prompt)` (a `Future<RunResult>`), which
every state manager already knows how to consume. Hold the agent's state in
*your* container and reuse `MessageListView` to render the transcript.

The fold is the same regardless of manager: accumulate `TextDelta` text for a
live bubble, and commit each `StepFinish` step's messages to the transcript —
exactly what `AgentController` does internally. The example below factors that
into one framework-agnostic reducer (`startUserTurn` + `foldEvent`) that both
recipes call.

**Riverpod** — a `Notifier` drives the stream:

```dart
class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() => const ChatState();

  Future<void> send(String prompt) async {
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
```

**Bloc** — a `Cubit` emits the same reduced state:

```dart
class ChatCubit extends Cubit<ChatState> {
  ChatCubit(this._agent) : super(const ChatState());
  final Agent<void> _agent;

  Future<void> send(String prompt) async {
    emit(startUserTurn(state, prompt));
    try {
      await for (final event in _agent.stream(state.messages)) {
        if (isClosed) return; // The screen was disposed mid-stream.
        emit(foldEvent(state, event));
      }
    } finally {
      if (!isClosed) emit(state.copyWith(isRunning: false));
    }
  }
}
```

> One collision to know: Riverpod and akashi both export a `Provider`. In a file
> that uses Riverpod's, import akashi with `hide Provider`.

A runnable, analyzer-clean app with both recipes (plus behavioral tests) lives in
[`examples/flutter_state_management`](../../examples/flutter_state_management).

## Approval: in-process vs. durable

Both styles resolve from the same `approve()` / `reject()` call.

- **In-process** (default): a pending tool call blocks the loop in memory and
  surfaces as `controller.pendingApproval`. Bind it to a dialog; `approve()` /
  `reject(reason)` complete it.
- **Durable** (`ToolLoopAgent(durableApproval: true)` + a `CheckpointStore`,
  e.g. `akashi_drift`): the run persists a checkpoint and *suspends* — the
  stream ends with `controller.suspended` set. `approve()` / `reject()` then
  `resume` it from the store, which survives a process restart. After a restart,
  attach the same agent and call `controller.resume(checkpointId, decision: …)`.

```dart
AgentBuilder<void>(
  controller: controller,
  builder: (context, c) {
    final call = c.pendingApproval?.call ?? c.suspended?.pendingCall;
    if (call == null) return const SizedBox.shrink();
    return Row(children: [
      Text('Allow ${call.toolName}?'),
      TextButton(onPressed: c.approve, child: const Text('Allow')),
      TextButton(onPressed: () => c.reject('denied'), child: const Text('Deny')),
    ]);
  },
);
```

## Offloading CPU-bound work

```dart
final parsed = await offload(parseBigPayload, rawJson);
```

Closures and live handles (sockets, DB connections, plugin channels) **cannot**
cross a `SendPort`. Construct such dependencies *inside* the callback from a
serializable config, or offload only pure, CPU-bound stages while the agent
stays on the main isolate.

## Example

A runnable reactive chat screen lives in
[`example/akashi_flutter_example.dart`](example/akashi_flutter_example.dart) —
swap the scripted model for any provider model and the rest is unchanged.

## Status

v0.3.

## License

MIT.
