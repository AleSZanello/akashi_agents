import 'dart:convert';

import '../messages/message.dart';
import '../model/language_model.dart';
import '../model/usage.dart';
import '../observability/tracer.dart';
import '../schema/schema.dart';
import '../streaming/agent_event.dart';
import '../tool/tool.dart';
import '../util/cancellation.dart';
import 'agent.dart';
import 'approval.dart';
import 'checkpoint.dart';
import 'prepare_step.dart';
import 'results.dart';
import 'stop_condition.dart';

/// The default [Agent]: a streaming tool loop over a [LanguageModel].
///
/// `stream` is the primitive — it runs the loop and yields [AgentEvent]s. `run`
/// and `generateObject` collect over `stream`, so the streaming and buffered
/// paths can never diverge.
///
/// The loop, each step: call the model → re-emit deltas as events while
/// accumulating text and tool calls → if no tool calls, finish → otherwise
/// execute the tools (with approval and error feedback), append results, and
/// check the stop conditions.
final class ToolLoopAgent<TDeps> implements Agent<TDeps> {
  /// Creates a tool-loop agent.
  ///
  /// [stopWhen] defaults to stopping at [maxSteps]; [maxSteps] also acts as a
  /// hard ceiling regardless of custom stop conditions.
  ToolLoopAgent({
    required this.model,
    this.instructions,
    this.tools = const [],
    List<StopCondition>? stopWhen,
    this.prepareStep,
    this.approvalHandler,
    this.checkpoints,
    this.tracer = const NoopTracer(),
    this.maxSteps = 16,
    this.parallelToolCalls = true,
  }) : stopWhen = stopWhen ?? <StopCondition>[stepCountIs(maxSteps)];

  /// The language model that drives the loop.
  final LanguageModel model;

  /// System instructions, prepended as a [SystemMessage] when none is present.
  final String? instructions;

  /// The tools the model may call.
  final List<Tool<TDeps>> tools;

  /// Stop conditions, evaluated with OR semantics after each step.
  final List<StopCondition> stopWhen;

  /// Optional per-step context-engineering hook.
  final PrepareStep<TDeps>? prepareStep;

  /// Optional in-process human-in-the-loop approval handler.
  final ApprovalHandler<TDeps>? approvalHandler;

  /// Optional checkpoint store for durability.
  final CheckpointStore? checkpoints;

  /// Tracer for run/step/tool spans.
  final Tracer tracer;

  /// Absolute ceiling on steps (also the default stop condition).
  final int maxSteps;

  /// Whether a step's tool calls execute concurrently (the default).
  ///
  /// When true, a step's tools run via `Future.wait`; their `ToolResult` events
  /// are still emitted in call-index order once all have settled. Approvals are
  /// always resolved sequentially before any execution. Set false to execute
  /// tools one at a time, in order.
  final bool parallelToolCalls;

  @override
  Stream<AgentEvent> stream(
    Object prompt, {
    TDeps? deps,
    RunOptions? options,
  }) {
    final opts = options ?? const RunOptions();
    return _run(_normalize(prompt), startStep: 0, deps: deps, opts: opts);
  }

  /// Resume a checkpointed run from its persisted state.
  ///
  /// Loads the latest [AgentCheckpoint] for [checkpointId] from the configured
  /// [checkpoints] store and continues the loop from the next step, preserving
  /// the prior message history. Throws a [StateError] when no store is
  /// configured or no checkpoint exists for the id.
  ///
  /// This is in addition to the [Agent] interface (not part of it), so existing
  /// implementers are unaffected.
  Stream<AgentEvent> resume(
    String checkpointId, {
    TDeps? deps,
    RunOptions? options,
  }) async* {
    final store = checkpoints;
    if (store == null) {
      throw StateError(
          'resume requires a CheckpointStore, but none is configured.');
    }
    final checkpoint = await store.load(checkpointId);
    if (checkpoint == null) {
      throw StateError('No checkpoint found for run "$checkpointId".');
    }
    yield* _run(
      checkpoint.messages,
      startStep: checkpoint.step + 1,
      deps: deps,
      opts: options ?? const RunOptions(),
      checkpointId: checkpointId,
    );
  }

