import 'package:akashi/akashi.dart';
import 'package:akashi_flutter/akashi_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final messages = <Message>[
    const UserMessage([TextPart('hello')]),
    const AssistantMessage([
      ReasoningPart('thinking'),
      ToolCallPart(toolCallId: 'c1', toolName: 'search', input: {'q': 'cats'}),
    ]),
    const ToolMessage([
      ToolResultPart(toolCallId: 'c1', toolName: 'search', output: 'found'),
      ToolResultPart(
        toolCallId: 'c2',
        toolName: 'broken',
        output: 'boom',
        isError: true,
      ),
    ]),
    AssistantMessage([
      ImagePart(mediaType: 'image/png', url: Uri.parse('https://x/y.png')),
      const FilePart(mediaType: 'application/pdf'),
    ]),
  ];

  testWidgets('renders every Part subtype', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: MessageListView(messages: messages))),
    );

    expect(find.text('hello'), findsOneWidget);
    expect(find.text('Reasoning'), findsOneWidget); // ExpansionTile title
    expect(find.widgetWithText(Chip, 'search({q: cats})'), findsOneWidget);
    expect(find.textContaining('search → found'), findsOneWidget);
    expect(find.textContaining('broken → boom'), findsOneWidget);
    expect(find.text('[image]'), findsOneWidget);
    expect(find.text('[file]'), findsOneWidget);
  });

  testWidgets('partBuilder overrides the default rendering', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageListView(
            messages: const [
              UserMessage([TextPart('x')]),
            ],
            partBuilder: (context, part) => const Text('custom'),
          ),
        ),
      ),
    );

    expect(find.text('custom'), findsOneWidget);
    expect(find.text('x'), findsNothing);
  });
}
