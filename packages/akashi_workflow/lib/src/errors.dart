/// Raised inside a task when the run was cancelled (globally, by a deadline, or
/// by a fail-fast sibling). Not retryable.
class WorkflowCancelled implements Exception {
  /// Creates a cancellation error with an optional [reason].
  const WorkflowCancelled([this.reason]);

  /// Why the run was cancelled, if known.
  final String? reason;

  @override
  String toString() => 'WorkflowCancelled${reason == null ? '' : ': $reason'}';
}

/// A task exceeded its allotted [timeout]. Retryable by default (transient).
class WorkflowTimeout implements Exception {
  /// Creates a timeout error for task [label].
  const WorkflowTimeout(this.label, this.timeout);

  /// The task's label.
  final String label;

  /// The timeout that elapsed.
  final Duration timeout;

  @override
  String toString() =>
      'WorkflowTimeout: "$label" exceeded ${timeout.inMilliseconds}ms';
}

/// The workflow hit its [maxTasks] budget. A runaway-loop backstop; not retryable.
class WorkflowBudgetExceeded implements Exception {
  /// Creates a budget error for the configured [maxTasks].
  const WorkflowBudgetExceeded(this.maxTasks);

  /// The configured task ceiling.
  final int maxTasks;

  @override
  String toString() => 'WorkflowBudgetExceeded: exceeded maxTasks=$maxTasks';
}
