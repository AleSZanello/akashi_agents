import 'package:fetch_client/fetch_client.dart';
import 'package:http/http.dart' as http;

/// On the web, the default `http.Client` does not stream response bodies, so
/// use `fetch_client`'s [FetchClient], which exposes the browser
/// `ReadableStream` — letting SSE stream in the browser like it does on the VM.
http.Client createHttpClient() => FetchClient(mode: RequestMode.cors);
