// An example `@toolInput` DTO. Run `dart run build_runner build` to (re)generate
// `weather_query.g.dart` with the `$weatherQuerySchema` getter.
import 'package:akashi/akashi.dart';
import 'package:akashi_gen/akashi_gen.dart';

part 'weather_query.g.dart';

@toolInput
class WeatherQuery {
  WeatherQuery({required this.city, required this.units, this.note});

  final String city;

  @SchemaField(
    description: 'metric or imperial',
    enumValues: ['metric', 'imperial'],
  )
  final String units;

  final String? note;
}

void main() {
  // The generated `$weatherQuerySchema` is a plain `Schema<WeatherQuery>` — pass
  // it anywhere a runtime-built schema would go (e.g. tool input or
  // generateObject).
  final schema = $weatherQuerySchema;
  print(schema.jsonSchema);
  final decoded = schema.decode({'city': 'Oslo', 'units': 'metric'});
  print('${decoded.city} / ${decoded.units}');
}
