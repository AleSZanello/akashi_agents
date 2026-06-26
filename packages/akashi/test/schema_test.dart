import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

void main() {
  group('Schema', () {
    test('object schema advertises JSON Schema and round-trips', () {
      final schema = Schema.object<({String name, int age})>(
        {
          'name': Schema.string(description: 'full name'),
          'age': Schema.integer(),
        },
        required: ['name', 'age'],
        fromJson: (json) =>
            (name: json['name']! as String, age: json['age']! as int),
      );

      expect(schema.jsonSchema['type'], 'object');
      expect(schema.jsonSchema['required'], ['name', 'age']);

      final decoded = schema.decode({'name': 'Ada', 'age': 36});
      expect(decoded.name, 'Ada');
      expect(decoded.age, 36);
    });

    test('object schema reports missing required fields without throwing', () {
      final schema = Schema.object<Map<String, Object?>>(
        {'name': Schema.string()},
        required: ['name'],
        fromJson: (json) => json,
      );

      final result = schema.validate({});
      expect(result, isA<Invalid<Object?>>());
      expect((result as Invalid<Object?>).errors.single, contains('name'));

      expect(() => schema.decode({}), throwsA(isA<SchemaError>()));
    });

    test('integer accepts whole doubles (JSON has no int/double split)', () {
      expect(Schema.integer().decode(5.0), 5);
      expect(Schema.integer().validate(5.5), isA<Invalid<Object?>>());
    });

    test('array validates each item', () {
      final schema = Schema.array(Schema.string());
      expect(schema.decode(['a', 'b']), ['a', 'b']);
      expect(schema.validate(['a', 1]), isA<Invalid<Object?>>());
    });

    test('enum rejects out-of-set values', () {
      final schema = Schema.string(enumValues: ['metric', 'imperial']);
      expect(schema.decode('metric'), 'metric');
      expect(schema.validate('kelvin'), isA<Invalid<Object?>>());
    });
  });
}
