# Changelog

## 0.3.0

- Initial release of the reactive Flutter integration.
- `AgentController` — a `ChangeNotifier` that drives an `Agent` and folds its
  streamed events into observable `text` / `events` / `isRunning` / `error`
  state. It is also the agent's `ApprovalHandler`, surfacing a `pendingApproval`
  resolved by `approve()` / `reject()`.
- `AgentBuilder` — rebuilds on controller changes.
- `MessageListView` — renders `Message`/`Part` exhaustively (text, reasoning,
  tool-call chips, results, media stubs).
- `offload()` — an Isolate (`compute`) helper for CPU-bound stages, with the
  deps-serializability contract documented.
