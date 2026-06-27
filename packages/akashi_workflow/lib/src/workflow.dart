import 'dart:async';
import 'dart:math';

import 'package:akashi/akashi.dart';

import 'concurrency.dart';
import 'errors.dart';
import 'events.dart';
import 'pipeline.dart';
import 'retry.dart';
import 'task.dart';

/// A deterministic, code-driven orchestrator for Akashi agents (and any async
/// work). You write the control flow — fan-out, pipelines, loops — and the
/// workflow supplies the production concerns: bounded concurrency, retries with
/// backoff, per-task and global timeouts, cooperative cancellation, a runaway
/// budget guard, and an observable [events] stream.
///
/// This complements Akashi's *model-driven* multi-agent primitives
/// (`Agent.asTool`, handoffs): there the model decides the topology at runtime;
/// here the topology is fixed in your Dart code.
///
/// ```dart
/// final wf = Workflow(maxConcurrency: 4, defaultRetry: RetryPolicy.standard);
/// // Fan out, bounded to 4 at a time, each retried up to 3x:
/// final findings = await wf.parallel([
///   for (final q in questions) agentTask(researcher, q.prompt, label: q.id),
/// ]);
/// final report = await wf.run(agentTask(writer, synthesisPrompt(findings)));
/// wf.dispose();
/// ```
class Workflow {
  /// Creates a workflow.
  ///
  /// [maxConcurrency] bounds simultaneous task executions. [defaultRetry] and
  /// [defaultTimeout] apply to tasks that don't override them. [deadline] cancels
  /// the whole run after a duration; [cancel] links an external token so callers
  /// can cancel from outside. [maxTasks] caps total task executions (a
  /// runaway-loop backstop). [random] is injectable for deterministic jitter.
  Workflow({
    int maxConcurrency = 8,
    this.defaultRetry = RetryPolicy.none,
    this.defaultTimeout,
    Duration? deadline,
    this.maxTasks,
    CancellationToken? cancel,
    this.tracer = const NoopTracer(),
    Random? random,
  })  : assert(maxConcurrency > 0, 'maxConcurrency must be > 0'),
        _semaphore = Semaphore(maxConcurrency),
        _random = random ?? Random(),
        _cancel = CancellationToken() {
    if (cancel != null) {
      if (cancel.isCancelled) {
        _cancel.cancel();
      } else {
        cancel.whenCancelled.then((_) => _cancel.cancel());
      }
    }
    if (deadline != null) {
      _deadlineTimer = Timer(deadline, () => _cancel.cancel());
    }
  }

  /// Default retry policy for tasks without their own.
  final RetryPolicy defaultRetry;

  /// Default per-task timeout for tasks without their own.
  final Duration? defaultTimeout;

  /// Ceiling on total task executions, or null for unbounded.
  final int? maxTasks;

  /// Tracer for `workflow.task` spans.
  final Tracer tracer;

  final Semaphore _semaphore;
  final Random _random;
  final CancellationToken _cancel;
  Timer? _deadlineTimer;
  int _taskCount = 0;

  final StreamController<WorkflowEvent> _events =
      StreamController<WorkflowEvent>.broadcast();

  /// A broadcast stream of task lifecycle [WorkflowEvent]s.
  Stream<WorkflowEvent> get events => _events.stream;

  /// The workflow-wide cancellation token (cancelled by [cancelAll], a deadline,
  /// or a linked external token).
  CancellationToken get cancel => _cancel;

  /// Whether the run has been cancelled.
  bool get isCancelled => _cancel.isCancelled;

  /// Total task executions started so far (counts retries).
  int get tasksRun => _taskCount;

  /// Cancel everything in flight (cooperative).
  void cancelAll() => _cancel.cancel();

  /// Run [task] to success, or throw its error after exhausting retries.
  Future<R> run<R>(Task<R> task) async {
    final result = await runCatching<R>(task);
    return result.valueOrThrow;
  }

  /// Run [task] and return a settled [TaskResult] — never throws (except if the
  /// workflow is disposed). Use when you want to inspect failures yourself.
  Future<TaskResult<R>> runCatching<R>(Task<R> task,
          {CancellationToken? scope}) =>
      _execute<R>(task, scope ?? _cancel);

