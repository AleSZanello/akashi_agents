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
