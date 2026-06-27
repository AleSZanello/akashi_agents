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
///
/// ## Approval: in-process vs. durable
///
/// The controller resolves either approval style from the same [approve] /
/// [reject] call:
///
/// - **In-process** (the default): the agent has this controller as its
///   `approvalHandler`. A pending call blocks the loop in memory; [approve] /
///   [reject] complete it.
/// - **Durable** (`ToolLoopAgent(durableApproval: true)` with a
///   `CheckpointStore`): the run persists a checkpoint and *suspends* — the
///   stream ends with [suspended] set instead of a live [pendingApproval].
///   [approve] / [reject] then `resume` the run from the store. This survives a
///   process restart; after a restart, attach the same agent and call [resume]
///   (or `approve`/`reject` once a fresh run has re-surfaced [suspended]).
///
/// ## Transcript
///
/// [messages] accumulates a [Message] transcript across turns — the user
/// prompts plus the assistant/tool messages this controller observed — suitable
/// for a `MessageListView`. The in-flight assistant text is also available live
/// via [text]. Note the transcript reflects what *this* controller saw; after a
/// cross-process durable resume, seed prior turns from your checkpoint store.
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

  final List<Message> _messages = [];

  /// The accumulated conversation transcript across turns: user prompts plus the
  /// assistant/tool messages this controller has observed. Drop into a
  /// `MessageListView`. The currently-streaming assistant text lives in [text]
  /// until its step finishes and is committed here.
  List<Message> get messages => List.unmodifiable(_messages);

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

  /// A tool call awaiting the user's in-process decision, or null. Durable
  /// suspensions surface as [suspended] instead.
  PendingApproval? get pendingApproval => _pendingApproval;

  Suspended? _suspended;

  /// A durable run paused awaiting approval, or null. Set when a
  /// `durableApproval` agent persists a checkpoint and throws [Suspended];
  /// cleared once [approve] / [reject] (or [resume]) continues the run.
  Suspended? get suspended => _suspended;

  /// Whether the run is paused on a durable approval (see [suspended]).
  bool get isSuspended => _suspended != null;

  /// Drive a run for [prompt]. A no-op when a run is already in flight or no
  /// [agent] is attached. Returns when the run finishes (or suspends/errors).
  ///
  /// The prompt is appended to the [messages] transcript and the agent is driven
  /// over the full history, so successive [send]s form a multi-turn
  /// conversation.
  Future<void> send(Object prompt, {RunOptions? options}) async {
    final target = _agent;
    if (target == null || _isRunning) return;
    final turn = _userTurn(prompt);
    _events.clear();
    _text = '';
    _error = null;
    _pendingApproval = null;
    _suspended = null;
    _isRunning = true;
    if (turn != null) _messages.addAll(turn);
    notifyListeners();
    // For an unsupported prompt shape, defer to the agent's own validation.
    await _consume(
      target.stream(
        turn != null ? _messages : prompt,
        deps: deps,
        options: options,
      ),
    );
  }

  /// Resume a suspended durable run from the checkpoint store by [checkpointId],
  /// optionally applying an approval [decision]. A no-op unless the attached
  /// agent is a [ToolLoopAgent] and no run is in flight.
  ///
  /// Use this after a process restart (a fresh controller with no in-memory
  /// [suspended]); within a live session, [approve] / [reject] resume for you.
  Future<void> resume(
    String checkpointId, {
    ApprovalDecision? decision,
    RunOptions? options,
  }) async {
    final target = _agent;
    if (target is! ToolLoopAgent<TDeps> || _isRunning) return;
    _suspended = null;
    _error = null;
    _pendingApproval = null;
    _isRunning = true;
    notifyListeners();
    await _consume(
      target.resume(
        checkpointId,
        decision: decision,
        deps: deps,
        options: options,
      ),
    );
  }

  /// Fold an event stream into observable state. Shared by [send] and [resume].
  Future<void> _consume(Stream<AgentEvent> stream) async {
    try {
      await for (final event in stream) {
        _events.add(event);
        if (event is TextDelta) _text += event.text;
        if (event is ErrorEvent) _error = event.error;
        if (event is StepFinish) _commitStep(event.result);
        notifyListeners();
      }
    } on Suspended catch (s) {
      _suspended = s;
    } catch (error) {
      _error = error;
    } finally {
      _isRunning = false;
      _pendingApproval = null;
      notifyListeners();
    }
  }

  /// Commit a finished step's assistant and tool messages to the transcript.
  void _commitStep(StepResult result) {
    final content = <Part>[
      if (result.text.isNotEmpty) TextPart(result.text),
      ...result.toolCalls,
    ];
    if (content.isNotEmpty) _messages.add(AssistantMessage(content));
    if (result.toolResults.isNotEmpty) {
      _messages.add(ToolMessage(result.toolResults));
    }
  }

  /// Map a [send] prompt onto the user message(s) to append, or null when the
  /// shape is unsupported (left for the agent to validate).
  List<Message>? _userTurn(Object prompt) => switch (prompt) {
    final String s => [UserMessage.text(s)],
    final Message m => [m],
    final Iterable<Message> it => it.toList(),
    _ => null,
  };

  @override
  Future<ApprovalDecision> decide(ToolCallPart call, ToolContext<TDeps> ctx) {
    final completer = Completer<ApprovalDecision>();
    _pendingApproval = PendingApproval(call, completer);
    notifyListeners();
    return completer.future;
  }

  /// Approve the pending call, resuming the paused run — whether it paused
  /// in-process ([pendingApproval]) or durably ([suspended]).
  void approve() => _resolve(const ApprovalDecision.approved());

  /// Reject the pending call (fed back to the model as an error result),
  /// optionally with a [reason]. Resolves either the in-process
  /// [pendingApproval] or a durable [suspended] pause.
  void reject([String? reason]) => _resolve(ApprovalDecision.rejected(reason));

  void _resolve(ApprovalDecision decision) {
    final pending = _pendingApproval;
    if (pending != null) {
      pending._resolve(decision);
      _pendingApproval = null;
      notifyListeners();
      return;
    }
    final paused = _suspended;
    if (paused != null) {
      unawaited(resume(paused.checkpointId, decision: decision));
    }
  }
}
