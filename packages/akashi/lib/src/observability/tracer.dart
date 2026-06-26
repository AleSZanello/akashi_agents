/// A minimal tracing contract. The core wires `run -> step -> tool` spans; a
/// real exporter (e.g. OpenTelemetry via `akashi_otel`) implements this.
abstract interface class Tracer {
  /// Start a span, optionally nested under [parent].
  Span startSpan(
    String name, {
    Span? parent,
    Map<String, Object?> attributes,
  });

  /// Record a point-in-time event not tied to a span.
  void event(String name, [Map<String, Object?> attributes]);
}

/// A unit of traced work.
abstract interface class Span {
  /// Attach a key/value attribute.
  void setAttribute(String key, Object? value);

  /// Record an event within this span.
  void addEvent(String name, [Map<String, Object?> attributes]);

  /// Mark the span as finished.
  void end();
}

/// A [Tracer] that does nothing. The default.
final class NoopTracer implements Tracer {
  /// Creates the no-op tracer.
  const NoopTracer();

  @override
  Span startSpan(
    String name, {
    Span? parent,
    Map<String, Object?> attributes = const {},
  }) =>
      const _NoopSpan();

  @override
  void event(String name, [Map<String, Object?> attributes = const {}]) {}
}

final class _NoopSpan implements Span {
  const _NoopSpan();

  @override
  void setAttribute(String key, Object? value) {}

  @override
  void addEvent(String name, [Map<String, Object?> attributes = const {}]) {}

  @override
  void end() {}
}

/// A [Tracer] that writes the `run -> step -> tool` span tree as indented lines
/// to a [sink] (defaults to `print`). Handy for local debugging without an
/// OpenTelemetry backend; pair with `akashi_otel`'s `OtelTracer` in production.
final class ConsoleTracer implements Tracer {
  /// Creates a console tracer. Lines go to [sink], or `print` when omitted.
  const ConsoleTracer({void Function(String line)? sink}) : _sink = sink;

  final void Function(String line)? _sink;

  void _write(String line) => (_sink ?? print)(line);

  @override
  Span startSpan(
    String name, {
    Span? parent,
    Map<String, Object?> attributes = const {},
  }) {
    final depth = parent is _ConsoleSpan ? parent.depth + 1 : 0;
    _write('${'  ' * depth}▶ $name${_formatAttributes(attributes)}');
    return _ConsoleSpan(name, depth, _write);
  }

  @override
  void event(String name, [Map<String, Object?> attributes = const {}]) {
    _write('• $name${_formatAttributes(attributes)}');
  }
}

final class _ConsoleSpan implements Span {
  _ConsoleSpan(this.name, this.depth, this._write);

  final String name;
  final int depth;
  final void Function(String line) _write;

  String get _indent => '  ' * depth;

  @override
  void setAttribute(String key, Object? value) {
    _write('$_indent  $key=$value');
  }

  @override
  void addEvent(String name, [Map<String, Object?> attributes = const {}]) {
    _write('$_indent  • $name${_formatAttributes(attributes)}');
  }

  @override
  void end() {
    _write('$_indent◀ $name');
  }
}

String _formatAttributes(Map<String, Object?> attributes) =>
    attributes.isEmpty ? '' : ' $attributes';
