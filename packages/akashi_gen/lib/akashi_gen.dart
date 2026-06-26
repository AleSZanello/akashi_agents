/// Optional `build_runner` code generation for Akashi tool-input schemas.
///
/// Annotate a DTO with `@toolInput` and run `dart run build_runner build` to get
/// a `Schema<T>` (named `$<camelCaseClassName>Schema`) that is drop-in
/// interchangeable with the runtime `Schema` builder.
library;

export 'src/annotations.dart';
