# Changelog

## 0.3.0

- Initial release of the reactive Flutter integration.
- `AgentController` — a `ChangeNotifier` that drives an `Agent` and folds its
  streamed events into observable `text` / `events` / `messages` / `isRunning` /
  `error` state. It is also the agent's `ApprovalHandler`, surfacing a
  `pendingApproval` resolved by `approve()` / `reject()`.
  - `messages` accumulates a `Message` transcript across turns; `send` drives the
    agent over the full history, so successive sends form a multi-turn
    conversation that drops straight into `MessageListView`.
  - Durable human-in-the-loop: a `durableApproval` run surfaces as `suspended`
    (instead of a live `pendingApproval`). `approve()` / `reject()` resume it
    from the checkpoint store, and `resume(checkpointId, decision: …)` resumes a
    suspension out of band (e.g. after a process restart).
  - Lifecycle: `dispose()` cancels the in-flight run, rejects a pending
    in-process approval so the agent loop completes instead of hanging, and
    silences post-dispose notifications; `stop()` cancels a run without
    disposing.
- `AgentBuilder` — rebuilds on controller changes.
- `MessageListView` — renders `Message`/`Part` exhaustively (text, reasoning,
  tool-call chips, results, media stubs).
- `offload()` — an Isolate (`compute`) helper for CPU-bound stages, with the
  deps-serializability contract documented.
