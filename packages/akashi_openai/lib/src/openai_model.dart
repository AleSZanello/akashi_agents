import 'dart:convert';

import 'package:akashi/akashi.dart';
import 'package:openai_dart/openai_dart.dart' as o;

/// A [LanguageModel] over an OpenAI chat model, normalizing OpenAI's streamed
/// content and index-keyed tool-call argument deltas into Akashi's
/// [ModelStreamPart] union.
final class OpenAIModel implements LanguageModel, StructuredOutputCapable {
  /// Creates an OpenAI model bound to a [client] and [modelId].
  OpenAIModel({required o.OpenAIClient client, required this.modelId})
    : _client = client;

  final o.OpenAIClient _client;

  @override
  final String modelId;

  @override
  String get providerId => 'openai';

  @override
  Set<StructuredOutputMode> get structuredOutputModes => const {
    StructuredOutputMode.jsonSchema,
    StructuredOutputMode.toolMode,
    StructuredOutputMode.promptOnly,
  };

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    // OpenAI streams tool-call argument fragments keyed by `index`; the `id`
    // and function name arrive on the first fragment only. Remember the id per
    // index so later argument deltas map back to it.
    final idByIndex = <int, String>{};
    o.Usage? usage;
    o.FinishReason? finish;

    await for (final event in _client.chat.completions.createStream(
      _toRequest(request),
    )) {
      if (event.usage != null) usage = event.usage;
      final choice = event.choices?.firstOrNull;
      if (choice == null) continue;
      if (choice.finishReason != null) finish = choice.finishReason;

      final delta = choice.delta;
      final content = delta.content;
      if (content != null && content.isNotEmpty) yield TextDeltaPart(content);
      final reasoning = delta.reasoning ?? delta.reasoningContent;
      if (reasoning != null && reasoning.isNotEmpty) {
        yield ReasoningDeltaPart(reasoning);
      }

      for (final call in delta.toolCalls ?? const <o.ToolCallDelta>[]) {
        final id = call.id;
        if (id != null) {
          idByIndex[call.index] = id;
          yield ToolCallStartPart(
            toolCallId: id,
            toolName: call.function?.name ?? '',
          );
        }
        final args = call.function?.arguments;
        if (args != null && args.isNotEmpty) {
          final resolved = idByIndex[call.index];
          if (resolved != null) {
            yield ToolCallDeltaPart(toolCallId: resolved, argsDelta: args);
          }
        }
      }
    }

    if (usage != null) yield UsagePart(_toUsage(usage));
    yield FinishPart(_toFinish(finish));
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async {
    final completion = await _client.chat.completions.create(
      _toRequest(request),
    );
    final choice = completion.choices.firstOrNull;
    final message = choice?.message;

    final parts = <Part>[];
    final calls = <ToolCallPart>[];
    if (message is o.AssistantMessage) {
      final reasoning = message.reasoning ?? message.reasoningContent;
      if (reasoning != null && reasoning.isNotEmpty) {
        parts.add(ReasoningPart(reasoning));
      }
      final content = message.content;
      if (content != null && content.isNotEmpty) parts.add(TextPart(content));
      for (final call in message.toolCalls ?? const <o.ToolCall>[]) {
        calls.add(
          ToolCallPart(
            toolCallId: call.id,
            toolName: call.function.name,
            input: _decodeArgs(call.function.arguments),
          ),
        );
      }
    }

    return ModelResponse(
      message: AssistantMessage([...parts, ...calls]),
      finishReason: _toFinish(choice?.finishReason),
      usage: _toUsage(completion.usage),
    );
  }

  o.ChatCompletionCreateRequest _toRequest(ModelRequest request) {
    final messages = <o.ChatMessage>[];
    for (final message in request.messages) {
      switch (message) {
        case SystemMessage(:final text):
          messages.add(o.SystemMessage(content: text));
        case UserMessage():
          messages.add(
            o.UserMessage(
              content: o.UserMessageContent.text(_textOf(message.content)),
            ),
          );
        case AssistantMessage():
          final toolCalls = [
            for (final call in message.toolCalls)
              o.ToolCall(
                id: call.toolCallId,
                type: 'function',
                function: o.FunctionCall(
                  name: call.toolName,
                  arguments: jsonEncode(call.input),
                ),
              ),
          ];
          messages.add(
            o.AssistantMessage(
              content: message.text.isEmpty ? null : message.text,
              toolCalls: toolCalls.isEmpty ? null : toolCalls,
            ),
          );
        case ToolMessage():
          for (final part in message.content) {
            if (part is ToolResultPart) {
              messages.add(
                o.ToolMessage(
                  toolCallId: part.toolCallId,
                  content: _stringify(part.output),
                ),
              );
            }
          }
      }
    }

    final tools = request.tools.isEmpty
        ? null
        : [
            for (final spec in request.tools)
              o.Tool.function(
                name: spec.name,
                description: spec.description,
                parameters: Map<String, dynamic>.from(spec.inputJsonSchema),
              ),
          ];

    final format = request.responseFormat;
    return o.ChatCompletionCreateRequest(
      model: modelId,
      messages: messages,
      tools: tools,
      toolChoice: _toToolChoice(request.toolChoice),
      responseFormat: format is JsonResponseFormat
          ? o.JsonSchemaResponseFormat(
              name: format.schemaName ?? 'output',
              schema: Map<String, dynamic>.from(format.schema),
            )
          : null,
      temperature: request.temperature,
      maxCompletionTokens: request.maxOutputTokens,
    );
  }
}

o.ToolChoice? _toToolChoice(ToolChoice choice) => switch (choice.mode) {
  ToolChoiceMode.auto => null,
  ToolChoiceMode.none => o.ToolChoice.none(),
  ToolChoiceMode.any => o.ToolChoice.required(),
  ToolChoiceMode.specific => o.ToolChoice.function(choice.toolName ?? ''),
};

String _textOf(List<Part> parts) =>
    parts.whereType<TextPart>().map((p) => p.text).join();

String _stringify(Object? output) =>
    output is String ? output : jsonEncode(output);

Map<String, Object?> _decodeArgs(String arguments) {
  if (arguments.trim().isEmpty) return {};
  try {
    final decoded = jsonDecode(arguments);
    return decoded is Map
        ? decoded.cast<String, Object?>()
        : {'value': decoded};
  } catch (_) {
    return {};
  }
}

Usage _toUsage(o.Usage? usage) => usage == null
    ? Usage.zero
    : Usage(
        inputTokens: usage.promptTokens,
        outputTokens: usage.completionTokens ?? 0,
      );

FinishReason _toFinish(o.FinishReason? reason) {
  if (reason == null) return FinishReason.stop;
  return reason.isTruncated ? FinishReason.length : FinishReason.stop;
}
