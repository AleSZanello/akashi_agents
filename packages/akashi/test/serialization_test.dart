import 'dart:typed_data';

import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

void main() {
  group('Part serialization', () {
    final parts = <Part>[
      const TextPart('hello'),
      const ReasoningPart('thinking', signature: 'sig-123'),
      const ReasoningPart('no signature'),
      ImagePart(
          bytes: Uint8List.fromList([1, 2, 3, 4]), mediaType: 'image/png'),
      ImagePart(url: Uri.parse('https://ex/y.png'), mediaType: 'image/png'),
      FilePart(
          bytes: Uint8List.fromList([9, 8, 7]), mediaType: 'application/pdf'),
      const ToolCallPart(
        toolCallId: 'c1',
        toolName: 'get',
        input: {
          'a': 1,
          'b': [true, null]
        },
      ),
      const ToolResultPart(
        toolCallId: 'c1',
        toolName: 'get',
        output: {'ok': true, 'n': 3},
      ),
      const ToolResultPart(
        toolCallId: 'c2',
        toolName: 'get',
        output: 'oops',
        isError: true,
      ),
    ];

    test('every Part subtype round-trips structurally', () {
      for (final part in parts) {
        final once = partToJson(part);
        final twice = partToJson(partFromJson(once));
        expect(twice, once, reason: '${part.runtimeType}');
      }
    });

    test('image bytes survive as base64', () {
      final part = ImagePart(
          bytes: Uint8List.fromList([10, 20, 30]), mediaType: 'image/png');
      final decoded = partFromJson(partToJson(part)) as ImagePart;
      expect(decoded.bytes, [10, 20, 30]);
      expect(decoded.url, isNull);
      expect(decoded.mediaType, 'image/png');
    });

    test('reasoning signature round-trips', () {
      final decoded = partFromJson(
        partToJson(const ReasoningPart('t', signature: 's')),
      ) as ReasoningPart;
      expect(decoded.signature, 's');
    });

    test('non-JSON tool output degrades to a flagged string', () {
      final part =
          ToolResultPart(toolCallId: 'c', toolName: 't', output: Object());
      final json = partToJson(part); // total: must not throw
      expect(json['_outputString'], isTrue);
      expect(json['output'], isA<String>());

      final decoded = partFromJson(json) as ToolResultPart;
      expect(decoded.output, json['output']);

      // The degraded value is now a plain string, so it re-encodes stably (the
      // one-time `_outputString` marker drops away on the second encode).
      final reencoded = partToJson(decoded);
      expect(partToJson(partFromJson(reencoded)), reencoded);
    });
  });

  group('Message serialization', () {
    test('every Message subtype round-trips structurally', () {
      final messages = <Message>[
        const SystemMessage('be nice'),
        UserMessage.text('hi'),
        const AssistantMessage([
          TextPart('answer'),
          ToolCallPart(toolCallId: 'c', toolName: 't', input: {}),
        ]),
        const ToolMessage([
          ToolResultPart(toolCallId: 'c', toolName: 't', output: 'r'),
        ]),
      ];
      for (final message in messages) {
        final once = messageToJson(message);
        expect(messageToJson(messageFromJson(once)), once,
            reason: '${message.runtimeType}');
      }
    });

    test('envelope round-trips and guards a future version', () {
      final messages = <Message>[
        const SystemMessage('s'),
        UserMessage.text('u'),
      ];
      final envelope = messagesToJson(messages);
      expect(envelope['v'], 1);
      expect(messagesToJson(messagesFromJson(envelope)), envelope);
      expect(
        () => messagesFromJson({'v': 999, 'messages': const []}),
        throwsFormatException,
      );
    });
  });

  group('Checkpoint serialization', () {
    test('round-trips a suspended checkpoint with pending approval', () {
      final checkpoint = AgentCheckpoint(
        id: 'job',
        step: 2,
        status: CheckpointStatus.suspended,
        messages: [
          const SystemMessage('sys'),
          UserMessage.text('hi'),
          const AssistantMessage([
            ToolCallPart(toolCallId: 'c1', toolName: 'danger', input: {'a': 1}),
          ]),
        ],
        pendingApproval: const ToolCallPart(
            toolCallId: 'c1', toolName: 'danger', input: {'a': 1}),
        resolvedResults: const [
          ToolResultPart(toolCallId: 'c0', toolName: 'safe', output: 'ok'),
        ],
      );
      final once = checkpointToJson(checkpoint);
      final back = checkpointFromJson(once);

      expect(checkpointToJson(back), once);
      expect(back.status, CheckpointStatus.suspended);
      expect(back.pendingApproval!.toolName, 'danger');
      expect(back.resolvedResults.single.output, 'ok');
      expect(back.messages, hasLength(3));
    });

    test('round-trips a plain running checkpoint', () {
      final checkpoint = AgentCheckpoint(
        id: 'r',
        step: 0,
        messages: [UserMessage.text('x')],
      );
      final once = checkpointToJson(checkpoint);
      expect(checkpointToJson(checkpointFromJson(once)), once);
      expect(checkpointFromJson(once).status, CheckpointStatus.running);
      expect(checkpointFromJson(once).pendingApproval, isNull);
    });
  });
}
