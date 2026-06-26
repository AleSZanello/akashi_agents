import 'dart:async';

import '../messages/message.dart';
import '../model/language_model.dart';
import '../observability/tracer.dart';
import '../schema/schema.dart';
import '../util/cancellation.dart';

/// The typed context handed to a tool's `execute`/`needsApproval` callbacks.
///
/// [deps] is the agent's typed dependency object — Akashi's analog of
/// dependency injection (Pydantic AI's `RunContext`). It lets tools reach
/// services, credentials, and per-request state with full static typing.
final class ToolContext<TDeps> {
  /// Creates a tool context.
  const ToolContext({
    required this.deps,
    required this.toolCallId,
    required this.step,
    required this.history,
    required this.cancel,
    required this.tracer,
  });

  /// The run's typed dependencies.
  final TDeps deps;

  /// The id of the call being handled.
  final String toolCallId;

  /// The current step index.
  final int step;

  /// The conversation so far (read-only).
  final List<Message> history;

  /// Cooperative cancellation signal.
  final CancellationToken cancel;

  /// Tracer for emitting tool-scoped events.
  final Tracer tracer;
}

/// A tool the agent can call.
///
/// The input type is erased at the list level (Dart has no existential types),
/// so a heterogeneous `List<Tool<TDeps>>` is possible. The concrete input type
/// `I` is recovered inside the [tool] factory, which decodes the raw JSON before
/// invoking your typed callbacks.
final class Tool<TDeps> {
  Tool._({
    required this.name,
    required this.description,
    required this.inputJsonSchema,
    required FutureOr<Object?> Function(
      Map<String, Object?> input,
      ToolContext<TDeps> ctx,
    ) execute,
    FutureOr<bool> Function(
      Map<String, Object?> input,
      ToolContext<TDeps> ctx,
    )? needsApproval,
  })  : _execute = execute,
        _needsApproval = needsApproval;

  /// The tool's name.
  final String name;

  /// A model-facing description.
  final String description;

  /// The JSON Schema of the tool's input.
  final Map<String, Object?> inputJsonSchema;

  final FutureOr<Object?> Function(
    Map<String, Object?> input,
    ToolContext<TDeps> ctx,
  ) _execute;

  final FutureOr<bool> Function(
    Map<String, Object?> input,
    ToolContext<TDeps> ctx,
  )? _needsApproval;

  /// The spec advertised to the model.
  ToolSpec get spec => ToolSpec(
        name: name,
        description: description,
        inputJsonSchema: inputJsonSchema,
      );

  /// Whether this call needs human approval before executing.
  Future<bool> needsApprovalFor(
    Map<String, Object?> input,
    ToolContext<TDeps> ctx,
  ) async =>
      _needsApproval == null ? false : await _needsApproval(input, ctx);

  /// Execute the tool with raw (already model-supplied) [input].
  Future<Object?> execute(
    Map<String, Object?> input,
    ToolContext<TDeps> ctx,
  ) async =>
      await _execute(input, ctx);
}

/// Define a tool from a typed input [inputSchema] and an [execute] callback.
///
/// `I` is the input type (a record, a class, or a primitive); `TDeps` is the
/// agent's dependency type. The raw JSON the model supplies is decoded via
/// [inputSchema] before your callbacks run, so `execute` receives a typed `I`
/// and a typed [ToolContext].
///
/// ```dart
/// final getWeather = tool<({String city}), Deps>(
///   name: 'get_weather',
///   description: 'Current weather for a city.',
///   inputSchema: Schema.object(
///     {'city': Schema.string()},
///     required: ['city'],
///     fromJson: (j) => (city: j['city']! as String),
///   ),
///   execute: (input, ctx) => ctx.deps.weather.current(input.city),
/// );
/// ```
Tool<TDeps> tool<I, TDeps>({
  required String name,
  required String description,
  required Schema<I> inputSchema,
  required FutureOr<Object?> Function(I input, ToolContext<TDeps> ctx) execute,
  FutureOr<bool> Function(I input, ToolContext<TDeps> ctx)? needsApproval,
}) {
  return Tool<TDeps>._(
    name: name,
    description: description,
    inputJsonSchema: inputSchema.jsonSchema,
    execute: (raw, ctx) => execute(inputSchema.decode(raw), ctx),
    needsApproval: needsApproval == null
        ? null
        : (raw, ctx) => needsApproval(inputSchema.decode(raw), ctx),
  );
}
