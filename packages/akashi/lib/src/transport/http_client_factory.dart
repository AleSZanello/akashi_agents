/// Returns the streaming-capable `http.Client` for the current platform: a
/// plain client on the VM/mobile, and a `fetch`-based client on the web (where
/// the default client cannot stream response bodies).
///
/// Selected via conditional import so the same agent code streams everywhere.
library;

export 'http_client_io.dart'
    if (dart.library.js_interop) 'http_client_web.dart';
