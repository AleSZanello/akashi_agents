/// Marks a class as a tool-input DTO for which `akashi_gen` should generate a
/// matching `Schema<T>` (named `$<camelCaseClassName>Schema`).
///
/// The class is expected to have a constructor with named parameters matching
/// its fields (the generated `fromJson` calls it).
class ToolInput {
  /// Creates the annotation.
  const ToolInput();
}

/// The canonical [ToolInput] instance to annotate with: `@toolInput`.
const toolInput = ToolInput();

/// Per-field overrides for the generated schema.
class SchemaField {
  /// Creates a field annotation.
  const SchemaField({this.description, this.enumValues});

  /// A model-facing description of the field.
  final String? description;

  /// Restrict a string field to this set of values (a JSON-Schema `enum`).
  final List<String>? enumValues;
}
