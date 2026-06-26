import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_client_factory.dart';
import 'sse_parser.dart';

export 'sse_parser.dart' show SseEvent, parseSseBytes, parseSseLines;

/// Raised when an SSE request returns a non-success status.
class SseTransportException implements Exception {
  /// Creates the exception from a [statusCode] and response [body].
  SseTransportException(this.statusCode, this.body);

  /// The HTTP status code.
  final int statusCode;

  /// The (truncated) response body.
  final String body;

  @override
  String toString() => 'SseTransportException($statusCode): $body';
}

/// Abstracts streaming HTTP so the same provider code streams on mobile,
/// server, and web behind a swappable backend. The agent loop itself never
/// touches HTTP — it talks to a `LanguageModel`.
abstract interface class SseTransport {
  /// Open a streaming connection, yielding parsed [SseEvent]s.
  Stream<SseEvent> connect({
    required Uri url,
    String method,
    Map<String, String> headers,
    Object? body,
  });

  /// Release any underlying resources.
  void close();
}

/// The default [SseTransport] over `package:http`. The streaming client is
/// chosen per platform via [createHttpClient] — a plain client on the VM and
/// mobile, a `fetch`-based client on the web — so the same code streams
/// everywhere. SSE bytes are decoded by the platform-agnostic [parseSseBytes].
final class HttpSseTransport implements SseTransport {
  /// Creates a transport. Without an explicit [client], the platform default
  /// from [createHttpClient] is used.
  HttpSseTransport({http.Client? client})
      : _client = client ?? createHttpClient();

  final http.Client _client;

  @override
  Stream<SseEvent> connect({
    required Uri url,
    String method = 'POST',
    Map<String, String> headers = const {},
    Object? body,
  }) async* {
    final request = http.Request(method, url)
      ..headers.addAll({'accept': 'text/event-stream', ...headers});
    if (body != null) {
      request.body = body is String ? body : jsonEncode(body);
    }

    final response = await _client.send(request);
    if (response.statusCode >= 400) {
      final errorBody = await response.stream.bytesToString();
      throw SseTransportException(response.statusCode, errorBody);
    }

    yield* parseSseBytes(response.stream);
  }

  @override
  void close() => _client.close();
}
