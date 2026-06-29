# akashi_workflow

**Deterministic, code-driven multi-agent orchestration for [Akashi](https://github.com/AleSZanello/akashi_agents).**

Akashi's built-in multi-agent primitives (`Agent.asTool`, handoffs, escalation)
are **model-driven** — the *model* decides at runtime whether to delegate or hand
off. `akashi_workflow` is the complement: **code-driven** orchestration where
*you* fix the topology (fan-out, pipelines, loops) and the engine supplies the
production concerns.

> 🔬 Live demo: the **Workflow pipeline** demo at
> [akashi-agents.web.app](https://akashi-agents.web.app/demos/workflow-pipeline).

## What it gives you

- **Bounded concurrency** — a fan-out of hundreds of tasks runs at most
  `maxConcurrency` at a time (a FIFO `Semaphore`).
- **Retries** — geometric backoff + jitter, per-task or workflow-default, with a
  `retryIf` predicate.
- **Timeouts** — per task and a global `deadline`; a timeout cooperatively
  cancels the task.
- **Cancellation** — one `CancellationToken` for the whole run, linkable to an
  external token, threaded into every task (and into agent runs via `agentTask`).
- **Fail-fast or settled** — `parallel` rethrows the first failure and cancels
  siblings; `parallelSettled` returns every `TaskResult`.
- **Typed pipelines** — chain stages with no barrier between them (item A can be
  in stage 3 while item B is in stage 1).
- **Observability** — a broadcast `events` stream (`TaskStarted` / `TaskSucceeded`
  / `TaskFailed` / `TaskRetrying`) plus `Tracer` spans.
- **A budget guard** — `maxTasks` caps total executions (a runaway-loop backstop).

## Quick start

```dart
import 'package:akashi_workflow/akashi_workflow.dart';

final wf = Workflow(
  maxConcurrency: 4,
  defaultRetry: RetryPolicy.standard,        // 3 attempts, backoff+jitter
  defaultTimeout: const Duration(seconds: 30),
);

// Fan out research across questions — bounded to 4 at a time, each retried.
final findings = await wf.parallel([
  for (final q in questions) agentTask(researcher, q.prompt, label: q.id),
]);

// Synthesize the results with another agent.
final report = await wf.run(agentTask(writer, synthesisPrompt(findings)));

wf.dispose();
```

### Settled fan-out (partial results)

```dart
final results = await wf.parallelSettled([
  for (final url in urls) Task((ctx) => scrape(url, ctx.cancel), label: url),
]);
final ok = results.where((r) => r.ok).map((r) => r.value);
final failed = results.where((r) => !r.ok);
```

### Typed pipeline (plan → research → verify)

```dart
final pipeline = Pipeline.input<Topic>()
    .stage('research', (topic, ctx) => researcher.run(topic.q,
        options: RunOptions(cancel: ctx.cancel)))            // Topic -> RunResult
    .stage('verify', (res, ctx) => verifier.run(res.text,
        options: RunOptions(cancel: ctx.cancel)));           // RunResult -> Verdict

final verdicts = await wf.pipeline(topics, pipeline); // List<TaskResult<Verdict>>
```

### Structured output between stages

```dart
final plan = await wf.run(objectTask(planner, goal, schema: planSchema));
```

### Live progress

```dart
wf.events.listen((e) {
  switch (e) {
    case TaskStarted(): print('▶ ${e.label} #${e.attempt}');
    case TaskSucceeded(): print('✓ ${e.label}');
    case TaskFailed(): print('✗ ${e.label} (retry: ${e.willRetry})');
    case TaskRetrying(): print('↻ ${e.label} in ${e.delay.inMilliseconds}ms');
  }
});
```

## When to use which

| | Model-driven (`akashi`) | Code-driven (`akashi_workflow`) |
|---|---|---|
| Who decides the shape | the LLM, at runtime | you, in Dart |
| Primitives | `Agent.asTool`, handoffs | `parallel`, `pipeline`, `run` |
| Best for | open-ended delegation | known fan-out, batch jobs, ETL-style pipelines, audits |

They compose: a workflow stage can itself run a multi-agent (subagent/handoff)
`Agent`.

See [`example/akashi_workflow_example.dart`](example/akashi_workflow_example.dart)
for a runnable plan → fan-out → synthesize pipeline on fake models.
