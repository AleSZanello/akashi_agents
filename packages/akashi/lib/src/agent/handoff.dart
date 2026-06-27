import 'tool_loop_agent.dart';

/// A control-transfer target: when the model calls `transfer_to_<name>`, the
/// loop switches the active agent to [agent] for all subsequent steps, while
/// the message history carries across unchanged.
///
/// Unlike a subagent (see `Agent.asTool`), a handoff is a *transfer*, not a
/// subroutine — the target takes over the conversation rather than returning a
/// result to the caller. Targets must be [ToolLoopAgent]s sharing the same
/// `TDeps`, because the swap needs their model/instructions/tools/handoffs,
/// which the bare `Agent` interface does not expose.
///
/// ```dart
/// final billing = ToolLoopAgent<Shared>(
///   model: model, instructions: 'You handle billing.', tools: [refund]);
/// final triage = ToolLoopAgent<Shared>(
///   model: model,
///   instructions: 'Route the user to a specialist.',
///   handoffs: [handoff(billing, name: 'billing')],
/// );
/// ```
final class Handoff<TDeps> {
  /// Creates a handoff exposed to the model as `transfer_to_<name>`.
  const Handoff({
    required this.name,
    required this.agent,
    this.description,
  });

  /// The target's short name; forms the `transfer_to_<name>` tool.
  final String name;

  /// The agent to transfer control to.
  final ToolLoopAgent<TDeps> agent;

  /// An optional description for the generated transfer tool.
  final String? description;
}

/// Builds a [Handoff] to [target], named [name].
Handoff<TDeps> handoff<TDeps>(
  ToolLoopAgent<TDeps> target, {
  required String name,
  String? description,
}) =>
    Handoff(name: name, agent: target, description: description);
