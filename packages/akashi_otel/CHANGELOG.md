# Changelog

## 0.3.0

- Coordinated 0.3.0 release (tracks `akashi` 0.3.0). No functional changes.

## 0.2.0

Initial release — OpenTelemetry tracing over the `opentelemetry` package.

- `OtelTracer` implements Akashi's `Tracer`, exporting the
  `agent.run -> agent.step -> tool.<name>` span tree with step-index and
  tool-name attributes. Construct it from any OpenTelemetry tracer
  (`OtelTracer(provider.getTracer('akashi'))`).
- Spans nest via OpenTelemetry `Context`, so the run/step/tool hierarchy is
  preserved by any exporter.
- Offline test asserting the exported span tree shape against an in-memory
  exporter; a runnable `example/`.
