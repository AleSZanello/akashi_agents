/// Deterministic, code-driven multi-agent orchestration for Akashi.
///
/// Where Akashi's [Agent] primitives are *model-driven* (the model decides when
/// to call a subagent or hand off), [Workflow] is *code-driven*: you write the
/// control flow (fan-out, pipelines, loops) and it supplies bounded concurrency,
/// retries with backoff, timeouts, cooperative cancellation, a budget guard, and
/// an observable [WorkflowEvent] stream.
///
/// Wrap agents as work with [agentTask] / [objectTask], fan out with
/// [Workflow.parallel] / [Workflow.parallelSettled], and chain stages with a
/// typed [Pipeline] via [Workflow.pipeline].
library;

export 'src/agent_tasks.dart';
export 'src/concurrency.dart';
export 'src/errors.dart';
export 'src/events.dart';
export 'src/pipeline.dart';
export 'src/retry.dart';
export 'src/task.dart';
export 'src/workflow.dart';