  /// The shared loop body. [initialHistory] is already normalized; [startStep]
  /// is 0 for a fresh run or `checkpoint.step + 1` on resume.
  Stream<AgentEvent> _run(
    List<Message> initialHistory, {
    required int startStep,
    required TDeps? deps,
    required RunOptions opts,
    String? checkpointId,
  }) async* {
    final cancel = opts.cancel ?? CancellationToken();
    final rootSpan = tracer.startSpan('agent.run');

    var history = initialHistory;
    final steps = <StepResult>[];
    var totalUsage = Usage.zero;
    var step = startStep;

    yield RunStart(step);

    while (true) {
      if (cancel.isCancelled) {
        yield RunFinish(step,
            finishReason: FinishReason.error, usage: totalUsage, text: '');
        rootSpan.end();
        return;
      }

      // 1. Context engineering hook (no-op unless configured).
      final cfg = prepareStep == null
          ? null
          : await prepareStep!(StepContext<TDeps>(
              step: step,
              messages: history,
              deps: deps as TDeps,
            ));
      final activeMessages = cfg?.messages ?? history;
      final activeModel = cfg?.model ?? model;
      final activeTools = _resolveTools(cfg?.activeTools);

      yield StepStart(step);
      final stepSpan = tracer.startSpan('agent.step',
          parent: rootSpan, attributes: {'step': step});

      // 2. Call the model, re-emitting deltas and accumulating the turn.
      final acc = _StepAccumulator();
      final request = ModelRequest(
        messages: activeMessages,
        tools: [for (final t in activeTools) t.spec],
        toolChoice: cfg?.toolChoice ?? ToolChoice.auto,
        responseFormat: opts.responseFormat ?? ResponseFormat.text,
        temperature: opts.temperature,
        maxOutputTokens: opts.maxOutputTokens,
        cancel: cancel,
      );

      await for (final part in activeModel.stream(request)) {
        switch (part) {
          case TextDeltaPart(:final text):
            acc.text.write(text);
            yield TextDelta(step, text);
          case ReasoningDeltaPart(:final text, :final signature):
            acc.reasoning.write(text);
            if (signature != null) acc.reasoningSignature = signature;
            yield ReasoningDelta(step, text);
          case ToolCallStartPart(:final toolCallId, :final toolName):
            acc.openCall(toolCallId, toolName);
            yield ToolCallStart(step,
                toolCallId: toolCallId, toolName: toolName);
          case ToolCallDeltaPart(:final toolCallId, :final argsDelta):
            acc.appendArgs(toolCallId, argsDelta);
            yield ToolCallArgsDelta(step,
                toolCallId: toolCallId, argsDelta: argsDelta);
          case ToolCallCompletePart(
              :final toolCallId,
              :final toolName,
              :final input
            ):
            acc.completeCall(toolCallId, toolName, input);
            yield ToolCallStart(step,
                toolCallId: toolCallId, toolName: toolName);
          case FinishPart(:final reason):
            acc.finishReason = reason;
          case UsagePart(:final usage):
            acc.usage += usage;
        }
      }

      totalUsage += acc.usage;
      history = [...history, acc.assistantMessage()];
      final calls = acc.toolCalls();

      // 3. No tool calls → terminal step.
      if (calls.isEmpty) {
        final result = StepResult(
          step: step,
          text: acc.text.toString(),
          toolCalls: const [],
          toolResults: const [],
          finishReason: acc.finishReason,
          usage: acc.usage,
        );
        steps.add(result);
        yield StepFinish(step, result);
        stepSpan.end();
        yield RunFinish(step,
            finishReason: acc.finishReason,
            usage: totalUsage,
            text: acc.text.toString());
        rootSpan.end();
        return;
      }

      // 4. Execute tool calls. Three phases so concurrent execution is possible
      // without yielding from inside Future.wait: (a) announce + resolve
      // unknown tools and approvals sequentially, (b) execute, (c) emit results
      // in call-index order.

      // 4a. Announce each call; resolve unknown tools and approvals in order
      // (interactive approvals must not race). Approved calls are queued.
      final preResolved = <int, ToolResultPart>{};
      final pending = <int, _PendingTool<TDeps>>{};
      for (var i = 0; i < calls.length; i++) {
        final call = calls[i];
        yield ToolCallReady(step, call);
        final toolCtx = ToolContext<TDeps>(
          deps: deps as TDeps,
          toolCallId: call.toolCallId,
          step: step,
          history: history,
          cancel: cancel,
          tracer: tracer,
        );

        final tool = _toolByName(call.toolName);
        if (tool == null) {
          preResolved[i] = ToolResultPart(
            toolCallId: call.toolCallId,
            toolName: call.toolName,
            output: 'Unknown tool: ${call.toolName}',
            isError: true,
          );
          continue;
        }

        if (await tool.needsApprovalFor(call.input, toolCtx)) {
          yield ApprovalRequest(step, call);
          final handler = approvalHandler;
          final decision = handler == null
              ? const ApprovalDecision.rejected(
                  'No approval handler configured')
              : await handler.decide(call, toolCtx);
          if (decision.rejected) {
            preResolved[i] = ToolResultPart(
              toolCallId: call.toolCallId,
              toolName: call.toolName,
              output: decision.reason ?? 'Rejected by approval handler',
              isError: true,
            );
            continue;
          }
        }

        pending[i] = _PendingTool<TDeps>(call: call, tool: tool, ctx: toolCtx);
      }

      // 4b. Execute approved tools — concurrently by default, each in its own
      // span. Errors are captured (fed back to the model), never thrown.
      final executed = <int, _ExecutedTool>{};
      Future<void> runOne(int index, _PendingTool<TDeps> p) async {
        final toolSpan = tracer.startSpan('tool.${p.call.toolName}',
            parent: stepSpan, attributes: {'tool': p.call.toolName});
        try {
          final output = await p.tool.execute(p.call.input, p.ctx);
          executed[index] = _ExecutedTool(ToolResultPart(
            toolCallId: p.call.toolCallId,
            toolName: p.call.toolName,
            output: output,
          ));
        } catch (e, st) {
          executed[index] = _ExecutedTool(
            ToolResultPart(
              toolCallId: p.call.toolCallId,
              toolName: p.call.toolName,
              output: e.toString(),
              isError: true,
            ),
            error: e,
            stackTrace: st,
          );
        } finally {
          toolSpan.end();
        }
      }

      if (parallelToolCalls) {
        await Future.wait([
          for (final entry in pending.entries) runOne(entry.key, entry.value)
        ]);
      } else {
        for (final entry in pending.entries) {
          await runOne(entry.key, entry.value);
        }
      }

      // 4c. Emit results (and any errors) in call-index order.
      final resultParts = <ToolResultPart>[];
      for (var i = 0; i < calls.length; i++) {
        final pre = preResolved[i];
        if (pre != null) {
          resultParts.add(pre);
          yield ToolResult(step, pre);
          continue;
        }
        final ex = executed[i]!;
        final error = ex.error;
        if (error != null) {
          yield ErrorEvent(step, error, ex.stackTrace!);
        }
        resultParts.add(ex.result);
        yield ToolResult(step, ex.result);
      }

      // 5. Append results, checkpoint (durability seam), record the step.
      history = [...history, ToolMessage(resultParts)];
      await checkpoints?.save(AgentCheckpoint(
        id: checkpointId ?? opts.checkpointId ?? 'run',
        step: step,
        messages: history,
      ));

      final result = StepResult(
        step: step,
        text: acc.text.toString(),
        toolCalls: calls,
        toolResults: resultParts,
        finishReason: acc.finishReason,
        usage: acc.usage,
      );
      steps.add(result);
      yield StepFinish(step, result);
      stepSpan.end();

      // 6. Stop conditions (OR) plus the hard ceiling.
      final stopCtx = StopContext(
        stepCount: step + 1,
        steps: List.unmodifiable(steps),
        lastStep: result,
      );
      var shouldStop = step + 1 >= maxSteps;
      if (!shouldStop) {
        for (final condition in stopWhen) {
          if (await condition(stopCtx)) {
            shouldStop = true;
            break;
          }
        }
      }
      if (shouldStop) {
        yield RunFinish(step,
            finishReason: FinishReason.stop,
            usage: totalUsage,
            text: acc.text.toString());
        rootSpan.end();
        return;
      }

      step++;
    }
  }

