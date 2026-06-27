import 'package:akashi/akashi.dart';

import 'retry.dart';

/// The context handed to a [Task]'s body each attempt.
class TaskContext {
  /// Creates a task context.
  const TaskContext({
    required this.cancel,
    required this.attempt,
    required this.tracer,
    required this.label,
  });

  /// Cooperative cancellation for this attempt — cancelled if the workflow is
  /// cancelled, a deadline passes, a fail-fast sibling failed, or this attempt
  /// times out. Pass it to `agent.run(options: RunOptions(cancel: ctx.cancel))`.
  final CancellationToken cancel;

  /// The 1-based attempt number (increments on retry).
  final int attempt;

  /// Tracer for emitting task-scoped spans.
  final Tracer tracer;

  /// The task's label.
  final String label;
}

/// A unit of work in a [Workflow]: an async [body] plus per-task [retry] and
/// [timeout] overrides. A task is just data — running it (with concurrency,
/// retries, timeouts, events) is the workflow's job.
class Task<R> {
  /// Creates a task wrapping [body].
  const Task(
    this.body, {
    this.label = 'task',
    this.retry,
    this.timeout,
  });

  /// The work to perform; receives a fresh [TaskContext] each attempt.
  final Future<R> Function(TaskContext ctx) body;

  /// A human-readable label, surfaced in events and traces.
  final String label;

  /// Overrides the workflow's default retry policy for this task.
  final RetryPolicy? retry;

  /// Overrides the workflow's default per-task timeout.
  final Duration? timeout;
}

/// The settled outcome of running a [Task] — success xor failure, plus how many
/// attempts it took and how long it ran.
class TaskResult<R> {
  const TaskResult._({
    required this.label,
    required this.ok,
    required this.attempts,
    required this.duration,
    this.value,
    this.error,
    this.stackTrace,
  });

  /// A successful result carrying [value].
  factory TaskResult.success({
    required String label,
    required R value,
    required int attempts,
    required Duration duration,
  }) =>
      TaskResult._(
        label: label,
        ok: true,
        value: value,
        attempts: attempts,
        duration: duration,
      );

  /// A failed result carrying [error].
  factory TaskResult.failure({
    required String label,
    required Object error,
    required int attempts,
    required Duration duration,
    StackTrace? stackTrace,
  }) =>
      TaskResult._(
        label: label,
        ok: false,
        error: error,
        stackTrace: stackTrace,
        attempts: attempts,
        duration: duration,
      );

  /// The task's label.
  final String label;

  /// Whether the task succeeded.
  final bool ok;

  /// The produced value when [ok]; null otherwise.
  final R? value;

  /// The error when not [ok]; null otherwise.
  final Object? error;

  /// The captured stack trace for [error], if any.
  final StackTrace? stackTrace;

  /// Total attempts made (≥ 1).
  final int attempts;

  /// Wall-clock duration across all attempts.
  final Duration duration;

  /// The value if [ok], otherwise rethrows the captured [error].
  R get valueOrThrow {
    if (ok) return value as R;
    throw error!;
  }
}
