import 'dart:convert';

import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

void main() {
  group('parseSseLines', () {
    test('dispatches on blank lines and joins multi-line data', () async {
      final lines = Stream.fromIterable([
        'event: message',
        'data: hello',
        '',
        'data: {"a":1}',
        'data: more',
        '',
        ': a comment',
        'data: last',
        '',
      ]);

      final events = await parseSseLines(lines).toList();

      expect(events, hasLength(3));
      expect(events[0].event, 'message');
      expect(events[0].data, 'hello');
      expect(events[1].data, '{"a":1}\nmore');
      expect(events[1].event, isNull);
      expect(events[2].data, 'last');
    });
  });

  group('parseSseBytes', () {
    test('decodes a UTF-8 body into events', () async {
      final body = utf8.encode('data: token1\n\ndata: token2\n\n');

      final events = await parseSseBytes(Stream.value(body)).toList();

      expect(events.map((e) => e.data), ['token1', 'token2']);
    });
  });
}
