@TestOn('vm')
library;

import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_openai/akashi_openai.dart';
import 'package:test/test.dart';

/// Live smoke tests against the real OpenAI API. Skipped unless `OPENAI_API_KEY`
/// is set.
void main() {
  final apiKey = Platform.environment['OPENAI_API_KEY'];
  final skip = apiKey == null ? 'set OPENAI_API_KEY to run live tests' : null;

  group('OpenAI live', () {
    late OpenAIProvider provider;
    setUp(() => provider = OpenAIProvider(apiKey: apiKey!));

    test('runs an agent and returns text', () async {
      final agent = ToolLoopAgent<Object?>(
        model: provider.languageModel('gpt-4o-mini'),
      );
      final result = await agent.run('Reply with the single word: pong');
      expect(result.text.toLowerCase(), contains('pong'));
    });

    test('embeds text into a vector', () async {
      final embedder = provider.embeddingModel('text-embedding-3-small')!;
      final vectors = await embedder.embed(['hello world']);
      expect(vectors.single, isNotEmpty);
    });
  }, skip: skip);
}
