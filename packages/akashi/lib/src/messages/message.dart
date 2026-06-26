import 'dart:typed_data';

/// A single piece of message content. Sealed for exhaustive `switch`.
sealed class Part {
  const Part();
}

/// Plain text.
final class TextPart extends Part {
  /// Wraps [text].
  const TextPart(this.text);

  /// The text.
  final String text;
}

/// Model "thinking" / reasoning content.
final class ReasoningPart extends Part {
  /// Wraps reasoning [text] with an optional provider [signature].
  const ReasoningPart(this.text, {this.signature});

  /// The reasoning text.
  final String text;

  /// An opaque provider signature, if any.
  final String? signature;
}

/// An image, by [url] or inline [bytes].
final class ImagePart extends Part {
  /// Creates an image part.
  const ImagePart({this.url, this.bytes, required this.mediaType});

  /// Remote image URL, if any.
  final Uri? url;

  /// Inline image bytes, if any.
  final Uint8List? bytes;

  /// The MIME type, e.g. `image/png`.
  final String mediaType;
}

/// A non-image file, by [url] or inline [bytes].
final class FilePart extends Part {
  /// Creates a file part.
  const FilePart({this.url, this.bytes, required this.mediaType});

  /// Remote file URL, if any.
  final Uri? url;

  /// Inline file bytes, if any.
  final Uint8List? bytes;

  /// The MIME type.
  final String mediaType;
}

/// A request from the model to invoke a tool.
final class ToolCallPart extends Part {
  /// Creates a tool call.
  const ToolCallPart({
    required this.toolCallId,
    required this.toolName,
    required this.input,
  });

  /// Provider-assigned id correlating the call with its result.
  final String toolCallId;

  /// The tool's name.
  final String toolName;

  /// The decoded JSON arguments.
  final Map<String, Object?> input;
}

/// The result of executing a tool, fed back to the model.
final class ToolResultPart extends Part {
  /// Creates a tool result.
  const ToolResultPart({
    required this.toolCallId,
    required this.toolName,
    required this.output,
    this.isError = false,
  });

  /// The id of the [ToolCallPart] this answers.
  final String toolCallId;

  /// The tool's name.
  final String toolName;

  /// The (JSON-encodable) output, or an error message when [isError].
  final Object? output;

  /// Whether [output] represents an error.
  final bool isError;
}

/// A message in a conversation. Sealed for exhaustive `switch`.
sealed class Message {
  const Message();

  /// The message's content parts.
  List<Part> get content;
}

/// A system / instruction message.
final class SystemMessage extends Message {
  /// Wraps system [text].
  const SystemMessage(this.text);

  /// The instruction text.
  final String text;

  @override
  List<Part> get content => [TextPart(text)];
}

/// A user message.
final class UserMessage extends Message {
  /// Creates a user message from arbitrary [content].
  const UserMessage(this.content);

  /// Creates a text-only user message.
  UserMessage.text(String text) : content = [TextPart(text)];

  @override
  final List<Part> content;
}

/// An assistant (model) message.
final class AssistantMessage extends Message {
  /// Creates an assistant message from [content].
  const AssistantMessage(this.content);

  @override
  final List<Part> content;

  /// The concatenated text of all [TextPart]s.
  String get text => content.whereType<TextPart>().map((p) => p.text).join();

  /// Any tool calls requested in this message.
  List<ToolCallPart> get toolCalls =>
      content.whereType<ToolCallPart>().toList();
}

/// A message carrying tool results back to the model.
final class ToolMessage extends Message {
  /// Creates a tool message from [content] (expected [ToolResultPart]s).
  const ToolMessage(this.content);

  @override
  final List<Part> content;
}
