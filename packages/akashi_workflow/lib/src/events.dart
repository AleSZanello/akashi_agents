/// An observable lifecycle event emitted by a `Workflow`. Subscribe via
/// `Workflow.events` to drive progress UIs, logs, or metrics. Sealed for
/// exhaustive `switch`.
sealed class WorkflowEvent {
  const WorkflowEvent({required this.label});

  /// The task (or pipeline stage) this event concerns.
  final String label;
}

/// A task attempt began.
final class TaskStarted extends WorkflowEvent {
  /// Creates a task-started event.
  const TaskStarted({required super.label, required this.attempt});

  /// The 1-based attempt number.
  final int attempt;
}

/// A task attempt completed successfully.
final class TaskSucceeded extends WorkflowEvent {
  /// Creates a task-succeeded event.
  const TaskSucceeded({
    required super.label,
    required this.attempt,
    required this.duration,
  });

  /// The attempt that succeeded.
  final int attempt;

  /// How long the successful attempt took.
  final Duration duration;
}

/// A task attempt threw.
final class TaskFailed extends WorkflowEvent {
  /// Creates a task-failed event.
  const TaskFailed({
    required super.label,
    required this.attempt,
    required this.error,
    required this.willRetry,
  });

  /// The attempt that failed.
  final int attempt;

  /// The error thrown.
  final Object error;

  /// Whether another attempt will follow.
  final bool willRetry;
}

/// A failed task is about to be retried after [delay].
final class TaskRetrying extends WorkflowEvent {
  /// Creates a task-retrying event.
  const TaskRetrying({
    required super.label,
    required this.nextAttempt,
    required this.delay,
  });

  /// The upcoming attempt number.
  final int nextAttempt;

  /// The backoff delay before the next attempt.
  final Duration delay;
}
