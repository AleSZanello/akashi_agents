import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

import 'support/fake_language_model.dart';

typedef Person = ({String name, int age});

final Schema<Person> personSchema = Schema.object<Person>(
  {
    'name': Schema.string(),
    'age': Schema.integer(),
  },
  required: ['name', 'age'],
  fromJson: (j) => (
    name: j['name']! as String,
    age: (j['age']! as num).toInt(),
  ),
);

String _userText(ModelRequest request) => request.messages
    .whereType<UserMessage>()
    .expand((m) => m.content.whereType<TextPart>().map((p) => p.text))
    .join('\n');

void main() {
  group('generateObject', () {
    test('promptOnly: decodes valid JSON on the first try', () async {
      final model = FakeLanguageModel([
        [
          const TextDeltaPart('{"name":"Ada","age":36}'),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final agent = ToolLoopAgent<Object?>(model: model);

      final result = await agent.generateObject('Who?', schema: personSchema);

      expect(result.object.name, 'Ada');
      expect(result.object.age, 36);
      expect(model.requests, hasLength(1));
      // Prompt-only injects the schema instruction and uses text format.
      expect(model.requests.first.responseFormat, isA<TextResponseFormat>());
      expect(_userText(model.requests.first), contains('JSON Schema'));
    });

    test('promptOnly: repairs after invalid output', () async {
      final model = FakeLanguageModel([
        [
          const TextDeltaPart('not json at all'),
          const FinishPart(FinishReason.stop),
        ],
        [
          const TextDeltaPart('{"name":"Ada","age":36}'),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final agent = ToolLoopAgent<Object?>(model: model);

      final result = await agent.generateObject('Who?', schema: personSchema);

      expect(result.object.name, 'Ada');
      expect(model.requests, hasLength(2));
      // The repair turn carries a corrective user message.
      expect(_userText(model.requests[1]), contains('did not validate'));
    });

    test('jsonSchema: sends a JsonResponseFormat and skips the instruction',
        () async {
      final model = FakeLanguageModel(
        [
          [
            const TextDeltaPart('{"name":"Ada","age":36}'),
            const FinishPart(FinishReason.stop),
          ],
        ],
        structuredOutputModes: const {StructuredOutputMode.jsonSchema},
      );
      final agent = ToolLoopAgent<Object?>(model: model);

      final result = await agent.generateObject('Who?', schema: personSchema);

      expect(result.object.name, 'Ada');
      final format = model.requests.first.responseFormat;
      expect(format, isA<JsonResponseFormat>());
      expect((format as JsonResponseFormat).schema, personSchema.jsonSchema);
      // Native schema → no prompt-injected JSON Schema instruction.
      expect(_userText(model.requests.first), isNot(contains('JSON Schema')));
    });

    test('toolMode: forces the final_answer tool and decodes its arguments',
        () async {
      final model = FakeLanguageModel(
        [
          [
            const ToolCallCompletePart(
              toolCallId: 'c1',
              toolName: 'final_answer',
              input: {'name': 'Ada', 'age': 36},
            ),
            const FinishPart(FinishReason.stop),
          ],
        ],
        structuredOutputModes: const {
          StructuredOutputMode.toolMode,
          StructuredOutputMode.promptOnly,
        },
      );
      final agent = ToolLoopAgent<Object?>(model: model);

      final result = await agent.generateObject('Who?', schema: personSchema);

      expect(result.object.name, 'Ada');
      expect(result.object.age, 36);
      final choice = model.requests.first.toolChoice;
      expect(choice.mode, ToolChoiceMode.specific);
      expect(choice.toolName, 'final_answer');
      expect(model.requests.first.tools.single.name, 'final_answer');
      expect(model.requests.first.tools.single.inputJsonSchema,
          personSchema.jsonSchema);
    });

    test('Output is a drop-in Schema for generateObject', () async {
      final schema = Output.object<Person>(
        {
          'name': Schema.string(),
          'age': Schema.integer(),
        },
        required: ['name', 'age'],
        fromJson: (j) => (
          name: j['name']! as String,
          age: (j['age']! as num).toInt(),
        ),
      );
      final model = FakeLanguageModel([
        [
          const TextDeltaPart('{"name":"Grace","age":85}'),
          const FinishPart(FinishReason.stop),
        ],
      ]);
      final agent = ToolLoopAgent<Object?>(model: model);

      final result = await agent.generateObject('Who?', schema: schema);

      expect(result.object.name, 'Grace');
    });
  });

  group('Output', () {
    test('array produces an array JSON Schema', () {
      final schema = Output.array<String>(Schema.string());
      expect(schema.jsonSchema, {
        'type': 'array',
        'items': {'type': 'string'},
      });
    });

    test('choice produces a string enum JSON Schema', () {
      final schema = Output.choice(['low', 'medium', 'high']);
      expect(schema.jsonSchema, {
        'type': 'string',
        'enum': ['low', 'medium', 'high'],
      });
      expect(schema.decode('high'), 'high');
    });
  });
}
