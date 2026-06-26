import '../messages/message.dart';
import '../util/cancellation.dart';
import 'usage.dart';

/// A vendor (OpenAI, Anthropic, Google, ...) that mints [LanguageModel]s.
abstract interface class Provider {
  /// A short, stable provider id, e.g. `google`.
  String get id;

  /// Resolve a model by its provider-specific [modelId].
  LanguageModel languageModel(String modelId);
}

/// The single abstraction every provider adapter implements. Provider streaming
/// differences are normalized into the [ModelStreamPart] union.
abstract interface class LanguageModel {
  /// The owning provider's id.
  String get providerId;

  /// This model's id.
  String get modelId;

  /// A buffered, single-shot generation.
  Future<ModelResponse> generate(ModelRequest request);

  /// A streamed generation, emitting normalized [ModelStreamPart]s.
  Stream<ModelStreamPart> stream(ModelRequest request);
}

/// How a model can be made to emit structured (JSON) output, best to worst.
enum StructuredOutputMode {
  /// Native JSON-Schema-constrained decoding (most reliable).
  jsonSchema,

  /// Native JSON-object mode (valid JSON, but unconstrained by a schema).
  jsonObject,

  /// Force a single synthetic tool whose input schema is the target type.
  toolMode,

  /// Prompt the model to "return JSON" and validate/repair (universal fallback).
  promptOnly,
}

/// An optional capability mix-in a [LanguageModel] may also implement to declare
/// which [StructuredOutputMode]s it supports.
///
/// Kept separate from [LanguageModel] so adding it never breaks existing
/// implementers. `generateObject` checks `model is StructuredOutputCapable` and
/// falls back to [StructuredOutputMode.promptOnly] when it is absent.
abstract interface class StructuredOutputCapable {
  /// The structured-output strategies this model supports.
  Set<StructuredOutputMode> get structuredOutputModes;
}

/// How the model should treat the available tools.
enum ToolChoiceMode {
  /// Model decides whether to call tools.
  auto,

  /// Model must not call tools.
  none,

  /// Model must call some tool.
  any,

  /// Model must call a specific named tool.
  specific,
}

/// A tool-choice directive for a request.
final class ToolChoice {
  const ToolChoice._(this.mode, [this.toolName]);

  /// The model decides.
  static const ToolChoice auto = ToolChoice._(ToolChoiceMode.auto);

  /// No tool calls.
  static const ToolChoice none = ToolChoice._(ToolChoiceMode.none);

  /// Some tool must be called.
  static const ToolChoice any = ToolChoice._(ToolChoiceMode.any);

  /// A specific [name]d tool must be called.
  const ToolChoice.tool(String name) : this._(ToolChoiceMode.specific, name);

  /// The choice mode.
  final ToolChoiceMode mode;

  /// The required tool name when [mode] is [ToolChoiceMode.specific].
  final String? toolName;
}

/// How the model should shape its final output.
sealed class ResponseFormat {
  const ResponseFormat();

  /// Free-form text (the default).
  static const ResponseFormat text = TextResponseFormat();
}

/// Free-form text output.
final class TextResponseFormat extends ResponseFormat {
  /// Creates the text response format.
  const TextResponseFormat();
}

/// JSON output constrained by a [schema].
final class JsonResponseFormat extends ResponseFormat {
  /// Creates a JSON response format from a JSON Schema map.
  const JsonResponseFormat(this.schema, {this.schemaName});

  /// The JSON Schema to constrain output to.
  final Map<String, Object?> schema;

  /// An optional schema name some providers require.
  final String? schemaName;
}

/// A tool advertised to the model: name, description, and input JSON Schema.
final class ToolSpec {
  /// Creates a tool spec.
  const ToolSpec({
    required this.name,
    required this.description,
    required this.inputJsonSchema,
  });

  /// The tool's name.
  final String name;

  /// A model-facing description.
  final String description;

  /// The JSON Schema of the tool's input.
  final Map<String, Object?> inputJsonSchema;
}

/// A normalized request to a [LanguageModel].
final class ModelRequest {
  /// Creates a model request.
  ModelRequest({
    required this.messages,
    this.tools = const [],
    this.toolChoice = ToolChoice.auto,
    this.responseFormat = ResponseFormat.text,
    this.temperature,
    this.maxOutputTokens,
    CancellationToken? cancel,
  }) : cancel = cancel ?? CancellationToken();

  /// The conversation so far (a leading [SystemMessage] is the instructions).
  final List<Message> messages;

  /// Tools the model may call.
  final List<ToolSpec> tools;

  /// The tool-choice directive.
  final ToolChoice toolChoice;

  /// The desired output shape.
  final ResponseFormat responseFormat;

  /// Sampling temperature, if set.
  final double? temperature;

  /// Output token cap, if set.
  final int? maxOutputTokens;

  /// Cooperative cancellation signal.
  final CancellationToken cancel;
}

/// A buffered model response.
final class ModelResponse {
  /// Creates a model response.
  const ModelResponse({
    required this.message,
    required this.finishReason,
    required this.usage,
  });

  /// The assistant message produced.
  final AssistantMessage message;

  /// Why generation stopped.
  final FinishReason finishReason;

  /// Token usage for this call.
  final Usage usage;
}

/// A normalized streaming event from a provider. Every adapter maps its
/// vendor-specific stream onto this sealed union.
sealed class ModelStreamPart {
  const ModelStreamPart();
}

/// An incremental chunk of assistant text.
final class TextDeltaPart extends ModelStreamPart {
  /// Wraps a text [text] delta.
  const TextDeltaPart(this.text);

  /// The text fragment.
  final String text;
}

/// An incremental chunk of reasoning text.
final class ReasoningDeltaPart extends ModelStreamPart {
  /// Wraps a reasoning [text] delta, optionally carrying a provider
  /// [signature] (e.g. Anthropic thinking-block signatures) for round-tripping.
  const ReasoningDeltaPart(this.text, {this.signature});

  /// The reasoning fragment.
  final String text;

  /// An opaque provider signature for this reasoning block, if any.
  final String? signature;
}

/// The model opened a tool call (name known, arguments may still stream).
final class ToolCallStartPart extends ModelStreamPart {
  /// Creates a tool-call-start part.
  const ToolCallStartPart({required this.toolCallId, required this.toolName});

  /// The provider-assigned call id.
  final String toolCallId;

  /// The tool's name.
  final String toolName;
}

/// An incremental chunk of a tool call's JSON arguments.
final class ToolCallDeltaPart extends ModelStreamPart {
  /// Creates a tool-call-args delta.
  const ToolCallDeltaPart({required this.toolCallId, required this.argsDelta});

  /// The call id these args belong to.
  final String toolCallId;

  /// A fragment of the arguments JSON string.
  final String argsDelta;
}

/// A complete tool call delivered in one event (e.g. Gemini function calls).
final class ToolCallCompletePart extends ModelStreamPart {
  /// Creates a complete tool-call part.
  const ToolCallCompletePart({
    required this.toolCallId,
    required this.toolName,
    required this.input,
  });

  /// The provider-assigned call id.
  final String toolCallId;

  /// The tool's name.
  final String toolName;

  /// The fully-decoded arguments.
  final Map<String, Object?> input;
}

/// The model finished a turn.
final class FinishPart extends ModelStreamPart {
  /// Wraps the finish [reason].
  const FinishPart(this.reason);

  /// Why the turn ended.
  final FinishReason reason;
}

/// Token usage for the turn (may arrive at any point).
final class UsagePart extends ModelStreamPart {
  /// Wraps [usage].
  const UsagePart(this.usage);

  /// The reported usage.
  final Usage usage;
}
