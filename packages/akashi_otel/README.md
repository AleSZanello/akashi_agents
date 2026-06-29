# akashi_otel

**OpenTelemetry** tracing for the [Akashi](https://github.com/AleSZanello/akashi_agents)
agent framework. Implements Akashi's `Tracer` over the
[`opentelemetry`](https://pub.dev/packages/opentelemetry) package, exporting the
`agent.run → agent.step → tool.<name>` span tree (with step-index and tool-name
attributes) to any OpenTelemetry exporter.

```dart
import 'package:akashi/akashi.dart';
import 'package:akashi_otel/akashi_otel.dart';
import 'package:opentelemetry/sdk.dart' as otel;

final provider = otel.TracerProviderBase(
  processors: [otel.SimpleSpanProcessor(myExporter)],
);

final agent = ToolLoopAgent(
  model: model,
  tools: tools,
  tracer: OtelTracer(provider.getTracer('akashi')),
);

await agent.run('...'); // spans nest via OpenTelemetry Context
```

Spans nest through OpenTelemetry `Context`, so the run/step/tool hierarchy is
preserved by any exporter (OTLP, Jaeger, Zipkin, ...).

See [`example/akashi_otel_example.dart`](example/akashi_otel_example.dart) for a
runnable offline example with an in-memory exporter.

## Status

v0.3.

## License

MIT.
