import 'dart:convert';

import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

import 'support/fake_language_model.dart';

void main() {
  group('agent.asTool', () {
    test('parent delegates to an isolated child agent', () async {
      // The child has its own tool 'echo' that the parent must never see.
      final childModel = FakeLanguageModel([
        [
          const TextDeltaPart('child answer'),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final child = ToolLoopAgent<Object?>(
        model: childModel,
        instructions: 'You are the child.',
        tools: [
          tool<({String x}), Object?>(
            name: 'echo',
            description: 'Echo the input.',
            inputSchema: Schema.object(
              {'x': Schema.string()},
              required: ['x'],
              fromJson: (json) => (x: json['x']! as String),
            ),
            execute: (input, ctx) async => input.x,
          ),
        ],
      );

      Object? capturedDeps;
      final researchTool = child.asTool<({String question}), String>(
        name: 'research',
        description: 'Investigate a question.',
        inputSchema: Schema.object(
          {'question': Schema.string()},
          required: ['question'],
          fromJson: (json) => (question: json['question']! as String),
        ),
        deps: (input, ctx) {
          capturedDeps = ctx.deps;
          return null;
        },
      );

      final parentModel = FakeLanguageModel([
        [
          const ToolCallCompletePart(
            toolCallId: 'c1',
            toolName: 'research',
            input: {'question': 'hi'},
          ),
          const FinishPart(FinishReason.stop),
        ],
        [
          const TextDeltaPart('parent done'),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final parent = ToolLoopAgent<String>(
        model: parentModel,
        tools: [researchTool],
      );

      final result = await parent.run('go', deps: 'parent-deps');

      // 1. The parent only ever advertised the subagent tool — child tools
      // (`echo`) are invisible to the parent model.
      expect(parentModel.requests.first.tools.map((t) => t.name), ['research']);

      // 2. The child ran fresh: its own system instructions, then exactly one
      // user message carrying the JSON-encoded input — no parent history.
      final childMessages = childModel.requests.first.messages;
      expect(childMessages.first, isA<SystemMessage>());
      final childUsers = childMessages.whereType<UserMessage>().toList();
      expect(childUsers, hasLength(1));
      expect(
        (childUsers.single.content.single as TextPart).text,
        jsonEncode({'question': 'hi'}),
      );

      // 3. The child's final text comes back as the parent's tool result.
      expect(result.steps.first.toolResults.single.output, 'child answer');
      expect(result.steps.first.toolResults.single.isError, isFalse);
      expect(result.text, 'parent done');

      // The deps mapper saw the parent's typed context.
      expect(capturedDeps, 'parent-deps');
    });

    test('uses a custom promptBuilder when provided', () async {
      final childModel = FakeLanguageModel([
        [const TextDeltaPart('ok'), const FinishPart(FinishReason.stop)],
      ]);
      final child = ToolLoopAgent<Object?>(model: childModel);
      final summarize = child.asTool<({String topic}), Object?>(
        name: 'summarize',
        description: 'Summarize a topic.',
        inputSchema: Schema.object(
          {'topic': Schema.string()},
          required: ['topic'],
          fromJson: (json) => (topic: json['topic']! as String),
        ),
        deps: (input, ctx) => null,
        promptBuilder: (input) => 'Summarize: ${input.topic}',
      );

      final parentModel = FakeLanguageModel([
        [
          const ToolCallCompletePart(
            toolCallId: 'c1',
            toolName: 'summarize',
            input: {'topic': 'whales'},
          ),
          const FinishPart(FinishReason.stop),
        ],
        [const TextDeltaPart('done'), const FinishPart(FinishReason.stop)],
      ]);
      final parent =
          ToolLoopAgent<Object?>(model: parentModel, tools: [summarize]);

      await parent.run('go');

      final childUser =
          childModel.requests.first.messages.whereType<UserMessage>().single;
      expect((childUser.content.single as TextPart).text, 'Summarize: whales');
    });
  });
}
