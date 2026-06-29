# akashi_gen

**Optional `build_runner` codegen** for [Akashi](https://github.com/Alezanello/akashi_agents)
tool input schemas. Annotate a class with `@toolInput` and it emits a `Schema<T>`
identical to the one the runtime builder produces — so generated and
hand-written schemas are drop-in interchangeable. The `akashi` core never depends
on this package.

```dart
import 'package:akashi/akashi.dart';
import 'package:akashi_gen/akashi_gen.dart';

part 'weather_query.g.dart';

@toolInput
class WeatherQuery {
  WeatherQuery({required this.city, required this.units});

  final String city;

  @SchemaField(
    description: 'metric or imperial',
    enumValues: ['metric', 'imperial'],
  )
  final String units;
}

// `dart run build_runner build` generates `$weatherQuerySchema`, a plain
// `Schema<WeatherQuery>` — pass it to a tool's `inputSchema` or `generateObject`.
```

Supports `String` / `int` / `double` / `bool` / `List` fields, string `enum`s,
and `@SchemaField` descriptions; `required` is inferred from non-nullable fields.

See [`example/weather_query.dart`](example/weather_query.dart) (and the committed
`.g.dart`) for the full round-trip.

## Status

v0.3.

## License

MIT.
