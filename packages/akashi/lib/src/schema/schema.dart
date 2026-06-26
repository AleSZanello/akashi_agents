/// The result of validating a JSON value against a [Schema].
sealed class ValidationResult<T> {
  const ValidationResult();
}

/// A successful validation carrying the decoded [value].
final class Valid<T> extends ValidationResult<T> {
  /// Wraps a decoded [value].
  const Valid(this.value);

  /// The decoded value.
  final T value;
}

/// A failed validation carrying human-readable [errors].
final class Invalid<T> extends ValidationResult<T> {
  /// Wraps the validation [errors].
  const Invalid(this.errors);

  /// One message per problem found.
  final List<String> errors;
}

/// Thrown by [Schema.decode] when a value does not conform.
class SchemaError implements Exception {
  /// Creates a schema error from a list of problems.
  SchemaError(this.errors);

  /// The validation problems.
  final List<String> errors;

  @override
  String toString() => 'SchemaError: ${errors.join('; ')}';
}

/// Couples a JSON-Schema description (sent to the model) with typed decoding.
///
/// The default path is the zero-codegen runtime builder ([Schema.string],
/// [Schema.object], ...). Optional `build_runner` codegen (`akashi_gen`) emits
/// the same `Schema<T>` type, so the two are drop-in interchangeable.
abstract interface class Schema<T> {
  /// The JSON Schema map advertised to the model.
  Map<String, Object?> get jsonSchema;

  /// Decode [json] to `T`, throwing [SchemaError] on a mismatch.
  T decode(Object? json);

  /// Validate [json] without throwing.
  ValidationResult<T> validate(Object? json);

  /// A string property.
  static Schema<String> string(
          {String? description, List<String>? enumValues}) =>
      _StringSchema(description: description, enumValues: enumValues);

  /// An integer property.
  static Schema<int> integer({String? description}) =>
      _IntSchema(description: description);

  /// A floating-point property.
  static Schema<double> number({String? description}) =>
      _NumberSchema(description: description);

  /// A boolean property.
  static Schema<bool> boolean({String? description}) =>
      _BoolSchema(description: description);

  /// An array of [items].
  static Schema<List<E>> array<E>(Schema<E> items, {String? description}) =>
      _ArraySchema<E>(items, description: description);

  /// An object with named [properties], decoded via [fromJson].
  static Schema<T> object<T>(
    Map<String, Schema<Object?>> properties, {
    required T Function(Map<String, Object?> json) fromJson,
    List<String> required = const [],
    String? description,
  }) =>
      _ObjectSchema<T>(
        properties,
        fromJson: fromJson,
        required: required,
        description: description,
      );

  /// An escape hatch: a hand-written JSON Schema [jsonSchema] plus a [decode]
  /// function.
  static Schema<T> raw<T>(
    Map<String, Object?> jsonSchema,
    T Function(Object? json) decode,
  ) =>
      _RawSchema<T>(jsonSchema, decode);
}

T _decodeVia<T>(Schema<T> schema, Object? json) {
  final result = schema.validate(json);
  return switch (result) {
    Valid(:final value) => value,
    Invalid(:final errors) => throw SchemaError(errors),
  };
}

final class _StringSchema implements Schema<String> {
  const _StringSchema({this.description, this.enumValues});

  final String? description;
  final List<String>? enumValues;

  @override
  Map<String, Object?> get jsonSchema => {
        'type': 'string',
        if (description != null) 'description': description,
        if (enumValues != null) 'enum': enumValues,
      };

  @override
  ValidationResult<String> validate(Object? json) {
    if (json is! String) {
      return Invalid(['expected string, got ${json.runtimeType}']);
    }
    final allowed = enumValues;
    if (allowed != null && !allowed.contains(json)) {
      return Invalid(['expected one of $allowed, got "$json"']);
    }
    return Valid(json);
  }

  @override
  String decode(Object? json) => _decodeVia(this, json);
}

final class _IntSchema implements Schema<int> {
  const _IntSchema({this.description});

  final String? description;

  @override
  Map<String, Object?> get jsonSchema => {
        'type': 'integer',
        if (description != null) 'description': description,
      };

