import 'package:akashi_showcase/src/demos/durable_demo.dart';
import 'package:akashi_showcase/src/demos/streaming_chat_demo.dart';
import 'package:akashi_showcase/src/demos/tool_calling_demo.dart';
import 'package:akashi_showcase/src/demos/workflow_demo.dart';
import 'package:akashi_showcase/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pump fixed-duration frames so streamed deltas land (pumpAndSettle would hang
/// on the perpetual typing-dots animation).
Future<void> advance(WidgetTester tester, [int ms = 5000]) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Widget host(Widget child) => MaterialApp(
      theme: buildAkashiTheme(),
      home: Scaffold(body: SizedBox(width: 900, height: 640, child: child)),
    );

void main() {
  testWidgets('streaming chat renders a streamed reply', (tester) async {
    await tester.pumpWidget(host(Builder(builder: streamingChatDemo.builder)));

    await tester.tap(find.text('What can Akashi do?'));
    await advance(tester);

    expect(find.textContaining('TextDelta'), findsOneWidget);
  });

  testWidgets('tool calling: call chip, result, then answer', (tester) async {
    await tester.pumpWidget(host(Builder(builder: toolCallingDemo.builder)));

    await tester.tap(find.text('Weather in Tokyo'));
    await advance(tester);

    // `get_weather` appears in both the call chip and the result row.
    expect(find.textContaining('get_weather'), findsWidgets);
    expect(find.textContaining('18°C'), findsWidgets); // tool result + answer
    expect(find.textContaining('partly cloudy'), findsWidgets);
  });

  testWidgets('durable: suspend, restart, resume to completion',
      (tester) async {
    await tester.pumpWidget(host(Builder(builder: durableDemo.builder)));

    // 1. Start the job → it suspends on the approval gate.
    await tester.tap(find.text('Start refund job'));
    await advance(tester);
    expect(find.text('SUSPENDED'), findsOneWidget);
    expect(find.text('Simulate process restart'), findsOneWidget);

    // 2. Restart into a fresh controller (the checkpoint survives).
    await tester.tap(find.text('Simulate process restart'));
    await tester.pump();
    expect(find.text('Approve & resume'), findsOneWidget);

    // 3. Approve → resume from the store → finish.
    await tester.tap(find.text('Approve & resume'));
    await advance(tester);
    expect(find.textContaining('Refund complete'), findsOneWidget);
  });

  testWidgets('workflow: fan-out + retry + synthesize completes',
      (tester) async {
    await tester.pumpWidget(host(Builder(builder: workflowDemo.builder)));

    await tester.tap(find.text('Run workflow'));
    await advance(tester, 8000); // research (with a retry) + synthesize

    // All 4 findings were gathered — which only holds if the flaky task's
    // retry succeeded — and the run is rerunnable.
    expect(find.textContaining('Synthesis of 4 findings'), findsOneWidget);
    expect(find.text('Run again'), findsOneWidget);
  });
}
