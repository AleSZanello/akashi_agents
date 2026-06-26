import '../schema/schema.dart';

/// Convenience [Schema]s for structured output.
///
/// `Output<T>` *is* a [Schema], so it drops straight into
/// `agent.generateObject(prompt, schema: Output.object(...))`. The named
/// constructors cover the shapes that would otherwise be verbose to spell out
/// with the raw [Schema] builder.
///
/// ```dart
/// final result = await agent.generateObject(
///   'Summarize the ticket.',
///   schema: Output.object<({String title, String severity})>(
///     {
///       'title': Schema.string(),
///       'severity': Output.choice(['low', 'medium', 'high']),
///     },
///     required: ['title', 'severity'],
///     fromJson: (j) => (
///       title: j['title']! as String,
///       severity: j['severity']! as String,
///     ),
///   ),
/// );
/// ```
final class Output<T> implements Schema<T> {
  const Output._(this._schema);

  /// Wraps an existing [schema] as an [Output] (drop-in, no behavior change).
  factory Output.of(Schema<T> schema) = Output<T>._;

  final Schema<T> _schema;

  /// An object output with named [properties], decoded via [fromJson].
  static Output<T> object<T>(
    Map<String, Schema<Object?>> properties, {
    required T Function(Map<String, Object?> json) fromJson,
    List<String> required = const [],
    String? description,
  }) =>
      Output<T>._(Schema.object<T>(
        properties,
        fromJson: fromJson,
        required: required,
        description: description,
      ));

  /// An array output whose elements conform to [items].
  static Output<List<E>> array<E>(Schema<E> items, {String? description}) =>
      Output<List<E>>._(Schema.array<E>(items, description: description));

  /// A single string chosen from [options] (a JSON-Schema `enum`).
  static Output<String> choice(List<String> options, {String? description}) =>
      Output<String>._(
          Schema.string(enumValues: options, description: description));

  @override
  Map<String, Object?> get jsonSchema => _schema.jsonSchema;

  @override
  T decode(Object? json) => _schema.decode(json);

  @override
  ValidationResult<T> validate(Object? json) => _schema.validate(json);
}
