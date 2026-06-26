@TestOn('vm')
library;

import 'dart:io';

import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

void main() {
  group('HttpSseTransport', () {
    test('streams SSE events from a server', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType =
            ContentType('text', 'event-stream');
        request.response.write('data: alpha\n\ndata: beta\n\n');
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final transport = HttpSseTransport();
      addTearDown(transport.close);

      final url =
          Uri.parse('http://${server.address.host}:${server.port}/stream');
      final events = await transport.connect(url: url, body: '{}').toList();

      expect(events.map((e) => e.data), ['alpha', 'beta']);
    });

    test('throws SseTransportException on an error status', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 500;
        request.response.write('boom');
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final transport = HttpSseTransport();
      addTearDown(transport.close);

      final url = Uri.parse('http://${server.address.host}:${server.port}/x');
      expect(
        transport.connect(url: url, body: '{}').toList(),
        throwsA(isA<SseTransportException>()),
      );
    });
  });
}