  @override
  Future<RunResult> run(
    Object prompt, {
    TDeps? deps,
    RunOptions? options,
  }) async {
    final initial = _normalize(prompt);
    final responseMessages = <Message>[];
    final steps = <StepResult>[];
    var text = '';
    var usage = Usage.zero;
    var reason = FinishReason.stop;

    await for (final event in stream(prompt, deps: deps, options: options)) {
      switch (event) {
        case StepFinish(:final result):
          steps.add(result);
          final parts = <Part>[
            if (result.text.isNotEmpty) TextPart(result.text),
            ...result.toolCalls,
          ];
          if (parts.isNotEmpty) responseMessages.add(AssistantMessage(parts));
          if (result.toolResults.isNotEmpty) {
            responseMessages.add(ToolMessage(result.toolResults));
          }
        case RunFinish(text: final t, usage: final u, finishReason: final r):
          text = t;
          usage = u;
          reason = r;
        default:
          break;
      }
    }

    return RunResult(
      text: text,
      messages: [...initial, ...responseMessages],
      responseMessages: responseMessages,
      steps: steps,
      usage: usage,
      finishReason: reason,
    );
  }

  @override
  Future<ObjectResult<T>> generateObject<T>(
    Object prompt, {
    required Schema<T> schema,
    TDeps? deps,
    RunOptions? options,
  }) async {
    final opts = options ?? const RunOptions();
    // Pick the most reliable strategy the model declares; the validate/repair
    // loop below is the universal safety net regardless of which is chosen.
    switch (_structuredOutputMode()) {
      case StructuredOutputMode.jsonSchema:
        return _generateViaRun(prompt,
            schema: schema, deps: deps, opts: opts, nativeSchema: true);
      case StructuredOutputMode.toolMode:
        return _generateViaToolMode(prompt,
            schema: schema, deps: deps, opts: opts);
      case StructuredOutputMode.jsonObject:
      case StructuredOutputMode.promptOnly:
        return _generateViaRun(prompt,
            schema: schema, deps: deps, opts: opts, nativeSchema: false);
    }
  }