  @override
  ValidationResult<int> validate(Object? json) {
    if (json is int) return Valid(json);
    if (json is double && json == json.truncateToDouble()) {
      return Valid(json.toInt());
    }
    return Invalid(['expected integer, got ${json.runtimeType}']);
  }

  @override
  int decode(Object? json) => _decodeVia(this, json);
}

final class _NumberSchema implements Schema<double> {
  const _NumberSchema({this.description});

  final String? description;

  @override
  Map<String, Object?> get jsonSchema => {
        'type': 'number',
        if (description != null) 'description': description,
      };

  @override
  ValidationResult<double> validate(Object? json) {
    if (json is num) return Valid(json.toDouble());
    return Invalid(['expected number, got ${json.runtimeType}']);
  }

  @override
  double decode(Object? json) => _decodeVia(this, json);
}

final class _BoolSchema implements Schema<bool> {
  const _BoolSchema({this.description});

  final String? description;

  @override
  Map<String, Object?> get jsonSchema => {
        'type': 'boolean',
        if (description != null) 'description': description,
      };

  @override
  ValidationResult<bool> validate(Object? json) => json is bool
      ? Valid(json)
      : Invalid(['expected boolean, got ${json.runtimeType}']);

  @override
  bool decode(Object? json) => _decodeVia(this, json);
}

final class _ArraySchema<E> implements Schema<List<E>> {
  const _ArraySchema(this.items, {this.description});

  final Schema<E> items;
  final String? description;

  @override
  Map<String, Object?> get jsonSchema => {
        'type': 'array',
        if (description != null) 'description': description,
        'items': items.jsonSchema,
      };

  @override
  ValidationResult<List<E>> validate(Object? json) {
    if (json is! List) {
      return Invalid(['expected array, got ${json.runtimeType}']);
    }
    final out = <E>[];
    final errors = <String>[];
    for (var i = 0; i < json.length; i++) {
      final result = items.validate(json[i]);
      switch (result) {
        case Valid(:final value):
          out.add(value);
        case Invalid(errors: final itemErrors):
          errors.addAll(itemErrors.map((e) => '[$i]: $e'));
      }
    }
    return errors.isEmpty ? Valid(out) : Invalid(errors);
  }

  @override
  List<E> decode(Object? json) => _decodeVia(this, json);
}

final class _ObjectSchema<T> implements Schema<T> {
  const _ObjectSchema(
    this.properties, {
    required this.fromJson,
    required this.required,
    this.description,
  });

  final Map<String, Schema<Object?>> properties;
  final T Function(Map<String, Object?>) fromJson;
  final List<String> required;
  final String? description;

  @override
  Map<String, Object?> get jsonSchema => {
        'type': 'object',
        if (description != null) 'description': description,
        'properties': {
          for (final entry in properties.entries)
            entry.key: entry.value.jsonSchema,
        },
        if (required.isNotEmpty) 'required': required,
      };

  @override
  ValidationResult<T> validate(Object? json) {
    if (json is! Map) {
      return Invalid(['expected object, got ${json.runtimeType}']);
    }
    final map = json.cast<String, Object?>();
    final errors = <String>[];
    for (final key in required) {
      if (!map.containsKey(key) || map[key] == null) {
        errors.add('missing required property: $key');
      }
    }
    for (final entry in properties.entries) {
      final key = entry.key;
      if (map.containsKey(key) && map[key] != null) {
        final result = entry.value.validate(map[key]);
        if (result is Invalid) {
          errors.addAll(result.errors.map((e) => '$key: $e'));
        }
      }
    }
    if (errors.isNotEmpty) return Invalid(errors);
    try {
      return Valid(fromJson(map));
    } catch (e) {
      return Invalid(['decode failed: $e']);
    }
  }

  @override
  T decode(Object? json) => _decodeVia(this, json);
}

final class _RawSchema<T> implements Schema<T> {
  const _RawSchema(this._jsonSchema, this._decode);

  final Map<String, Object?> _jsonSchema;
  final T Function(Object?) _decode;

  @override
  Map<String, Object?> get jsonSchema => _jsonSchema;

  @override
  ValidationResult<T> validate(Object? json) {
    try {
      return Valid(_decode(json));
    } catch (e) {
      return Invalid(['$e']);
    }
  }

  @override
  T decode(Object? json) => _decode(json);
}
