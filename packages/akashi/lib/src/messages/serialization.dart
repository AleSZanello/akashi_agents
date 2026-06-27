/// JSON (de)serialization for the sealed [Message]/[Part] hierarchies.
///
/// These are free functions, not methods on the data types, so the message
/// model stays free of `dart:convert` and the wire format can evolve in one
/// place. The format is a discriminated union — each [Part] carries a `type`
/// and each [Message] a `role` — wrapped in a version-tagged envelope by
/// [messagesToJson]. This is the load-bearing surface durable checkpoint stores
/// (e.g. `akashi_drift`) persist.
///
/// Encoding is **total**: it never throws. A [ToolResultPart.output] that is not
/// JSON-encodable degrades to its string form, flagged with `_outputString`.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../agent/checkpoint.dart';
import 'message.dart';

/// The current wire-format version, written into the [messagesToJson] envelope.
const int messageWireVersion = 1;

/// Encode a single [Part] to a JSON map.
Map<String, Object?> partToJson(Part part) {
  switch (part) {
    case TextPart(:final text):
      return {'type': 'text', 'text': text};
    case ReasoningPart(:final text, :final signature):
      return {
        'type': 'reasoning',
        'text': text,
        if (signature != null) 'signature': signature,
      };
    case ImagePart(:final url, :final bytes, :final mediaType):
      return _mediaToJson('image', url, bytes, mediaType);
    case FilePart(:final url, :final bytes, :final mediaType):
      return _mediaToJson('file', url, bytes, mediaType);
    case ToolCallPart(:final toolCallId, :final toolName, :final input):
      return {
        'type': 'tool_call',
        'toolCallId': toolCallId,
        'toolName': toolName,
        'input': input,
      };
    case ToolResultPart():
      return _toolResultToJson(part);
  }
}

/// Decode a single [Part] from a JSON map. Throws [FormatException] on an
/// unrecognized `type`.
Part partFromJson(Map<String, Object?> json) {
  final type = json['type'];
  switch (type) {
    case 'text':
      return TextPart(json['text']! as String);
    case 'reasoning':
      return ReasoningPart(
        json['text']! as String,
        signature: json['signature'] as String?,
      );
    case 'image':
      return ImagePart(
        url: _urlFromJson(json['url']),
        bytes: _bytesFromJson(json['bytes']),
        mediaType: json['mediaType']! as String,
      );
    case 'file':
      return FilePart(
        url: _urlFromJson(json['url']),
        bytes: _bytesFromJson(json['bytes']),
        mediaType: json['mediaType']! as String,
      );
    case 'tool_call':
      return ToolCallPart(
        toolCallId: json['toolCallId']! as String,
        toolName: json['toolName']! as String,
        input: (json['input']! as Map).cast<String, Object?>(),
      );
    case 'tool_result':
      return ToolResultPart(
        toolCallId: json['toolCallId']! as String,
        toolName: json['toolName']! as String,
        output: json['output'],
        isError: json['isError'] as bool? ?? false,
      );
    default:
      throw FormatException('Unknown part type: $type');
  }
}

/// Encode a single [Message] to a JSON map.
Map<String, Object?> messageToJson(Message message) {
  switch (message) {
    case SystemMessage(:final text):
      return {'role': 'system', 'text': text};
    case UserMessage(:final content):
      return {'role': 'user', 'content': _partsToJson(content)};
    case AssistantMessage(:final content):
      return {'role': 'assistant', 'content': _partsToJson(content)};
    case ToolMessage(:final content):
      return {'role': 'tool', 'content': _partsToJson(content)};
  }
}

/// Decode a single [Message] from a JSON map. Throws [FormatException] on an
/// unrecognized `role`.
Message messageFromJson(Map<String, Object?> json) {
  final role = json['role'];
  switch (role) {
    case 'system':
      return SystemMessage(json['text']! as String);
    case 'user':
      return UserMessage(_partsFromJson(json['content']));
    case 'assistant':
      return AssistantMessage(_partsFromJson(json['content']));
    case 'tool':
      return ToolMessage(_partsFromJson(json['content']));
    default:
      throw FormatException('Unknown message role: $role');
  }
}

/// Encode a message list into a version-tagged envelope.
Map<String, Object?> messagesToJson(List<Message> messages) => {
      'v': messageWireVersion,
      'messages': [for (final message in messages) messageToJson(message)],
    };

