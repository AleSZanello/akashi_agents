import 'package:flutter/widgets.dart';

import 'agent_controller.dart';

/// Rebuilds [builder] whenever [controller] notifies — an [AnimatedBuilder]
/// specialized for an [AgentController].
///
/// ```dart
/// AgentBuilder(
///   controller: controller,
///   builder: (context, c) => Text(c.text),
/// );
/// ```
class AgentBuilder<TDeps> extends StatelessWidget {
  /// Creates an agent builder bound to [controller].
  const AgentBuilder({
    super.key,
    required this.controller,
    required this.builder,
  });

  /// The controller whose state drives rebuilds.
  final AgentController<TDeps> controller;

  /// Builds the subtree from the current controller state.
  final Widget Function(BuildContext context, AgentController<TDeps> controller)
  builder;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => builder(context, controller),
  );
}
