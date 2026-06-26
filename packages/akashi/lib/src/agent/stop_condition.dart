import 'dart:async';

import 'results.dart';

/// Context passed to a [StopCondition] after each completed step.
final class StopContext {
  /// Creates a stop context.
  const StopContext({
    required this.stepCount,
    required this.steps,
    required this.lastStep,
  });

  /// The number of steps completed so far.
  final int stepCount;

  /// All step results so far.
  final List<StepResult> steps;

  /// The most recent step result.
  final StepResult lastStep;
}

/// Decides whether the agent loop should stop. Composable: an agent stops when
/// **any** of its conditions returns true.
typedef StopCondition = FutureOr<bool> Function(StopContext ctx);

/// Stop once [n] steps have completed.
StopCondition stepCountIs(int n) => (ctx) => ctx.stepCount >= n;

/// Stop when the model produced text and requested no tools (a final answer).
StopCondition hasText() => (ctx) =>
    ctx.lastStep.text.trim().isNotEmpty && ctx.lastStep.toolCalls.isEmpty;

/// Stop as soon as a tool named [name] has been called.
StopCondition hasToolCall(String name) =>
    (ctx) => ctx.lastStep.toolCalls.any((c) => c.toolName == name);
