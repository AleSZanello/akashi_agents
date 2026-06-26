@TestOn('vm')
library;

import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:akashi_google/akashi_google.dart';
import 'package:test/test.dart';

/// Live smoke tests against the real Gemini API. Skipped unless `GEMINI_API_KEY`
/// is set, so CI without a key stays green.
void main() {
  final apiKey = Platform.environment['GEMINI_API_KEY'];
  final skip =
      apiKey == null ? 'set GEMINI_API_KEY to run live Gemini tests' : null;

  group('Gemini live', () {
    late GoogleProvider provider;

    setUp(() => provider = GoogleProvider(apiKey: apiKey!));

    test('runs an agent and returns text', () async {
      final agent = ToolLoopAgent<Object?>(
        model: provider.languageModel('gemini-2.5-flash'),
      );
      final result = await agent.run('Reply with the single word: pong');
      expect(result.text.toLowerCase(), contains('pong'));
    });

    test('embeds text into a vector', () async {
      final embedder = provider.embeddingModel('text-embedding-004')!;
      final vectors = await embedder.embed(['hello world']);
      expect(vectors.single, isNotEmpty);
    });
  }, skip: skip);
}
