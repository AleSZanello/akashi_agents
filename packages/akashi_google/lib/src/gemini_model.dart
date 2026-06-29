import 'package:akashi/akashi.dart';
import 'package:googleai_dart/googleai_dart.dart' as g;

/// A [LanguageModel] over a Gemini model, normalizing Gemini's content and
/// function calls into Akashi's [ModelStreamPart] union.
final class GeminiModel implements LanguageModel, StructuredOutputCapable {
  /// Creates a Gemini model bound to a [client] and [modelId].
  GeminiModel({required g.GoogleAIClient client, required this.modelId})
      : _client = client;

  final g.GoogleAIClient _client;

  @override
  final String modelId;

  @override
  String get providerId => 'google';

  @override
  Set<StructuredOutputMode> get structuredOutputModes => const {
        StructuredOutputMode.jsonSchema,
        StructuredOutputMode.toolMode,
        StructuredOutputMode.promptOnly,
      };

  @override
  Stream<ModelStreamPart> stream(ModelRequest request) async* {
    final geminiRequest = _toRequest(request);
    var callIndex = 0;
    g.UsageMetadata? lastUsage;
    g.FinishReason? lastFinish;

    final stream = _client.models.streamGenerateContent(
      model: modelId,
      request: geminiRequest,
    );

    await for (final chunk in stream) {
      // Cooperative cancellation: stop draining the upstream stream if the run
      // was cancelled (the agent loop also observes the same token).
      if (request.cancel.isCancelled) break;
      if (chunk.usageMetadata != null) lastUsage = chunk.usageMetadata;
      final candidates = chunk.candidates ?? const [];
      if (candidates.isEmpty) continue;
      final candidate = candidates.first;
      if (candidate.finishReason != null) lastFinish = candidate.finishReason;

      for (final part in candidate.content?.parts ?? const []) {
        switch (part) {
          case g.TextPart(:final text, :final thought):
            if (text.isEmpty) break;
            if (thought ?? false) {
              yield ReasoningDeltaPart(text);
            } else {
              yield TextDeltaPart(text);
            }
          case g.FunctionCallPart(:final functionCall):
            yield ToolCallCompletePart(
              toolCallId:
                  functionCall.id ?? '${functionCall.name}_${callIndex++}',
              toolName: functionCall.name,
              input: (functionCall.args ?? const {}).cast<String, Object?>(),
            );
          default:
            break;
        }
      }
    }

    if (lastUsage != null) yield UsagePart(_toUsage(lastUsage));
    yield FinishPart(_toFinish(lastFinish));
  }

  @override
  Future<ModelResponse> generate(ModelRequest request) async {
    final response = await _client.models.generateContent(
      model: modelId,
      request: _toRequest(request),
    );
    final candidates = response.candidates ?? const [];
    final candidate = candidates.isEmpty ? null : candidates.first;

    final parts = <Part>[];
    final calls = <ToolCallPart>[];
    var callIndex = 0;
    for (final part in candidate?.content?.parts ?? const []) {
      switch (part) {
        case g.TextPart(:final text, :final thought):
          if (text.isEmpty) break;
          parts.add((thought ?? false) ? ReasoningPart(text) : TextPart(text));
        case g.FunctionCallPart(:final functionCall):
          calls.add(ToolCallPart(
            toolCallId:
                functionCall.id ?? '${functionCall.name}_${callIndex++}',
            toolName: functionCall.name,
            input: (functionCall.args ?? const {}).cast<String, Object?>(),
          ));
        default:
          break;
      }
    }

    return ModelResponse(
      message: AssistantMessage([...parts, ...calls]),
      finishReason: _toFinish(candidate?.finishReason),
      usage: _toUsage(response.usageMetadata),
    );
  }

  g.GenerateContentRequest _toRequest(ModelRequest request) {
    final contents = <g.Content>[];
    final systemTexts = <String>[];

    for (final message in request.messages) {
      switch (message) {
        case SystemMessage(:final text):
          systemTexts.add(text);
        case UserMessage():
          contents.add(
              g.Content(role: 'user', parts: _toGeminiParts(message.content)));
        case AssistantMessage():
          contents.add(
              g.Content(role: 'model', parts: _toGeminiParts(message.content)));
        case ToolMessage():
          // Gemini carries function responses in a user-role turn.
          contents.add(
              g.Content(role: 'user', parts: _toGeminiParts(message.content)));
      }
    }

    final tools = request.tools.isEmpty
        ? null
        : <g.Tool>[
            g.Tool(
              functionDeclarations: [
                for (final spec in request.tools)
                  g.FunctionDeclaration(
                    name: spec.name,
                    description: spec.description,
                    parameters: _toGeminiSchema(spec.inputJsonSchema),
                  ),
              ],
            ),
          ];

    final format = request.responseFormat;
    final jsonFormat = format is JsonResponseFormat ? format : null;
    final needsConfig = request.temperature != null ||
        request.maxOutputTokens != null ||
        jsonFormat != null;
    final generationConfig = needsConfig
        ? g.GenerationConfig(
            temperature: request.temperature,
            maxOutputTokens: request.maxOutputTokens,
            responseMimeType: jsonFormat == null ? null : 'application/json',
            responseSchema: jsonFormat == null
                ? null
                : Map<String, dynamic>.from(jsonFormat.schema),
          )
        : null;

    return g.GenerateContentRequest(
      contents: contents,
      tools: tools,
      toolConfig: _toToolConfig(request.toolChoice),
      systemInstruction: systemTexts.isEmpty
          ? null
          : g.Content(parts: [g.TextPart(systemTexts.join('\n\n'))]),
      generationConfig: generationConfig,
    );
  }

