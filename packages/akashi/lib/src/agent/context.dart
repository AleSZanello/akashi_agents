/// Context-engineering helpers that build a [StepConfig] for a [PrepareStep]
/// hook. They are pure (apart from [summarizeOlderThan]'s injected model), so
/// they compose freely and test offline.
///
/// ```dart
/// final agent = ToolLoopAgent(
///   model: model,
///   prepareStep: (ctx) => keepLastMessages(ctx, 10),
/// );
/// ```
library;

import '../messages/message.dart';
import '../model/language_model.dart';
import 'prepare_step.dart';

/// Keep only the last [n] non-system messages; leading [SystemMessage]s are
/// always preserved.
///
/// To avoid sending a [ToolMessage] whose originating assistant turn was
/// trimmed (which most providers reject), any leading tool results in the kept
/// window are dropped.
StepConfig keepLastMessages<TDeps>(StepContext<TDeps> ctx, int n) {
  final (system, rest) = _partitionSystem(ctx.messages);
  final tail = _trimLeadingToolResults(
    n >= rest.length ? rest : rest.sublist(rest.length - n),
  );
  return StepConfig(messages: [...system, ...tail]);
}

/// Summarize everything older than the last [keep] non-system messages via a
/// (cheap) [summarizer] model, then continue with `[system…, summary, recent…]`.
///
/// Returns an empty [StepConfig] (no override) when there is nothing old enough
/// to summarize.
Future<StepConfig> summarizeOlderThan<TDeps>(
  StepContext<TDeps> ctx, {
  required LanguageModel summarizer,
  int keep = 6,
}) async {
  final (system, rest) = _partitionSystem(ctx.messages);
  if (rest.length <= keep) return const StepConfig();

  final older = rest.sublist(0, rest.length - keep);
  final recent = _trimLeadingToolResults(rest.sublist(rest.length - keep));

  final response = await summarizer.generate(ModelRequest(messages: [
    const SystemMessage(
      'Summarize the conversation so far concisely, preserving facts, '
      'decisions, and any open tasks. Reply with the summary only.',
    ),
    UserMessage.text(_renderTranscript(older)),
  ]));

  return StepConfig(messages: [
    ...system,
    SystemMessage('Summary of earlier conversation:\n${response.message.text}'),
    ...recent,
  ]);
}

/// Swap to a [bigger] model once the conversation has accumulated at least
/// [afterErrors] tool errors; returns null (no override) before then.
StepConfig? escalateAfterErrors<TDeps>(
  StepContext<TDeps> ctx, {
  required LanguageModel bigger,
  int afterErrors = 2,
}) {
  var errors = 0;
  for (final message in ctx.messages) {
    if (message is ToolMessage) {
      for (final part in message.content) {
        if (part is ToolResultPart && part.isError) errors++;
      }
    }
  }
  return errors >= afterErrors ? StepConfig(model: bigger) : null;
}

(List<Message>, List<Message>) _partitionSystem(List<Message> messages) {
  final system = <Message>[];
  final rest = <Message>[];
  for (final message in messages) {
    (message is SystemMessage ? system : rest).add(message);
  }
  return (system, rest);
}

List<Message> _trimLeadingToolResults(List<Message> messages) {
  var start = 0;
  while (start < messages.length && messages[start] is ToolMessage) {
    start++;
  }
  return start == 0 ? messages : messages.sublist(start);
}

String _renderTranscript(List<Message> messages) {
  final buffer = StringBuffer();
  for (final message in messages) {
    final role = switch (message) {
      SystemMessage() => 'system',
      UserMessage() => 'user',
      AssistantMessage() => 'assistant',
      ToolMessage() => 'tool',
    };
    final body = message.content
        .map((part) => switch (part) {
              TextPart(:final text) => text,
              ReasoningPart(:final text) => text,
              ToolCallPart(:final toolName, :final input) =>
                '[call $toolName($input)]',
              ToolResultPart(:final toolName, :final output) =>
                '[result $toolName: $output]',
              ImagePart() => '[image]',
              FilePart() => '[file]',
            })
        .join(' ');
    buffer.writeln('$role: $body');
  }
  return buffer.toString();
}