  /// The best structured-output strategy this agent's [model] supports.
  StructuredOutputMode _structuredOutputMode() {
    final modes = model is StructuredOutputCapable
        ? (model as StructuredOutputCapable).structuredOutputModes
        : const {StructuredOutputMode.promptOnly};
    if (modes.contains(StructuredOutputMode.jsonSchema)) {
      return StructuredOutputMode.jsonSchema;
    }
    if (modes.contains(StructuredOutputMode.toolMode)) {
      return StructuredOutputMode.toolMode;
    }
    return StructuredOutputMode.promptOnly;
  }

  /// Structured output via the normal loop, extracting JSON from the final text.
  ///
  /// When [nativeSchema] is true the request carries a [JsonResponseFormat] and
  /// no prompt instruction is injected; otherwise it prompts for JSON. Both run
  /// inside the validate/repair loop.
  Future<ObjectResult<T>> _generateViaRun<T>(
    Object prompt, {
    required Schema<T> schema,
    required TDeps? deps,
    required RunOptions opts,
    required bool nativeSchema,
  }) async {
    final maxAttempts = opts.maxRepairAttempts + 1;
    final runOpts = nativeSchema
        ? RunOptions(
            cancel: opts.cancel,
            temperature: opts.temperature,
            maxOutputTokens: opts.maxOutputTokens,
            maxRepairAttempts: opts.maxRepairAttempts,
            checkpointId: opts.checkpointId,
            responseFormat:
                JsonResponseFormat(schema.jsonSchema, schemaName: T.toString()),
          )
        : opts;

    var messages = <Message>[
      ..._normalize(prompt),
      if (!nativeSchema)
        UserMessage.text(
          'Respond with ONLY a JSON value conforming to this JSON Schema. '
          'No markdown, no prose:\n${jsonEncode(schema.jsonSchema)}',
        ),
    ];
    RunResult? last;
    var lastErrors = const <String>[];

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final result = await run(messages, deps: deps, options: runOpts);
      last = result;
      final decoded = _tryDecodeJson(_extractJson(result.text));
      final validation = schema.validate(decoded);
      switch (validation) {
        case Valid(:final value):
          return ObjectResult(object: value, raw: result);
        case Invalid(:final errors):
          lastErrors = errors;
          messages = [
            ...messages,
            AssistantMessage([TextPart(result.text)]),
            UserMessage.text(
              'That did not validate: ${errors.join('; ')}. '
              'Return corrected JSON only.',
            ),
          ];
      }
    }

