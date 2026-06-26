@TestOn('vm')
library;

import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_anthropic/akashi_anthropic.dart';
import 'package:test/test.dart';

/// Live smoke test against the real Anthropic API. Skipped unless
/// `ANTHROPIC_API_KEY` is set.
void main() {
  final apiKey = Platform.environment['ANTHROPIC_API_KEY'];
  final skip = apiKey == null
      ? 'set ANTHROPIC_API_KEY to run live tests'
      : null;

  group('Anthropic live', () {
    test('runs an agent and returns text', () async {
      final provider = AnthropicProvider(apiKey: apiKey!);
      final agent = ToolLoopAgent<Object?>(
        model: provider.languageModel('claude-haiku-4-5-20251001'),
      );
      final result = await agent.run('Reply with the single word: pong');
      expect(result.text.toLowerCase(), contains('pong'));
    });
  }, skip: skip);
}
