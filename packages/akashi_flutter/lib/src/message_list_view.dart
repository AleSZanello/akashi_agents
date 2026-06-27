import 'package:akashi/akashi.dart';
import 'package:flutter/material.dart';

/// Renders a list of [Message]s, exhaustively handling every [Part] subtype:
/// text, reasoning disclosures, tool-call chips, tool results, and media stubs.
///
/// A drop-in transcript view; supply your own [partBuilder] to customize a part.
class MessageListView extends StatelessWidget {
  /// Creates a message list over [messages].
  const MessageListView({
    super.key,
    required this.messages,
    this.padding,
    this.partBuilder,
  });

  /// The conversation to render.
  final List<Message> messages;

  /// Optional list padding.
  final EdgeInsetsGeometry? padding;

  /// Optional override for rendering a single [Part].
  final Widget Function(BuildContext context, Part part)? partBuilder;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: padding,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final part in message.content)
              partBuilder?.call(context, part) ?? _defaultPart(context, part),
          ],
        );
      },
    );
  }

  Widget _defaultPart(BuildContext context, Part part) {
    switch (part) {
      case TextPart(:final text):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(text),
        );
      case ReasoningPart(:final text):
        return ExpansionTile(
          title: const Text('Reasoning'),
          childrenPadding: const EdgeInsets.all(8),
          children: [Text(text)],
        );
      case ToolCallPart(:final toolName, :final input):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Chip(label: Text('$toolName($input)')),
        );
      case ToolResultPart(:final toolName, :final output, :final isError):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '$toolName → $output',
            style: TextStyle(
              color: isError ? Theme.of(context).colorScheme.error : null,
            ),
          ),
        );
      case ImagePart():
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('[image]'),
        );
      case FilePart():
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Text('[file]'),
        );
    }
  }
}
