import 'dart:async';

import '../messages/message.dart';
import '../tool/tool.dart';

/// The decision returned by an [ApprovalHandler] for a pending tool call.
final class ApprovalDecision {
  /// Approve the call.
  const ApprovalDecision.approved()
      : rejected = false,
        reason = null;

  /// Reject the call, optionally with a [reason] fed back to the model.
  const ApprovalDecision.rejected([this.reason]) : rejected = true;

  /// Whether the call was rejected.
  final bool rejected;

  /// The rejection reason, if any.
  final String? reason;
}

/// Resolves human-in-the-loop approval for tools that opt in via
/// `needsApproval`. In v0.1 this is an in-process callback; durable
/// suspend/resume across processes arrives with the checkpoint store.
abstract interface class ApprovalHandler<TDeps> {
  /// Decide whether [call] may execute, given its [ctx].
  Future<ApprovalDecision> decide(ToolCallPart call, ToolContext<TDeps> ctx);
}

/// An [ApprovalHandler] backed by a single callback — e.g. a CLI prompt or a
/// Flutter dialog. Return `true` to approve, `false` to reject; an optional
/// [reasonFor] supplies the rejection reason fed back to the model.
final class CallbackApprovalHandler<TDeps> implements ApprovalHandler<TDeps> {
  /// Wraps an [approve] callback.
  const CallbackApprovalHandler(
    this._approve, {
    String Function(ToolCallPart call)? reasonFor,
  }) : _reasonFor = reasonFor;

  final FutureOr<bool> Function(ToolCallPart call) _approve;
  final String Function(ToolCallPart call)? _reasonFor;

  @override
  Future<ApprovalDecision> decide(
    ToolCallPart call,
    ToolContext<TDeps> ctx,
  ) async {
    final approved = await _approve(call);
    return approved
        ? const ApprovalDecision.approved()
        : ApprovalDecision.rejected(_reasonFor?.call(call));
  }
}
