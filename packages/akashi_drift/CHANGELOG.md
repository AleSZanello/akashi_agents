# Changelog

## 0.3.0

- Initial release: `DriftCheckpointStore`, a durable `CheckpointStore` backed by
  drift + SQLite.
- Persists `AgentCheckpoint`s (via `checkpointToJson`) so a run can resume across
  process restarts and pause indefinitely for durable human-in-the-loop approval
  (`ToolLoopAgent(durableApproval: true)` + `resume(..., decision: ...)`).
- `DriftCheckpointStore.memory()` for tests and `.open(File)` for file-backed
  persistence.