  List<g.Part> _toGeminiParts(List<Part> parts) {
    final out = <g.Part>[];
    for (final part in parts) {
      switch (part) {
        case TextPart(:final text):
          out.add(g.TextPart(text));
        case ReasoningPart(:final text):
          out.add(g.TextPart(text));
        case ToolCallPart(:final toolName, :final input):
          out.add(g.Part.functionCall(toolName, args: input));
        case ToolResultPart(:final toolName, :final output):
          out.add(g.Part.functionResponse(toolName, _asResponseMap(output)));
        case ImagePart():
        case FilePart():
          break; // multi-modal input is not wired in v0.1
      }
    }
    return out;
  }
}

/// Maps Akashi's [ToolChoice] onto Gemini's `toolConfig.functionCallingConfig`.
/// Returns null for [ToolChoiceMode.auto] (Gemini's default).
g.ToolConfig? _toToolConfig(ToolChoice choice) {
  switch (choice.mode) {
    case ToolChoiceMode.auto:
      return null;
    case ToolChoiceMode.none:
      return const g.ToolConfig(
        functionCallingConfig:
            g.FunctionCallingConfig(mode: g.FunctionCallingMode.none),
      );
    case ToolChoiceMode.any:
      return const g.ToolConfig(
        functionCallingConfig:
            g.FunctionCallingConfig(mode: g.FunctionCallingMode.any),
      );
    case ToolChoiceMode.specific:
      final name = choice.toolName;
      return g.ToolConfig(
        functionCallingConfig: g.FunctionCallingConfig(
          mode: g.FunctionCallingMode.any,
          allowedFunctionNames: name == null ? null : [name],
        ),
      );
  }
}

g.Schema _toGeminiSchema(Map<String, Object?> json) {
  final type = switch ((json['type'] as String?)?.toLowerCase()) {
    'string' => g.SchemaType.string,
    'number' => g.SchemaType.number,
    'integer' => g.SchemaType.integer,
    'boolean' => g.SchemaType.boolean,
    'array' => g.SchemaType.array,
    'object' => g.SchemaType.object,
    _ => null,
  };
  final properties = json['properties'] as Map<String, Object?>?;
  final items = json['items'] as Map<String, Object?>?;
  final enumValues = json['enum'] as List<Object?>?;
  final required = json['required'] as List<Object?>?;

  return g.Schema(
    type: type,
    description: json['description'] as String?,
    enumValues: enumValues?.map((e) => '$e').toList(),
    items: items == null ? null : _toGeminiSchema(items),
    properties: properties == null
        ? null
        : {
            for (final entry in properties.entries)
              entry.key: _toGeminiSchema(entry.value as Map<String, Object?>),
          },
    required: required?.map((e) => '$e').toList(),
  );
}

Map<String, dynamic> _asResponseMap(Object? output) {
  if (output is Map) return output.cast<String, dynamic>();
  return {'result': output};
}

Usage _toUsage(g.UsageMetadata? usage) => usage == null
    ? Usage.zero
    : Usage(
        inputTokens: usage.promptTokenCount ?? 0,
        outputTokens: usage.candidatesTokenCount ?? 0,
      );

FinishReason _toFinish(g.FinishReason? reason) => switch (reason) {
      g.FinishReason.maxTokens => FinishReason.length,
      g.FinishReason.safety ||
      g.FinishReason.recitation ||
      g.FinishReason.blocklist ||
      g.FinishReason.prohibitedContent ||
      g.FinishReason.spii ||
      g.FinishReason.imageSafety ||
      g.FinishReason.imageProhibitedContent ||
      g.FinishReason.imageRecitation =>
        FinishReason.contentFilter,
      g.FinishReason.stop ||
      g.FinishReason.unspecified ||
      null =>
        FinishReason.stop,
      _ => FinishReason.other,
    };