    throw SchemaError([
      'generateObject failed after $maxAttempts attempt(s)',
      ...lastErrors,
      if (last != null) 'last output: ${last.text}',
    ]);
  }

  /// Structured output by forcing a single synthetic `final_answer` tool whose
  /// input schema is the target type, then decoding the call's arguments.
  Future<ObjectResult<T>> _generateViaToolMode<T>(
    Object prompt, {
    required Schema<T> schema,
    required TDeps? deps,
    required RunOptions opts,
  }) async {
    const toolName = 'final_answer';
    final maxAttempts = opts.maxRepairAttempts + 1;
    final cancel = opts.cancel ?? CancellationToken();
    final toolSpec = ToolSpec(
      name: toolName,
      description:
          'Call this exactly once with the final answer as structured arguments.',
      inputJsonSchema: schema.jsonSchema,
    );

    var messages = _normalize(prompt);
    RunResult? last;
    var lastErrors = const <String>[];

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final response = await model.generate(ModelRequest(
        messages: messages,
        tools: [toolSpec],
        toolChoice: const ToolChoice.tool(toolName),
        temperature: opts.temperature,
        maxOutputTokens: opts.maxOutputTokens,
        cancel: cancel,
      ));
      final assistant = response.message;

      ToolCallPart? call;
      for (final c in assistant.toolCalls) {
        if (c.toolName == toolName) {
          call = c;
          break;
        }
      }
      final candidate = call != null
          ? call.input
          : _tryDecodeJson(_extractJson(assistant.text));

      final raw = RunResult(
        text: assistant.text,
        messages: [...messages, assistant],
        responseMessages: [assistant],
        steps: [
          StepResult(
            step: attempt,
            text: assistant.text,
            toolCalls: assistant.toolCalls,
            toolResults: const [],
            finishReason: response.finishReason,
            usage: response.usage,
          ),
        ],
        usage: response.usage,
        finishReason: response.finishReason,
      );
      last = raw;

      final validation = schema.validate(candidate);
      switch (validation) {
        case Valid(:final value):
          return ObjectResult(object: value, raw: raw);
        case Invalid(:final errors):
          lastErrors = errors;
          messages = [
            ...messages,
            assistant,
            UserMessage.text(
              'That did not validate: ${errors.join('; ')}. '
              'Call $toolName again with corrected arguments.',
            ),
          ];
      }
    }

    throw SchemaError([
      'generateObject failed after $maxAttempts attempt(s)',
      ...lastErrors,
      if (last != null) 'last output: ${last.text}',
    ]);
  }

  List<Message> _normalize(Object prompt) {
    final List<Message> base;
    switch (prompt) {
      case final String s:
        base = [UserMessage.text(s)];
      case final Message m:
        base = [m];
      case final Iterable<Message> it:
        base = it.toList();
      default:
        throw ArgumentError('Unsupported prompt type: ${prompt.runtimeType}');
    }
    final hasSystem = base.any((m) => m is SystemMessage);
    if (instructions != null && !hasSystem) {
      return [SystemMessage(instructions!), ...base];
    }
    return base;
  }

  List<Tool<TDeps>> _resolveTools(List<String>? activeNames) {
    if (activeNames == null) return tools;
    final allowed = activeNames.toSet();
    return [
      for (final t in tools)
        if (allowed.contains(t.name)) t
    ];
  }

  Tool<TDeps>? _toolByName(String name) {
    for (final t in tools) {
      if (t.name == name) return t;
    }
    return null;
  }

  static String _extractJson(String text) {
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', multiLine: true);
    final match = fence.firstMatch(text);
    return (match != null ? match.group(1) : text)?.trim() ?? '';
  }

  static Object? _tryDecodeJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }
}

