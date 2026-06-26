import 'package:akashi/akashi.dart';
import 'package:test/test.dart';

void main() {
  group('tool<I, TDeps>', () {
    ToolContext<Object?> context() => ToolContext<Object?>(
          deps: null,
          toolCallId: 'c1',
          step: 0,
          history: const [],
          cancel: CancellationToken(),
          tracer: const NoopTracer(),
        );

    test('decodes raw JSON into the typed input before execute runs', () async {
      final captured = <String>[];
      final weather = tool<({String city}), Object?>(
        name: 'get_weather',
        description: 'weather',
        inputSchema: Schema.object(
          {'city': Schema.string()},
          required: ['city'],
          fromJson: (json) => (city: json['city']! as String),
        ),
        execute: (input, ctx) async {
          captured.add(input.city);
          return 'ok';
        },
      );

      final output = await weather.execute({'city': 'Lima'}, context());
      expect(output, 'ok');
      expect(captured.single, 'Lima');
      expect(weather.spec.name, 'get_weather');
      expect(weather.spec.inputJsonSchema['type'], 'object');
    });

    test('needsApproval defaults to false and honors the predicate', () async {
      final guarded = tool<({String amount}), Object?>(
        name: 'pay',
        description: 'pay',
        inputSchema: Schema.object(
          {'amount': Schema.string()},
          required: ['amount'],
          fromJson: (json) => (amount: json['amount']! as String),
        ),
        needsApproval: (input, ctx) => input.amount != '0',
        execute: (input, ctx) async => 'paid',
      );

      expect(
          await guarded.needsApprovalFor({'amount': '0'}, context()), isFalse);
      expect(
          await guarded.needsApprovalFor({'amount': '5'}, context()), isTrue);
    });
  });
}
