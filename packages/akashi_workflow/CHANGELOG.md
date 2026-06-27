# Changelog

## 0.3.0

- Initial release of deterministic, code-driven multi-agent orchestration.
- `Workflow` — an orchestrator with bounded concurrency (`maxConcurrency`),
  default + per-task `RetryPolicy` (geometric backoff + jitter), per-task and
  global (`deadline`) timeouts, cooperative cancellation (linkable to an external
  `CancellationToken`), a `maxTasks` runaway-budget guard, and a broadcast
  `events` stream of `WorkflowEvent`s.
  - `run` / `runCatching` — single task (throwing vs. settled).
  - `parallel` — fan-out, fail-fast with sibling cancellation.
  - `parallelSettled` — fan-out returning every `TaskResult` (successes +
    failures).
  - `pipeline` — stream items through a typed `Pipeline` with **no barrier**
    between stages.
- `Task` / `TaskResult` / `TaskContext`, `RetryPolicy`, `Semaphore`, sealed
  `WorkflowEvent`s, and typed `Pipeline` builder.
- `agentTask` / `objectTask` — wrap an Akashi `Agent` (`run` / `generateObject`)
  as a workflow task, with cancellation wired through to the agent loop.
