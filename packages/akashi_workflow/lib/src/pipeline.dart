import 'package:akashi/akashi.dart';

import 'retry.dart';

/// The context handed to a pipeline stage body. Like a task context, plus the
/// item's [index] and the [originalItem] the pipeline started with.
class StageContext {
  /// Creates a stage context.
  const StageContext({
    required this.cancel,
    required this.attempt,
    required this.tracer,
    required this.index,
    required this.originalItem,
  });

  /// Cooperative cancellation for this stage attempt.
  final CancellationToken cancel;

  /// The 1-based attempt number for this stage.
  final int attempt;

  /// Tracer for stage-scoped spans.
  final Tracer tracer;

  /// The item's index in the original input list.
  final int index;

  /// The item the pipeline started with (typed as the pipeline input `I`).
  final Object? originalItem;
}

/// A single stage in a [Pipeline] (internal representation).
class PipelineStage {
  /// Creates a pipeline stage.
  const PipelineStage({
    required this.name,
    required this.body,
    this.retry,
    this.timeout,
  });

  /// The stage name (surfaced in events/traces).
  final String name;

  /// The stage body, erased to `Object?` for storage in a heterogeneous list.
  final Future<Object?> Function(Object? input, StageContext ctx) body;

  /// Per-stage retry override.
  final RetryPolicy? retry;

  /// Per-stage timeout override.
  final Duration? timeout;
}

/// A typed, reusable sequence of stages each item flows through independently.
///
/// Build it fluently — types chain stage to stage — then hand it to
/// `Workflow.pipeline(items, pipeline)`. There is **no barrier** between stages:
/// item A can be in stage 3 while item B is still in stage 1, so wall-clock is
/// the slowest single chain, not the sum of per-stage maxima.
///
/// ```dart
/// final p = Pipeline.input<Topic>()
///   .stage('research', (topic, ctx) => researcher.run(topic.q))   // Topic -> RunResult
///   .stage('verify',   (res, ctx) => verifier.run(res.text));     // RunResult -> Verdict
/// final results = await workflow.pipeline(topics, p); // List<TaskResult<Verdict>>
/// ```
class Pipeline<I, O> {
  const Pipeline._(this.stages);

  /// The ordered stages (internal).
  final List<PipelineStage> stages;

  /// Start an empty pipeline whose input and output are both `I`.
  static Pipeline<I, I> input<I>() => Pipeline<I, I>._(const <PipelineStage>[]);

  /// Append a stage mapping the current output `O` to `N`.
  Pipeline<I, N> stage<N>(
    String name,
    Future<N> Function(O input, StageContext ctx) body, {
    RetryPolicy? retry,
    Duration? timeout,
  }) {
    return Pipeline<I, N>._([
      ...stages,
      PipelineStage(
        name: name,
        retry: retry,
        timeout: timeout,
        body: (input, ctx) async => await body(input as O, ctx),
      ),
    ]);
  }
}
