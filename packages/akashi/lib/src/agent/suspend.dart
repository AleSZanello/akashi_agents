import '../messages/message.dart';

/// Thrown by a durable [ToolLoopAgent] run when a tool needs human approval.
///
/// Instead of blocking in memory on an [ApprovalHandler] (the in-process path),
/// a durable run persists a suspended checkpoint and throws this — so a run can
/// pause indefinitely without holding compute, spanning process restarts or
/// separate HTTP requests. Resume out of band once the human decides:
///
/// ```dart
/// try {
///   await agent.run(prompt, options: RunOptions(checkpointId: 'job-42'));
/// } on Suspended catch (s) {
///   // persist s.checkpointId, return to caller; later, elsewhere:
///   await agent.resume('job-42', decision: const ApprovalDecision.approved());
/// }
/// ```
final class Suspended implements Exception {
  /// Creates a suspension for run [checkpointId], awaiting approval of
  /// [pendingCall].
  const Suspended({required this.checkpointId, required this.pendingCall});

  /// The run id whose state was persisted; pass it to `ToolLoopAgent.resume`.
  final String checkpointId;

  /// The tool call awaiting a human decision.
  final ToolCallPart pendingCall;

  @override
  String toString() => 'Suspended(run "$checkpointId" awaiting approval for '
      '${pendingCall.toolName})';
}
