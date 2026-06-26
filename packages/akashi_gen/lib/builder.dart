import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'src/schema_generator.dart';

/// The `build_runner` entry point: generates a shared part with a `Schema<T>`
/// for each `@toolInput` class. Wired via `build.yaml`.
Builder schemaBuilder(BuilderOptions options) =>
    SharedPartBuilder([SchemaGenerator()], 'akashi_gen');