/// Decode a message list from a [messagesToJson] envelope. Throws
/// [FormatException] when the envelope version is newer than this build
/// supports.
List<Message> messagesFromJson(Map<String, Object?> json) {
  checkWireVersion(json['v']);
  final raw = json['messages']! as List;
  return [
    for (final item in raw)
      messageFromJson((item as Map).cast<String, Object?>())
  ];
}

/// Validate a wire-format version tag. A missing tag is treated as version 1;
/// a version newer than [messageWireVersion] throws [FormatException].
void checkWireVersion(Object? tag) {
  final version = tag is int ? tag : messageWireVersion;
  if (version > messageWireVersion) {
    throw FormatException(
      'Unsupported wire version $version (this build supports up to '
      '$messageWireVersion).',
    );
  }
}

/// Encode an [AgentCheckpoint] to a version-tagged JSON map. The durable-HITL
/// fields ([AgentCheckpoint.pendingApproval], `resolvedResults`) are written
/// only when present, so plain snapshots stay compact.
Map<String, Object?> checkpointToJson(AgentCheckpoint checkpoint) => {
      'v': messageWireVersion,
      'id': checkpoint.id,
      'step': checkpoint.step,
      'status': checkpoint.status.name,
      'messages': [for (final m in checkpoint.messages) messageToJson(m)],
      if (checkpoint.pendingApproval != null)
        'pendingApproval': partToJson(checkpoint.pendingApproval!),
      if (checkpoint.resolvedResults.isNotEmpty)
        'resolvedResults': [
          for (final r in checkpoint.resolvedResults) partToJson(r)
        ],
    };

/// Decode an [AgentCheckpoint] from a [checkpointToJson] map.
AgentCheckpoint checkpointFromJson(Map<String, Object?> json) {
  checkWireVersion(json['v']);
  final pending = json['pendingApproval'];
  final resolved = json['resolvedResults'];
  return AgentCheckpoint(
    id: json['id']! as String,
    step: json['step']! as int,
    status: _statusFromName(json['status']),
    messages: [
      for (final item in (json['messages']! as List))
        messageFromJson((item as Map).cast<String, Object?>())
    ],
    pendingApproval: pending == null
        ? null
        : partFromJson((pending as Map).cast<String, Object?>())
            as ToolCallPart,
    resolvedResults: resolved == null
        ? const []
        : [
            for (final item in (resolved as List))
              partFromJson((item as Map).cast<String, Object?>())
                  as ToolResultPart
          ],
  );
}

CheckpointStatus _statusFromName(Object? name) {
  for (final status in CheckpointStatus.values) {
    if (status.name == name) return status;
  }
  return CheckpointStatus.running;
}

List<Map<String, Object?>> _partsToJson(List<Part> parts) =>
    [for (final part in parts) partToJson(part)];

List<Part> _partsFromJson(Object? raw) => [
      for (final item in (raw! as List))
        partFromJson((item as Map).cast<String, Object?>()),
    ];

Map<String, Object?> _mediaToJson(
  String type,
  Uri? url,
  Uint8List? bytes,
  String mediaType,
) =>
    {
      'type': type,
      if (url != null) 'url': url.toString(),
      if (bytes != null) 'bytes': base64Encode(bytes),
      'mediaType': mediaType,
    };

Map<String, Object?> _toolResultToJson(ToolResultPart part) {
  final json = <String, Object?>{
    'type': 'tool_result',
    'toolCallId': part.toolCallId,
    'toolName': part.toolName,
    'isError': part.isError,
  };
  final output = part.output;
  if (output == null || output is num || output is String || output is bool) {
    json['output'] = output;
  } else {
    // List/Map and everything else: normalize through JSON. Non-encodable
    // values degrade to their string form, flagged for auditability.
    try {
      json['output'] = jsonDecode(jsonEncode(output));
    } catch (_) {
      json['output'] = output.toString();
      json['_outputString'] = true;
    }
  }
  return json;
}

Uri? _urlFromJson(Object? raw) => raw == null ? null : Uri.parse(raw as String);

Uint8List? _bytesFromJson(Object? raw) =>
    raw == null ? null : base64Decode(raw as String);
