import 'dart:convert';

import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

void main() {
  group('partsToText', () {
    test('concatenates text parts and drops non-text parts', () {
      final text = partsToText([
        TextPart('hello '),
        ReasoningPart('ignored'),
        TextPart('world'),
      ]);
      expect(text, 'hello world');
    });

    test('is empty when there is no text part', () {
      expect(partsToText([ReasoningPart('thinking')]), isEmpty);
    });
  });

  group('encodeToolOutput', () {
    test('returns a string output as-is', () {
      expect(encodeToolOutput('already text'), 'already text');
    });

    test('JSON-encodes a non-string output', () {
      expect(encodeToolOutput({'a': 1}), jsonEncode({'a': 1}));
    });
  });
}
