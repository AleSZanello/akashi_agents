import 'dart:async';
import 'dart:convert';

/// One parsed Server-Sent Event.
final class SseEvent {
  /// Creates an SSE event.
  const SseEvent({this.event, required this.data});

  /// The `event:` field, if present.
  final String? event;

  /// The accumulated `data:` payload.
  final String data;
}

/// Parses a raw byte stream (an SSE HTTP response body) into [SseEvent]s.
/// Pure and platform-agnostic — works on the VM, mobile, and web.
Stream<SseEvent> parseSseBytes(Stream<List<int>> bytes) => parseSseLines(
    bytes.transform(utf8.decoder).transform(const LineSplitter()));

/// Parses already-split SSE [lines] into [SseEvent]s. Blank lines dispatch the
/// accumulated event; `:`-prefixed lines are comments.
Stream<SseEvent> parseSseLines(Stream<String> lines) async* {
  String? event;
  final data = StringBuffer();

  await for (final line in lines) {
    if (line.isEmpty) {
      if (data.isNotEmpty) {
        yield SseEvent(event: event, data: data.toString().trimRight());
        event = null;
        data.clear();
      }
      continue;
    }
    if (line.startsWith(':')) continue; // comment

    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    final value = colon == -1 ? '' : line.substring(colon + 1).trimLeft();
    switch (field) {
      case 'event':
        event = value;
      case 'data':
        data.writeln(value);
    }
  }

  if (data.isNotEmpty) {
    yield SseEvent(event: event, data: data.toString().trimRight());
  }
}
