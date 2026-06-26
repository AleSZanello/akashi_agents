# Changelog

## 0.2.0

Initial release — optional `build_runner` codegen for tool-input schemas.

- `@toolInput` / `@SchemaField` annotations.
- A `source_gen` builder that emits a `Schema<T>` (named
  `$<camelCaseClassName>Schema`) plus a `_$<ClassName>FromJson` decoder for each
  annotated class. The generated `Schema<T>` is drop-in interchangeable with the
  runtime `Schema` builder.
- Supports `String`/`int`/`double`/`bool`/`List` fields, string `enum`s and
  descriptions via `@SchemaField`; required is inferred from non-nullable fields.
- Strictly optional: `akashi` core never depends on this package. The example
  ships a committed `.g.dart`; regenerate with `dart run build_runner build`.
