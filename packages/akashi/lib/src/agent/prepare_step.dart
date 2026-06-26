import 'dart:async';

import '../messages/message.dart';
import '../model/language_model.dart';

/// Context handed to a [PrepareStep] hook before each model call.
final class StepContext<TDeps> {
  /// Creates a step context.
  const StepContext({
    required this.step,
    required this.messages,
    required this.deps,
  });

  /// The zero-based step index about to run.
  final int step;

  /// The conversation as it stands.
  final List<Message> messages;

  /// The run's typed dependencies.
  final TDeps deps;
}

/// A per-step override returned by a [PrepareStep] hook. Any null field leaves
/// the agent's default in place.
final class StepConfig {
  /// Creates a step config.
  const StepConfig({
    this.messages,
    this.activeTools,
    this.toolChoice,
    this.model,
  });

  /// Replacement messages (e.g. a compacted history) for this step.
  final List<Message>? messages;

  /// Restrict tools to these names for this step.
  final List<String>? activeTools;

  /// Override the tool-choice directive for this step.
  final ToolChoice? toolChoice;

  /// Swap the model for this step (e.g. cheap → expensive escalation).
  final LanguageModel? model;
}

/// A context-engineering hook run before each step. Returning null keeps the
/// agent defaults.
typedef PrepareStep<TDeps> = FutureOr<StepConfig?> Function(
  StepContext<TDeps> ctx,
);
