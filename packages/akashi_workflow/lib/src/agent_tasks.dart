import 'package:akashi/akashi.dart';

import 'retry.dart';
import 'task.dart';

/// A [Task] that runs [agent] on [prompt] and returns its final text.
///
/// Cancellation is wired through: the task's [TaskContext.cancel] is passed to
/// the agent run, so a workflow cancellation/timeout cooperatively stops the
/// agent loop.
///
/// ```dart
/// await workflow.parallel([
///   for (final q in questions) agentTask(researcher, q, label: 'research'),
/// ]);
/// ```
Task<String> agentTask<TDeps>(
  Agent<TDeps> agent,
  Object prompt, {
  TDeps? deps,
  String? label,
  RetryPolicy? retry,
  Duration? timeout,
}) {
  return Task<String>(
    (ctx) async {
      final result = await agent.run(
        prompt,
        deps: deps,
        options: RunOptions(cancel: ctx.cancel),
      );
      return result.text;
    },
    label: label ?? 'agent',
    retry: retry,
    timeout: timeout,
  );
}

/// A [Task] that runs [agent]'s `generateObject` against [schema] and returns the
/// decoded, validated `T`. Cancellation is wired through as in [agentTask].
Task<T> objectTask<T, TDeps>(
  Agent<TDeps> agent,
  Object prompt, {
  required Schema<T> schema,
  TDeps? deps,
  String? label,
  RetryPolicy? retry,
  Duration? timeout,
}) {
  return Task<T>(
    (ctx) async {
      final result = await agent.generateObject<T>(
        prompt,
        schema: schema,
        deps: deps,
        options: RunOptions(cancel: ctx.cancel),
      );
      return result.object;
    },
    label: label ?? 'agent.object',
    retry: retry,
    timeout: timeout,
  );
}
