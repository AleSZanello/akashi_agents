import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'annotations.dart';

const _schemaFieldChecker = TypeChecker.typeNamed(SchemaField);

/// Generates a `Schema<T>` (named `$<camelCaseClassName>Schema`) plus a
/// `_$<ClassName>FromJson` decoder for each `@toolInput`-annotated class.
class SchemaGenerator extends GeneratorForAnnotation<ToolInput> {
  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@toolInput can only annotate classes.',
        element: element,
      );
    }
    final className = element.name;
    if (className == null) {
      throw InvalidGenerationSourceError(
        '@toolInput class has no name.',
        element: element,
      );
    }

    final fields = element.fields
        .where((f) => !f.isStatic && !f.isSynthetic)
        .toList();

    final properties = StringBuffer();
    final required = <String>[];
    final ctorArgs = StringBuffer();
    for (final field in fields) {
      final name = field.name;
      if (name == null) continue;
      final type = field.type;
      final field_ = _readSchemaField(field);
      properties.writeln("    '$name': ${_schemaFor(type, field_, element)},");
      if (type.nullabilitySuffix != NullabilitySuffix.question) {
        required.add(name);
      }
      ctorArgs.writeln('    $name: ${_fromJsonExpr(name, type)},');
    }

    final getter = '\$${_lowerFirst(className)}Schema';
    final requiredList = required.map((r) => "'$r'").join(', ');
    return '''
Schema<$className> get $getter => Schema.object<$className>(
  {
${properties.toString().trimRight()}
  },
  required: [$requiredList],
  fromJson: _\$${className}FromJson,
);

$className _\$${className}FromJson(Map<String, Object?> json) => $className(
${ctorArgs.toString().trimRight()}
);
''';
  }
}

ConstantReader? _readSchemaField(FieldElement field) {
  final object = _schemaFieldChecker.firstAnnotationOf(field);
  return object == null ? null : ConstantReader(object);
}

String _schemaFor(DartType type, ConstantReader? field, Element owner) {
  final description = field?.peek('description')?.stringValue;
  final enumValues = field
      ?.peek('enumValues')
      ?.listValue
      .map((e) => ConstantReader(e).stringValue)
      .toList();
  final descriptionArg = description == null
      ? null
      : "description: '${_escape(description)}'";

  if (type.isDartCoreString) {
    final args = <String>[
      if (enumValues != null)
        'enumValues: [${enumValues.map((e) => "'${_escape(e)}'").join(', ')}]',
      if (descriptionArg != null) descriptionArg,
    ];
    return 'Schema.string(${args.join(', ')})';
  }
  if (type.isDartCoreInt) {
    return 'Schema.integer(${descriptionArg ?? ''})';
  }
  if (type.isDartCoreDouble) {
    return 'Schema.number(${descriptionArg ?? ''})';
  }
  if (type.isDartCoreBool) {
    return 'Schema.boolean(${descriptionArg ?? ''})';
  }
  if (type.isDartCoreList && type is InterfaceType) {
    return 'Schema.array(${_schemaFor(type.typeArguments.first, null, owner)})';
  }
  throw InvalidGenerationSourceError(
    'akashi_gen does not support the field type '
    '"${type.getDisplayString()}" (supported: String, int, double, bool, '
    'List of those).',
    element: owner,
  );
}

String _fromJsonExpr(String name, DartType type) {
  final nullable = type.nullabilitySuffix == NullabilitySuffix.question;
  final key = "json['$name']";
  if (type.isDartCoreString) {
    return nullable ? '$key as String?' : '$key! as String';
  }
  if (type.isDartCoreInt) {
    return nullable ? '($key as num?)?.toInt()' : '($key! as num).toInt()';
  }
  if (type.isDartCoreDouble) {
    return nullable
        ? '($key as num?)?.toDouble()'
        : '($key! as num).toDouble()';
  }
  if (type.isDartCoreBool) {
    return nullable ? '$key as bool?' : '$key! as bool';
  }
  if (type.isDartCoreList && type is InterfaceType) {
    final element = type.typeArguments.first.getDisplayString();
    return nullable
        ? '($key as List?)?.cast<$element>()'
        : '($key! as List).cast<$element>()';
  }
  return key;
}

String _lowerFirst(String s) =>
    s.isEmpty ? s : '${s[0].toLowerCase()}${s.substring(1)}';

String _escape(String s) => s.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
