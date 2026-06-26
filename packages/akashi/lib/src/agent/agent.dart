import '../model/language_model.dart';
import '../schema/schema.dart';
import '../streaming/agent_event.dart';
import '../util/cancellation.dart';
import 'results.dart';

/// Per-run knobs shared by all [Agent] entry points.
final class RunOptions {
  /// Creates run options.
  const RunOptions({
    this.cancel,
    this.temperature,
    this.maxOutputTokens,
    this.maxRepairAttempts = 2,
    this.checkpointId,
    this.responseFormat,
  });

  /// A cancellation token (one is created per run if omitted).
  final CancellationToken? cancel;

  /// Sampling temperature override.
  final double? temperature;

  /// Output token cap override.
  final int? maxOutputTokens;

  /// For `generateObject`: how many times to re-prompt on validation failure.
  final int maxRepairAttempts;

  /// A stable run id used when a checkpoint store is configured.
  final String? checkpointId;

  /// The desired output shape for this run. When null, the loop uses
  /// [ResponseFormat.text]. `generateObject` sets this when a model supports
  /// native JSON-Schema output.
  final ResponseFormat? responseFormat;
}

/// The agent contract.
///
/// This is an **interface**, not just a class: `ToolLoopAgent` is the default
/// implementation, but durable and multi-agent loops can implement [Agent]
/// without changing any caller.
abstract interface class Agent<TDeps> {
  /// Run to completion and return the buffered result.
  Future<RunResult> run(Object prompt, {TDeps? deps, RunOptions? options});

  /// Run and stream [AgentEvent]s as they happen. This is the primitive; [run]
  /// collects over it.
  Stream<AgentEvent> stream(Object prompt, {TDeps? deps, RunOptions? options});

  /// Run and decode the final output against [schema], repairing on validation
  /// failure up to `options.maxRepairAttempts`.
  Future<ObjectResult<T>> generateObject<T>(
    Object prompt, {
    required Schema<T> schema,
    TDeps? deps,
    RunOptions? options,
  });
}
