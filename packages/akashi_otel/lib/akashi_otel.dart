/// OpenTelemetry tracing for the Akashi agent framework.
///
/// Wrap an OpenTelemetry tracer in [OtelTracer] and pass it to a
/// `ToolLoopAgent` to export its `run -> step -> tool` span tree.
library;

export 'src/otel_tracer.dart' show OtelTracer;
