import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

import '../example/weather_query.dart';

void main() {
  group('generated \$weatherQuerySchema', () {
    test('jsonSchema equals the hand-written equivalent', () {
      final handWritten = Schema.object<WeatherQuery>(
        {
          'city': Schema.string(),
          'units': Schema.string(
            enumValues: ['metric', 'imperial'],
            description: 'metric or imperial',
          ),
          'note': Schema.string(),
        },
        required: ['city', 'units'],
        fromJson: (j) => WeatherQuery(
          city: j['city']! as String,
          units: j['units']! as String,
          note: j['note'] as String?,
        ),
      );

      expect($weatherQuerySchema.jsonSchema, handWritten.jsonSchema);
    });

    test('decodes JSON into the typed object', () {
      final query = $weatherQuerySchema.decode({
        'city': 'Oslo',
        'units': 'metric',
      });
      expect(query.city, 'Oslo');
      expect(query.units, 'metric');
      expect(query.note, isNull);
    });

    test('honors the generated enum constraint', () {
      final result = $weatherQuerySchema.validate({
        'city': 'Oslo',
        'units': 'kelvin',
      });
      expect(result, isA<Invalid<WeatherQuery>>());
    });
  });
}
