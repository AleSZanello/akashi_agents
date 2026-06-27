import '../agent/results.dart';
import '../messages/message.dart';
import '../model/usage.dart';

/// An event emitted by an agent run. Sealed for exhaustive `switch`.
///
/// `ToolLoopAgent.stream` is the primitive that yields these; `run` collects
/// over the same stream. [ApprovalRequest] is part of the contract from v0.1
/// even though durable human-in-the-loop lands later — so the event surface
/// never breaks.
sealed class AgentEvent {
  /// Creates an event tagged with the [step] it belongs to.
  const AgentEvent(this.step);

  /// The zero-based step index this event belongs to.
  final int step;
}

/// The run has started.
final class RunStart extends AgentEvent {
  /// Creates a run-start event.
  const RunStart(super.step);
}

/// A step (one model turn) has started.
final class StepStart extends AgentEvent {
  /// Creates a step-start event.
  const StepStart(super.step);
}

/// An incremental chunk of assistant text.
final class TextDelta extends AgentEvent {
  /// Creates a text delta.
  const TextDelta(super.step, this.text);

  /// The text fragment.
  final String text;
}

/// An incremental chunk of reasoning text.
final class ReasoningDelta extends AgentEvent {
  /// Creates a reasoning delta.
  const ReasoningDelta(super.step, this.text);

  /// The reasoning fragment.
  final String text;
}

/// The model opened a tool call.
final class ToolCallStart extends AgentEvent {
  /// Creates a tool-call-start event.
  const ToolCallStart(super.step,
      {required this.toolCallId, required this.toolName});

  /// The provider-assigned call id.
  final String toolCallId;

  /// The tool's name.
  final String toolName;
}

/// An incremental chunk of a tool call's arguments.
final class ToolCallArgsDelta extends AgentEvent {
  /// Creates a tool-call-args delta event.
  const ToolCallArgsDelta(super.step,
      {required this.toolCallId, required this.argsDelta});

  /// The call id these args belong to.
  final String toolCallId;

  /// A fragment of the arguments JSON string.
  final String argsDelta;
}

/// A tool call is fully assembled and about to execute.
final class ToolCallReady extends AgentEvent {
  /// Creates a tool-call-ready event.
  const ToolCallReady(super.step, this.call);

  /// The assembled tool call.
  final ToolCallPart call;
}

/// A tool requires human approval before executing. The loop pauses here.
final class ApprovalRequest extends AgentEvent {
  /// Creates an approval-request event.
  const ApprovalRequest(super.step, this.call);

  /// The call awaiting approval.
  final ToolCallPart call;
}

/// A tool finished executing.
final class ToolResult extends AgentEvent {
  /// Creates a tool-result event.
  const ToolResult(super.step, this.result);

  /// The tool result.
  final ToolResultPart result;
}

/// Control was transferred from one agent to another via a `transfer_to_<name>`
/// tool call (see `Handoff`). Subsequent steps use the [to] agent's model,
/// tools, and instructions; the message history carries across.
final class HandoffEvent extends AgentEvent {
  /// Creates a handoff event recording the transfer from [from] to [to].
  const HandoffEvent(super.step, {required this.from, required this.to});

  /// The name of the agent handing off control.
  final String from;

  /// The name of the agent taking over.
  final String to;
}

/// A step finished (model turn plus any tool execution).
final class StepFinish extends AgentEvent {
  /// Creates a step-finish event.
  const StepFinish(super.step, this.result);

  /// The step's result.
  final StepResult result;
}

/// The run finished.
final class RunFinish extends AgentEvent {
  /// Creates a run-finish event.
  const RunFinish(
    super.step, {
    required this.finishReason,
    required this.usage,
    required this.text,
  });

  /// Why the run ended.
  final FinishReason finishReason;

  /// Total token usage.
  final Usage usage;

  /// The final assistant text.
  final String text;
}

/// A recoverable error occurred (e.g. a tool threw). The loop continues unless
/// the error is fatal.
final class ErrorEvent extends AgentEvent {
  /// Creates an error event.
  const ErrorEvent(super.step, this.error, this.stackTrace);

  /// The error.
  final Object error;

  /// The captured stack trace.
  final StackTrace stackTrace;
}