  /// Run [tasks] concurrently (bounded by `maxConcurrency`) and return their
  /// values in order. **Fail-fast:** the first failure cancels the remaining
  /// siblings (cooperatively) and is rethrown. For partial results, use
  /// [parallelSettled].
  Future<List<R>> parallel<R>(Iterable<Task<R>> tasks) async {
    final list = tasks.toList();
    final scope = _link(_cancel);
    Object? firstError;
    StackTrace? firstStack;
    final futures = <Future<TaskResult<R>>>[];
    for (final task in list) {
      final future = runCatching<R>(task, scope: scope);
      future.then((result) {
        if (!result.ok && firstError == null) {
          firstError = result.error;
          firstStack = result.stackTrace;
          if (!scope.isCancelled) scope.cancel();
        }
      });
      futures.add(future);
    }
    final settled = await Future.wait(futures);
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack ?? StackTrace.current);
    }
    return [for (final result in settled) result.value as R];
  }

  /// Run [tasks] concurrently and return every settled [TaskResult] — successes
  /// and failures both — in order. Never throws; nothing is cancelled on failure.
  Future<List<TaskResult<R>>> parallelSettled<R>(Iterable<Task<R>> tasks) {
    return Future.wait([for (final task in tasks) runCatching<R>(task)]);
  }

  /// Stream each of [items] through [pipeline]'s stages independently (no barrier
  /// between stages) and return a settled [TaskResult] per item. A stage that
  /// throws drops just that item to a failure result; the rest continue.
  Future<List<TaskResult<O>>> pipeline<I, O>(
    Iterable<I> items,
    Pipeline<I, O> pipeline,
  ) {
    final list = items.toList();
    return Future.wait([
      for (var i = 0; i < list.length; i++)
        _runPipelineItem<O>(list[i], i, pipeline.stages),
    ]);
  }

  /// Release resources (the deadline timer and the events stream).
  void dispose() {
    _deadlineTimer?.cancel();
    if (!_events.isClosed) _events.close();
  }

  Future<TaskResult<O>> _runPipelineItem<O>(
    Object? item,
    int index,
    List<PipelineStage> stages,
  ) async {
    final stopwatch = Stopwatch()..start();
    Object? current = item;
    var attempts = 0;
    for (final stage in stages) {
      final task = Task<Object?>(
        (ctx) => stage.body(
          current,
          StageContext(
            cancel: ctx.cancel,
            attempt: ctx.attempt,
            tracer: ctx.tracer,
            index: index,
            originalItem: item,
          ),
        ),
        label: stage.name,
        retry: stage.retry,
        timeout: stage.timeout,
      );
      final result = await runCatching<Object?>(task);
      attempts += result.attempts;
      if (!result.ok) {
        return TaskResult<O>.failure(
          label: stage.name,
          error: result.error!,
          stackTrace: result.stackTrace,
          attempts: attempts,
          duration: stopwatch.elapsed,
        );
      }
      current = result.value;
    }
    return TaskResult<O>.success(
      label: 'pipeline[$index]',
      value: current as O,
      attempts: attempts,
      duration: stopwatch.elapsed,
    );
  }

  Future<TaskResult<R>> _execute<R>(
    Task<R> task,
    CancellationToken governing,
  ) async {
    final policy = task.retry ?? defaultRetry;
    final timeout = task.timeout ?? defaultTimeout;
    final stopwatch = Stopwatch()..start();
    var attempt = 0;

    while (true) {
      attempt++;

      if (governing.isCancelled) {
        return TaskResult<R>.failure(
          label: task.label,
          error: const WorkflowCancelled('cancelled before start'),
          attempts: attempt,
          duration: stopwatch.elapsed,
        );
      }
      if (maxTasks != null && _taskCount >= maxTasks!) {
        return TaskResult<R>.failure(
          label: task.label,
          error: WorkflowBudgetExceeded(maxTasks!),
          attempts: attempt,
          duration: stopwatch.elapsed,
        );
      }
      _taskCount++;

      final attemptToken = _link(governing);
      final ctx = TaskContext(
        cancel: attemptToken,
        attempt: attempt,
        tracer: tracer,
        label: task.label,
      );

      // Acquire a permit FIRST, so TaskStarted reflects actually-running work
      // (queued tasks stay silent) and the backoff delay never holds a permit.
      await _semaphore.acquire();
      _emit(TaskStarted(label: task.label, attempt: attempt));
      final span = tracer.startSpan(
        'workflow.task',
        attributes: {'label': task.label, 'attempt': attempt},
      );
      final attemptStopwatch = Stopwatch()..start();

      R? value;
      var succeeded = false;
      Object? caughtError;
      StackTrace? caughtStack;
      try {
        if (governing.isCancelled) {
          throw const WorkflowCancelled('cancelled while queued');
        }
        value = timeout == null
            ? await task.body(ctx)
            : await task.body(ctx).timeout(
                timeout,
                onTimeout: () {
                  attemptToken.cancel();
                  throw WorkflowTimeout(task.label, timeout);
                },
              );
        succeeded = true;
      } catch (error, stackTrace) {
        caughtError = error;
        caughtStack = stackTrace;
      } finally {
        _semaphore.release(); // release before any backoff
        span.end();
      }

      if (succeeded) {
        _emit(TaskSucceeded(
          label: task.label,
          attempt: attempt,
          duration: attemptStopwatch.elapsed,
        ));
        return TaskResult<R>.success(
          label: task.label,
          value: value as R,
          attempts: attempt,
          duration: stopwatch.elapsed,
        );
      }

      final error = caughtError!;
      final retryable = attempt < policy.maxAttempts &&
          !governing.isCancelled &&
          (policy.retryIf?.call(error) ?? _defaultRetryable(error));
      _emit(TaskFailed(
        label: task.label,
        attempt: attempt,
        error: error,
        willRetry: retryable,
      ));
      if (!retryable) {
        return TaskResult<R>.failure(
          label: task.label,
          error: error,
          stackTrace: caughtStack,
          attempts: attempt,
          duration: stopwatch.elapsed,
        );
      }
      final delay = policy.backoffFor(attempt, _random);
      _emit(TaskRetrying(
        label: task.label,
        nextAttempt: attempt + 1,
        delay: delay,
      ));
      if (delay > Duration.zero) {
        // Wake early if the run is cancelled during the backoff.
        await Future.any<void>([
          Future<void>.delayed(delay),
          governing.whenCancelled,
        ]);
      }
    }
  }

  static bool _defaultRetryable(Object error) =>
      error is! WorkflowCancelled && error is! WorkflowBudgetExceeded;

  void _emit(WorkflowEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  /// A child token that cancels when [parent] does (and starts cancelled if
  /// [parent] already is).
  CancellationToken _link(CancellationToken parent) {
    final token = CancellationToken();
    if (parent.isCancelled) {
      token.cancel();
    } else {
      parent.whenCancelled.then((_) => token.cancel());
    }
    return token;
  }
}
