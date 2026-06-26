import 'package:akashi/akashi.dart';
import 'package:opentelemetry/api.dart' as ot;

/// A [Tracer] that exports Akashi's `agent.run -> agent.step -> tool.<name>`
/// span tree to OpenTelemetry.
///
/// Construct it from an OpenTelemetry tracer (typically obtained from a
/// `TracerProviderBase` in `package:opentelemetry/sdk.dart`):
///
/// ```dart
/// final provider = TracerProviderBase(processors: [BatchSpanProcessor(exporter)]);
/// final agent = ToolLoopAgent(
///   model: model,
///   tracer: OtelTracer(provider.getTracer('akashi')),
/// );
/// ```
final class OtelTracer implements Tracer {
  /// Creates an Akashi tracer that delegates to an OpenTelemetry [tracer].
  OtelTracer(ot.Tracer tracer) : _tracer = tracer;

  final ot.Tracer _tracer;

  @override
  Span startSpan(
    String name, {
    Span? parent,
    Map<String, Object?> attributes = const {},
  }) {
    final attrs = [
      for (final entry in attributes.entries)
        _toAttribute(entry.key, entry.value),
    ];
    final span = parent is _OtelSpan
        ? _tracer.startSpan(
            name,
            context: ot.contextWithSpan(ot.Context.root, parent._span),
            attributes: attrs,
          )
        : _tracer.startSpan(name, attributes: attrs);
    return _OtelSpan(span);
  }

  @override
  void event(String name, [Map<String, Object?> attributes = const {}]) {
    // Point-in-time events not tied to a span have no OTel home without an
    // active span context; the loop attaches events to spans instead.
  }
}

final class _OtelSpan implements Span {
  _OtelSpan(this._span);

  final ot.Span _span;

  @override
  void setAttribute(String key, Object? value) =>
      _span.setAttribute(_toAttribute(key, value));

  @override
  void addEvent(String name, [Map<String, Object?> attributes = const {}]) =>
      _span.addEvent(
        name,
        attributes: [
          for (final entry in attributes.entries)
            _toAttribute(entry.key, entry.value),
        ],
      );

  @override
  void end() => _span.end();
}

ot.Attribute _toAttribute(String key, Object? value) => switch (value) {
  final String v => ot.Attribute.fromString(key, v),
  final bool v => ot.Attribute.fromBoolean(key, v),
  final int v => ot.Attribute.fromInt(key, v),
  final double v => ot.Attribute.fromDouble(key, v),
  _ => ot.Attribute.fromString(key, '$value'),
};