/// Accumulates one model turn from its streamed parts.
class _StepAccumulator {
  final StringBuffer text = StringBuffer();
  final StringBuffer reasoning = StringBuffer();
  String? reasoningSignature;
  final List<String> _order = [];
  final Map<String, _PartialCall> _calls = {};
  FinishReason finishReason = FinishReason.stop;
  Usage usage = Usage.zero;

  void openCall(String id, String name) {
    final call = _calls.putIfAbsent(id, () {
      _order.add(id);
      return _PartialCall(name);
    });
    if (name.isNotEmpty) call.name = name;
  }

  void appendArgs(String id, String delta) {
    final call = _calls.putIfAbsent(id, () {
      _order.add(id);
      return _PartialCall('');
    });
    call.argsBuffer.write(delta);
  }

  void completeCall(String id, String name, Map<String, Object?> input) {
    final call = _calls.putIfAbsent(id, () {
      _order.add(id);
      return _PartialCall(name);
    });
    if (name.isNotEmpty) call.name = name;
    call.input = input;
  }

  List<ToolCallPart> toolCalls() => [
        for (final id in _order)
          ToolCallPart(
            toolCallId: id,
            toolName: _calls[id]!.name,
            input: _calls[id]!.resolveInput(),
          ),
      ];

  AssistantMessage assistantMessage() {
    final parts = <Part>[
      if (reasoning.isNotEmpty)
        ReasoningPart(reasoning.toString(), signature: reasoningSignature),
      if (text.isNotEmpty) TextPart(text.toString()),
      ...toolCalls(),
    ];
    return AssistantMessage(parts);
  }
}

class _PartialCall {
  _PartialCall(this.name);

  String name;
  final StringBuffer argsBuffer = StringBuffer();
  Map<String, Object?>? input;

  Map<String, Object?> resolveInput() {
    final fixed = input;
    if (fixed != null) return fixed;
    final raw = argsBuffer.toString().trim();
    if (raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? decoded.cast<String, Object?>()
        : {'value': decoded};
  }
}

/// An approved tool call awaiting execution.
class _PendingTool<TDeps> {
  _PendingTool({required this.call, required this.tool, required this.ctx});

  final ToolCallPart call;
  final Tool<TDeps> tool;
  final ToolContext<TDeps> ctx;
}

/// The outcome of executing one tool — its result plus any captured error.
class _ExecutedTool {
  _ExecutedTool(this.result, {this.error, this.stackTrace});

  final ToolResultPart result;
  final Object? error;
  final StackTrace? stackTrace;
}
