import 'dart:convert';

import '../schema/schema.dart';
import '../tool/tool.dart';
import 'agent.dart';

/// Turns any [Agent] into a [Tool] a parent agent can call — the core
/// multi-agent primitive ("agents as tools").
///
/// The child agent runs **fresh and isolated**: it gets its own empty-prefix
/// message history (just the prompt built from the call's input, plus its own
/// instructions) and its own tools. None of the parent's history leaks in, and
/// the child's tools are never advertised to the parent model — the only thing
/// the parent sees is this tool's [name]/[description]/[inputSchema] and the
/// child's final text coming back as the tool result.
///
/// Isolation is the point. Because the child runs behind the opaque
/// `Tool.execute -> Object?` boundary, its [AgentEvent]s and tracer spans do
/// **not** nest into the parent's stream; only a single `subagent.<name>` span
/// is emitted on the parent's tracer as a seam. This is deliberate, not a gap.
///
/// ```dart
/// final researcher = ToolLoopAgent<ResearchDeps>(
///   model: smallModel, tools: [search], instructions: 'Investigate concisely.');
///
/// final orchestrator = ToolLoopAgent<AppDeps>(
///   model: bigModel,
///   tools: [
///     researcher.asTool<({String question}), AppDeps>(
///       name: 'research',
///       description: 'Investigate a question and report findings.',
///       inputSchema: Schema.object(
///         {'question': Schema.string()},
///         required: ['question'],
///         fromJson: (j) => (question: j['question']! as String),
///       ),
///       deps: (input, ctx) => ResearchDeps(http: ctx.deps.http),
///     ),
///   ],
/// );
/// ```
extension AgentAsTool<TDeps> on Agent<TDeps> {
  /// Expose this agent as a [Tool] callable by a parent agent whose deps are
  /// [TParentDeps].
  ///
  /// [inputSchema] is advertised to the parent model and decodes the call into
  /// a typed `I`. [deps] maps the parent's [ToolContext] into the child's
  /// dependency object — the seam through which shared services/credentials
  /// pass into the isolated child. [promptBuilder] turns the typed input into
  /// the child's prompt; it defaults to JSON-encoding the raw input.
  Tool<TParentDeps> asTool<I, TParentDeps>({
    required String name,
    required String description,
    required Schema<I> inputSchema,
    required TDeps Function(I input, ToolContext<TParentDeps> ctx) deps,
    String Function(I input)? promptBuilder,
  }) {
    final child = this;
    // A pass-through schema: it advertises the real [inputSchema]'s JSON Schema
    // to the parent model, but hands `execute` the raw map so we can both
    // validate it to `I` and JSON-encode it for the default prompt. Mirrors how
    // the core `tool<I, TDeps>` factory recovers the erased input type `I`
    // inside a closure (a `Tool<TParentDeps>` cannot itself carry `I`).
    final passthrough = Schema.raw<Map<String, Object?>>(
      inputSchema.jsonSchema,
      (json) => (json! as Map).cast<String, Object?>(),
    );
    return tool<Map<String, Object?>, TParentDeps>(
      name: name,
      description: description,
      inputSchema: passthrough,
      execute: (raw, ctx) async {
        final typed = inputSchema.decode(raw); // validates + recovers `I`
        final prompt = promptBuilder?.call(typed) ?? jsonEncode(raw);
        final span = ctx.tracer
            .startSpan('subagent.$name', attributes: {'subagent': name});
        try {
          final result = await child.run(
            prompt,
            deps: deps(typed, ctx),
            options: RunOptions(cancel: ctx.cancel),
          );
          return result.text;
        } finally {
          span.end();
        }
      },
    );
  }
}
