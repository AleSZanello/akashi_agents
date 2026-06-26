import '../messages/message.dart';
import '../model/usage.dart';

/// The outcome of a single step (one model turn plus any tool execution).
final class StepResult {
  /// Creates a step result.
  const StepResult({
    required this.step,
    required this.text,
    required this.toolCalls,
    required this.toolResults,
    required this.finishReason,
    required this.usage,
  });

  /// The zero-based step index.
  final int step;

  /// Assistant text produced this step.
  final String text;

  /// Tool calls the model requested this step.
  final List<ToolCallPart> toolCalls;

  /// Results of executing [toolCalls].
  final List<ToolResultPart> toolResults;

  /// Why the model turn ended.
  final FinishReason finishReason;

  /// Token usage for this step.
  final Usage usage;
}

/// The outcome of a full agent run.
final class RunResult {
  /// Creates a run result.
  const RunResult({
    required this.text,
    required this.messages,
    required this.responseMessages,
    required this.steps,
    required this.usage,
    required this.finishReason,
  });

  /// The final assistant text.
  final String text;

  /// The complete conversation, including the original prompt.
  final List<Message> messages;

  /// Only the messages generated during this run.
  final List<Message> responseMessages;

  /// Per-step results.
  final List<StepResult> steps;

  /// Total token usage across all steps.
  final Usage usage;

  /// Why the run ended.
  final FinishReason finishReason;
}

/// A validated structured-output result plus the underlying [raw] run.
final class ObjectResult<T> {
  /// Creates an object result.
  const ObjectResult({required this.object, required this.raw});

  /// The decoded object.
  final T object;

  /// The full run that produced it.
  final RunResult raw;
}
