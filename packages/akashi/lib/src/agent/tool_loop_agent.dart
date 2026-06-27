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
import 'handoff.dart';
import 'prepare_step.dart';
import 'results.dart';
import 'stop_condition.dart';
import 'suspend.dart';

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
    this.name,
    this.tools = const [],
    this.handoffs = const [],
    List<StopCondition>? stopWhen,
    this.prepareStep,
    this.approvalHandler,
    this.checkpoints,
    this.tracer = const NoopTracer(),
    this.maxSteps = 16,
    this.parallelToolCalls = true,
    this.durableApproval = false,
  }) : stopWhen = stopWhen ?? <StopCondition>[stepCountIs(maxSteps)];

  /// The language model that drives the loop.
  final LanguageModel model;

  /// System instructions, prepended as a [SystemMessage] when none is present.
  final String? instructions;

  /// An optional name identifying this agent, surfaced as [HandoffEvent.from]
  /// when this agent transfers control. Defaults to `'agent'` when null.
  final String? name;

  /// The tools the model may call.
  final List<Tool<TDeps>> tools;

  /// Optional handoff targets this agent can transfer control to. Each is
  /// advertised to the model as a `transfer_to_<name>` tool. Empty by default,
  /// so a single-agent loop behaves exactly as before.
  final List<Handoff<TDeps>> handoffs;

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

  /// Use durable (suspend/resume) human-in-the-loop instead of the in-process
  /// [approvalHandler]. Active only when a [checkpoints] store is also
  /// configured. When on, a tool needing approval persists a suspended
  /// checkpoint and throws [Suspended]; resume out of band with
  /// [resume] passing an [ApprovalDecision]. Off by default — the in-process
  /// approval path is unchanged.
  final bool durableApproval;

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
  /// [checkpoints] store. Throws a [StateError] when no store is configured or
  /// no checkpoint exists for the id.
  ///
  /// With no [decision] this is a plain resume: the loop continues from the next
  /// step, preserving the prior message history (unchanged from v0.2). Pass a
  /// [decision] to resume a durable human-in-the-loop pause (a checkpoint with
  /// status [CheckpointStatus.suspended]): the loop re-enters the suspended step
  /// and applies the decision to the pending tool call — approved → execute,
  /// rejected → an error result fed back to the model.
  ///
  /// This is in addition to the [Agent] interface (not part of it), so existing
  /// implementers are unaffected.
  Stream<AgentEvent> resume(
    String checkpointId, {
    ApprovalDecision? decision,
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

    if (decision == null) {
      yield* _run(
        checkpoint.messages,
        startStep: checkpoint.step + 1,
        deps: deps,
        opts: options ?? const RunOptions(),
        checkpointId: checkpointId,
      );
      return;
    }

    final pending = checkpoint.pendingApproval;
    if (checkpoint.status != CheckpointStatus.suspended || pending == null) {
      throw StateError(
          'Checkpoint "$checkpointId" is not awaiting an approval decision.');
    }
    yield* _run(
      checkpoint.messages,
      startStep: checkpoint.step,
      deps: deps,
      opts: options ?? const RunOptions(),
      checkpointId: checkpointId,
      resume: _DurableResume<TDeps>(
        pendingCall: pending,
        resolved: checkpoint.resolvedResults,
        decision: decision,
      ),
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
    _DurableResume<TDeps>? resume,
  }) async* {
    final cancel = opts.cancel ?? CancellationToken();
    final rootSpan = tracer.startSpan('agent.run');

    var history = initialHistory;
    final steps = <StepResult>[];
    var totalUsage = Usage.zero;
    var step = startStep;

    // The mutable "active agent" config. A handoff reassigns these fields to the
    // target agent while [history] carries across; with no handoffs they stay
    // equal to the constructor values and the loop is unchanged.
    final active = _Active<TDeps>(
      name: name ?? 'agent',
      model: model,
      instructions: instructions,
      tools: tools,
      handoffs: handoffs,
    );

    yield RunStart(step);

    while (true) {
      if (cancel.isCancelled) {
        yield RunFinish(step,
            finishReason: FinishReason.error, usage: totalUsage, text: '');
        rootSpan.end();
        return;
      }

      // On a durable-approval resume, the suspended step's model turn already
      // ran — its assistant message is the last in the rehydrated history — so
      // we skip phases 1–3 and re-enter directly at tool execution.
      final reentry = resume != null && step == startStep;

      yield StepStart(step);
      final stepSpan = tracer.startSpan('agent.step',
          parent: rootSpan,
          attributes: {'step': step, if (reentry) 'resumed': true});

      final List<ToolCallPart> calls;
      final String stepText;
      final FinishReason stepFinishReason;
      final Usage stepUsage;

      if (reentry) {
        final assistant = history.last as AssistantMessage;
        calls = assistant.toolCalls;
        stepText = assistant.text;
        stepFinishReason = FinishReason.stop;
        stepUsage = Usage.zero; // the model was not re-called on resume
      } else {
        // 1. Context engineering hook (no-op unless configured).
        final cfg = prepareStep == null
            ? null
            : await prepareStep!(StepContext<TDeps>(
                step: step,
                messages: history,
                deps: deps as TDeps,
              ));
        final activeMessages = cfg?.messages ?? history;
        final activeModel = cfg?.model ?? active.model;
        final activeTools = _resolveTools(cfg?.activeTools, active.tools);

        // 2. Call the model, re-emitting deltas and accumulating the turn.
        final acc = _StepAccumulator();
        final request = ModelRequest(
          messages: activeMessages,
          tools: [
            for (final t in activeTools) t.spec,
            for (final h in active.handoffs) _transferSpec(h),
          ],
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
        final stepCalls = acc.toolCalls();

        // 3. No tool calls → terminal step.
        if (stepCalls.isEmpty) {
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

        calls = stepCalls;
        stepText = acc.text.toString();
        stepFinishReason = acc.finishReason;
        stepUsage = acc.usage;
      }

      // 4. Execute tool calls. Three phases so concurrent execution is possible
      // without yielding from inside Future.wait: (a) announce + resolve
      // unknown tools and approvals sequentially, (b) execute, (c) emit results
      // in call-index order.

      // Handoff targets advertised this step, keyed by their transfer-tool name.
      final transfers = {
        for (final h in active.handoffs) 'transfer_to_${h.name}': h,
      };
      Handoff<TDeps>? requestedHandoff;

      // Durable-approval resume state for this step (empty on a normal step).
      final resumedById = reentry
          ? {for (final r in resume.resolved) r.toolCallId: r}
          : const <String, ToolResultPart>{};
      final resumedCallId = reentry ? resume.pendingCall.toolCallId : null;
      final resumedDecision = reentry ? resume.decision : null;

      // 4a. Announce each call; resolve unknown tools and approvals in order
      // (interactive approvals must not race). Approved calls are queued.
      final preResolved = <int, ToolResultPart>{};
      final pending = <int, _PendingTool<TDeps>>{};
      // On resume, seed results already decided before the suspension so they
      // are neither re-announced nor re-run.
      for (var i = 0; i < calls.length; i++) {
        final prior = resumedById[calls[i].toolCallId];
        if (prior != null) preResolved[i] = prior;
      }
      for (var i = 0; i < calls.length; i++) {
        if (preResolved.containsKey(i)) continue;
        final call = calls[i];
        yield ToolCallReady(step, call);

        // A `transfer_to_<name>` call is structural, not a real tool: ack it so
        // history stays provider-valid, emit a HandoffEvent, and record the
        // requested transfer (applied after this step's results are appended).
        final transferTarget = transfers[call.toolName];
        if (transferTarget != null) {
          preResolved[i] = ToolResultPart(
            toolCallId: call.toolCallId,
            toolName: call.toolName,
            output: 'Transferred to ${transferTarget.name}.',
          );
          yield HandoffEvent(step, from: active.name, to: transferTarget.name);
          requestedHandoff = transferTarget;
          continue;
        }

        final toolCtx = ToolContext<TDeps>(
          deps: deps as TDeps,
          toolCallId: call.toolCallId,
          step: step,
          history: history,
          cancel: cancel,
          tracer: tracer,
        );

        final tool = _toolByName(call.toolName, active.tools);
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
          final durable = durableApproval && checkpoints != null;
          if (durable) {
            if (resumedCallId == call.toolCallId) {
              // Resuming exactly this call: apply the human decision.
              if (resumedDecision!.rejected) {
                preResolved[i] = ToolResultPart(
                  toolCallId: call.toolCallId,
                  toolName: call.toolName,
                  output:
                      resumedDecision.reason ?? 'Rejected by approval handler',
                  isError: true,
                );
                continue;
              }
              // Approved → fall through to queue the call for execution.
            } else {
              // Persist a suspended checkpoint and pause for out-of-band resume.
              yield ApprovalRequest(step, call);
              final cpId = checkpointId ?? opts.checkpointId ?? 'run';
              await checkpoints!.save(AgentCheckpoint(
                id: cpId,
                step: step,
                messages: history,
                pendingApproval: call,
                resolvedResults: [
                  for (var k = 0; k < calls.length; k++)
                    if (preResolved[k] != null) preResolved[k]!,
                ],
                status: CheckpointStatus.suspended,
              ));
              throw Suspended(checkpointId: cpId, pendingCall: call);
            }
          } else {
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

      // 5. Append results, apply any handoff, checkpoint, record the step.
      history = [...history, ToolMessage(resultParts)];

      // Apply a requested handoff: swap the active config to the target agent
      // and rewrite the leading instructions, keeping the accumulated history.
      if (requestedHandoff != null) {
        final prevInstructions = active.instructions;
        final target = requestedHandoff.agent;
        active
          ..name = requestedHandoff.name
          ..model = target.model
          ..instructions = target.instructions
          ..tools = target.tools
          ..handoffs = target.handoffs;
        history =
            _applyInstructions(history, prevInstructions, active.instructions);
      }

      await checkpoints?.save(AgentCheckpoint(
        id: checkpointId ?? opts.checkpointId ?? 'run',
        step: step,
        messages: history,
      ));

      final result = StepResult(
        step: step,
        text: stepText,
        toolCalls: calls,
        toolResults: resultParts,
        finishReason: stepFinishReason,
        usage: stepUsage,
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
            finishReason: FinishReason.stop, usage: totalUsage, text: stepText);
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

  /// Restrict [base] to the [activeNames] requested by a `prepareStep` hook.
  /// Transfer (`transfer_to_*`) tools are structural and never filtered here.
  List<Tool<TDeps>> _resolveTools(
    List<String>? activeNames,
    List<Tool<TDeps>> base,
  ) {
    if (activeNames == null) return base;
    final allowed = activeNames.toSet();
    return [
      for (final t in base)
        if (allowed.contains(t.name)) t
    ];
  }

  Tool<TDeps>? _toolByName(String name, List<Tool<TDeps>> base) {
    for (final t in base) {
      if (t.name == name) return t;
    }
    return null;
  }

  /// The synthetic tool advertised for a handoff target.
  ToolSpec _transferSpec(Handoff<TDeps> h) => ToolSpec(
        name: 'transfer_to_${h.name}',
        description:
            h.description ?? 'Transfer control to the ${h.name} agent.',
        inputJsonSchema: const {
          'type': 'object',
          'properties': <String, Object?>{},
        },
      );

  /// Rewrite the leading [SystemMessage] to a handoff target's [next]
  /// instructions. Replaces only when the head was the previous agent's injected
  /// instructions ([prev]); otherwise prepends so a caller-supplied system
  /// message is never clobbered.
  List<Message> _applyInstructions(
    List<Message> history,
    String? prev,
    String? next,
  ) {
    if (next == null) return history;
    final head = history.isNotEmpty ? history.first : null;
    if (prev != null && head is SystemMessage && head.text == prev) {
      return [SystemMessage(next), ...history.skip(1)];
    }
    return [SystemMessage(next), ...history];
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

/// Carries a durable-approval decision into a resumed step: the call awaiting a
/// decision, the results already settled before the pause, and the decision.
class _DurableResume<TDeps> {
  _DurableResume({
    required this.pendingCall,
    required this.resolved,
    required this.decision,
  });

  final ToolCallPart pendingCall;
  final List<ToolResultPart> resolved;
  final ApprovalDecision decision;
}

/// The mutable "active agent" config inside the loop. A handoff reassigns these
/// fields to the target agent's config; the message history is unaffected.
class _Active<TDeps> {
  _Active({
    required this.name,
    required this.model,
    required this.instructions,
    required this.tools,
    required this.handoffs,
  });

  String name;
  LanguageModel model;
  String? instructions;
  List<Tool<TDeps>> tools;
  List<Handoff<TDeps>> handoffs;
}
