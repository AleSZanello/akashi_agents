import 'package:akashi/akashi.dart';
import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as a;

/// Default `max_tokens` when a request doesn't set one (Anthropic requires it).
const _defaultMaxTokens = 4096;

/// A [LanguageModel] over an Anthropic Claude model, normalizing Anthropic's
/// content blocks (text, thinking, tool_use) into Akashi's [ModelStreamPart]
/// union. Thinking-block signatures are surfaced on [ReasoningDeltaPart] for
/// inspection and persistence.
final class ClaudeModel implements LanguageModel, StructuredOutputCapable {
  /// Creates a Claude model bound to a [client] and [modelId].
  ClaudeModel({required a.AnthropicClient client, required this.modelId})
    : _client = client;

  final a.AnthropicClient _client;

  @override
  final String modelId;

  @override
  String get providerId => 'anthropic';

  @override
  Set<StructuredOutputMode> get structuredOutputModes => const {
    StructuredOutputMode.toolMode,
    StructuredOutputMode.promptOnly,
  };

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    // Anthropic streams content blocks; tool_use args arrive as input_json
    // deltas keyed by the block's index. Map index -> tool_use id.
    final idByIndex = <int, String>{};
    var inputTokens = 0;
    var outputTokens = 0;
    a.StopReason? stopReason;

    await for (final event in _client.messages.createStream(
      _toRequest(request),
    )) {
      // Cooperative cancellation: stop draining the upstream stream if the run
      // was cancelled (the agent loop also observes the same token).
      if (request.cancel.isCancelled) break;
      switch (event) {
        case a.MessageStartEvent(:final message):
          inputTokens = message.usage.inputTokens;
        case a.ContentBlockStartEvent(:final index, :final contentBlock):
          switch (contentBlock) {
            case a.ToolUseBlock(:final id, :final name):
              idByIndex[index] = id;
              yield ToolCallStartPart(toolCallId: id, toolName: name);
            case a.TextBlock(:final text):
              if (text.isNotEmpty) yield TextDeltaPart(text);
            case a.ThinkingBlock(:final thinking, :final signature):
              if (thinking.isNotEmpty) yield ReasoningDeltaPart(thinking);
              if (signature.isNotEmpty) {
                yield ReasoningDeltaPart('', signature: signature);
              }
            default:
              break;
          }
        case a.ContentBlockDeltaEvent(:final index, :final delta):
          switch (delta) {
            case a.TextDelta(:final text):
              yield TextDeltaPart(text);
            case a.ThinkingDelta(:final thinking):
              yield ReasoningDeltaPart(thinking);
            case a.SignatureDelta(:final signature):
              yield ReasoningDeltaPart('', signature: signature);
            case a.InputJsonDelta(:final partialJson):
              final id = idByIndex[index];
              if (id != null) {
                yield ToolCallDeltaPart(toolCallId: id, argsDelta: partialJson);
              }
            default:
              break;
          }
        case a.MessageDeltaEvent(:final delta, :final usage):
          outputTokens = usage.outputTokens;
          stopReason = delta.stopReason;
        default:
          break;
      }
    }

    yield UsagePart(
      Usage(inputTokens: inputTokens, outputTokens: outputTokens),
    );
    yield FinishPart(_toFinish(stopReason));
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async {
    final message = await _client.messages.create(_toRequest(request));

    final parts = <Part>[];
    final calls = <ToolCallPart>[];
    for (final block in message.content) {
      switch (block) {
        case a.TextBlock(:final text):
          parts.add(TextPart(text));
        case a.ThinkingBlock(:final thinking, :final signature):
          parts.add(
            ReasoningPart(
              thinking,
              signature: signature.isEmpty ? null : signature,
            ),
          );
        case a.ToolUseBlock(:final id, :final name, :final input):
          calls.add(
            ToolCallPart(
              toolCallId: id,
              toolName: name,
              input: input.cast<String, Object?>(),
            ),
          );
        default:
          break;
      }
    }

    return ModelResponse(
      message: AssistantMessage([...parts, ...calls]),
      finishReason: _toFinish(message.stopReason),
      usage: Usage(
        inputTokens: message.usage.inputTokens,
        outputTokens: message.usage.outputTokens,
      ),
    );
  }

  a.MessageCreateRequest _toRequest(ModelRequest request) {
    final systemTexts = <String>[];
    final messages = <a.InputMessage>[];

    for (final message in request.messages) {
      switch (message) {
        case SystemMessage(:final text):
          systemTexts.add(text);
        case UserMessage():
          messages.add(a.InputMessage.user(partsToText(message.content)));
        case AssistantMessage():
          // NOTE: a captured [ReasoningPart] (Anthropic "thinking") is not
          // replayed here. anthropic_sdk_dart 5 has no thinking *input* block,
          // and Akashi does not yet enable extended thinking on a request, so
          // there is no signed thinking block to round-trip. When a thinking
          // config is exposed, emit the thinking block (with its signature)
          // first, ahead of text and tool_use, in this branch.
          final blocks = <a.InputContentBlock>[];
          final text = message.text;
          if (text.isNotEmpty) blocks.add(a.InputContentBlock.text(text));
          for (final call in message.toolCalls) {
            blocks.add(
              a.InputContentBlock.toolUse(
                id: call.toolCallId,
                name: call.toolName,
                input: Map<String, dynamic>.from(call.input),
              ),
            );
          }
          messages.add(
            blocks.isEmpty
                ? a.InputMessage.assistant(text)
                : a.InputMessage.assistantBlocks(blocks),
          );
        case ToolMessage():
          final blocks = <a.InputContentBlock>[
            for (final part in message.content)
              if (part is ToolResultPart)
                a.InputContentBlock.toolResultText(
                  toolUseId: part.toolCallId,
                  text: encodeToolOutput(part.output),
                  isError: part.isError,
                ),
          ];
          messages.add(a.InputMessage.userBlocks(blocks));
      }
    }

    final tools = request.tools.isEmpty
        ? null
        : [
            for (final spec in request.tools)
              a.ToolDefinition.custom(
                a.Tool(
                  name: spec.name,
                  description: spec.description,
                  inputSchema: a.InputSchema.fromJson(
                    Map<String, dynamic>.from(spec.inputJsonSchema),
                  ),
                ),
              ),
          ];

    return a.MessageCreateRequest(
      model: modelId,
      messages: messages,
      maxTokens: request.maxOutputTokens ?? _defaultMaxTokens,
      system: systemTexts.isEmpty
          ? null
          : a.SystemPrompt.text(systemTexts.join('\n\n')),
      tools: tools,
      toolChoice: _toToolChoice(request.toolChoice),
      temperature: request.temperature,
    );
  }
}

a.ToolChoice? _toToolChoice(ToolChoice choice) => switch (choice.mode) {
  ToolChoiceMode.auto => null,
  ToolChoiceMode.none => a.ToolChoice.none(),
  ToolChoiceMode.any => a.ToolChoice.any(),
  ToolChoiceMode.specific => a.ToolChoice.tool(choice.toolName ?? ''),
};

FinishReason _toFinish(a.StopReason? reason) => switch (reason) {
  a.StopReason.maxTokens ||
  a.StopReason.modelContextWindowExceeded => FinishReason.length,
  a.StopReason.toolUse => FinishReason.toolCalls,
  a.StopReason.refusal => FinishReason.contentFilter,
  // endTurn, stopSequence, pauseTurn, compaction, and null are natural stops.
  _ => FinishReason.stop,
};
