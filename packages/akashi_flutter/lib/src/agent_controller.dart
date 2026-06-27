import 'dart:async';

import 'package:akashi/akashi.dart';
import 'package:flutter/foundation.dart';

/// A tool call awaiting the user's approval decision, surfaced by an
/// [AgentController] so the UI can prompt and respond.
class PendingApproval {
  /// Wraps the [call] and the [_completer] the agent loop is awaiting.
  PendingApproval(this.call, this._completer);

  /// The tool call awaiting approval.
  final ToolCallPart call;

  final Completer<ApprovalDecision> _completer;

  /// Whether a decision has already been delivered.
  bool get isResolved => _completer.isCompleted;

  void _resolve(ApprovalDecision decision) {
    if (!_completer.isCompleted) _completer.complete(decision);
  }
}

/// A reactive [ChangeNotifier] that drives an [Agent] and folds its streamed
/// [AgentEvent]s into observable state for Flutter widgets.
///
/// It is also the agent's [ApprovalHandler]: wire it in at construction and the
/// controller surfaces a [pendingApproval] whenever a tool needs approval, which
/// the UI resolves via [approve] / [reject].
///
/// ```dart
/// final controller = AgentController<Deps>();
/// final agent = ToolLoopAgent<Deps>(
///   model: model, tools: tools, approvalHandler: controller);
/// controller.agent = agent;
/// // in a widget tree: AgentBuilder(controller: controller, builder: ...)
/// controller.send('Hello');
/// ```
class AgentController<TDeps> extends ChangeNotifier
    implements ApprovalHandler<TDeps> {
  /// Creates a controller, optionally pre-attached to [agent].
  AgentController({Agent<TDeps>? agent, this.deps}) : _agent = agent;

  Agent<TDeps>? _agent;

  /// The agent this controller drives. Set it after construction when the agent
  /// was built with this controller as its `approvalHandler` (a chicken-and-egg
  /// the late setter resolves).
  Agent<TDeps>? get agent => _agent;
  set agent(Agent<TDeps>? value) => _agent = value;

  /// Optional typed deps passed to each run.
  final TDeps? deps;

  final List<AgentEvent> _events = [];

  /// Every event seen so far this run, in order.
  List<AgentEvent> get events => List.unmodifiable(_events);

  String _text = '';

  /// The accumulated assistant text for the current run.
  String get text => _text;

  bool _isRunning = false;

  /// Whether a run is currently in flight.
  bool get isRunning => _isRunning;

  Object? _error;

  /// The error that ended the run, if any.
  Object? get error => _error;

  PendingApproval? _pendingApproval;

  /// A tool call awaiting the user's decision, or null.
  PendingApproval? get pendingApproval => _pendingApproval;

  /// Drive a run for [prompt]. A no-op when a run is already in flight or no
  /// [agent] is attached. Returns when the run finishes (or suspends/errors).
  Future<void> send(Object prompt, {RunOptions? options}) async {
    final target = _agent;
    if (target == null || _isRunning) return;
    _events.clear();
    _text = '';
    _error = null;
    _pendingApproval = null;
    _isRunning = true;
    notifyListeners();
    try {
      await for (final event in target.stream(
        prompt,
        deps: deps,
        options: options,
      )) {
        _events.add(event);
        if (event is TextDelta) _text += event.text;
        if (event is ErrorEvent) _error = event.error;
        notifyListeners();
      }
    } catch (error) {
      _error = error;
    } finally {
      _isRunning = false;
      _pendingApproval = null;
      notifyListeners();
    }
  }

  @override
  Future<ApprovalDecision> decide(ToolCallPart call, ToolContext<TDeps> ctx) {
    final completer = Completer<ApprovalDecision>();
    _pendingApproval = PendingApproval(call, completer);
    notifyListeners();
    return completer.future;
  }

  /// Approve the [pendingApproval] call, resuming the paused run.
  void approve() {
    _pendingApproval?._resolve(const ApprovalDecision.approved());
    _pendingApproval = null;
    notifyListeners();
  }

  /// Reject the [pendingApproval] call (fed back to the model as an error
  /// result), optionally with a [reason].
  void reject([String? reason]) {
    _pendingApproval?._resolve(ApprovalDecision.rejected(reason));
    _pendingApproval = null;
    notifyListeners();
  }
}
