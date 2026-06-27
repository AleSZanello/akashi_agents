import 'package:akashi/akashi.dart';
import 'package:flutter_gemma/flutter_gemma.dart' as fg;

import 'gemma_backend.dart';

/// A [GemmaBackend] over flutter_gemma's [fg.InferenceChat].
///
/// The caller configures the chat (model, tools, multimodality) and hands it in;
/// this backend feeds new messages into it and normalizes its streamed
/// `ModelResponse`s onto [GemmaChunk]s. Because flutter_gemma's chat keeps its
/// own running history, only messages beyond those already submitted are added
/// on each turn.
class FlutterGemmaBackend implements GemmaBackend {
  /// Wraps a configured flutter_gemma [chat].
  FlutterGemmaBackend(this.chat);

  /// The underlying flutter_gemma chat session.
  final fg.InferenceChat chat;

  int _sent = 0;

  @override
  Stream<GemmaChunk> generate(
    List<Message> messages, {
    List<ToolSpec> tools = const [],
  }) async* {
    for (final message in messages.skip(_sent)) {
      await chat.addQueryChunk(_toGemmaMessage(message));
    }
    _sent = messages.length;

    await for (final response in chat.generateChatResponseAsync()) {
      switch (response) {
        case fg.TextResponse(:final token):
          yield GemmaTextChunk(token);
        case fg.ThinkingResponse(:final content):
          yield GemmaReasoningChunk(content);
        case fg.FunctionCallResponse(:final name, :final args):
          yield GemmaFunctionCallChunk(name, args.cast<String, Object?>());
        case fg.ParallelFunctionCallResponse(:final calls):
          for (final call in calls) {
            yield GemmaFunctionCallChunk(
              call.name,
              call.args.cast<String, Object?>(),
            );
          }
      }
    }
  }

  fg.Message _toGemmaMessage(Message message) {
    final text = message.content
        .map(
          (part) => switch (part) {
            TextPart(:final text) => text,
            ToolResultPart(:final output) => '$output',
            _ => '',
          },
        )
        .join();
    return fg.Message.text(text: text, isUser: message is UserMessage);
  }
}
