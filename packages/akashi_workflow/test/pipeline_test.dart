import 'dart:async';

import 'package:akashi_workflow/akashi_workflow.dart';
import 'package:test/test.dart';

void main() {
  test('runs each item through every stage', () async {
    final wf = Workflow(maxConcurrency: 4);
    final pipeline = Pipeline.input<int>()
        .stage<int>('double', (n, ctx) async => n * 2)
        .stage<String>('label', (n, ctx) async => 'v$n');
    final results = await wf.pipeline([1, 2, 3], pipeline);
    expect(results.map((r) => r.value), ['v2', 'v4', 'v6']);
    expect(results.every((r) => r.ok), isTrue);
    wf.dispose();
  });

  test('a failing stage isolates just that item', () async {
    final wf = Workflow(maxConcurrency: 4);
    final pipeline = Pipeline.input<int>()
        .stage<int>('double', (n, ctx) async => n * 2)
        .stage<String>('label', (n, ctx) async {
      if (n == 4) throw StateError('reject 4');
      return 'v$n';
    });
    // inputs 1,2,3 → doubled 2,4,6 → item 2 (=>4) is rejected.
    final results = await wf.pipeline([1, 2, 3], pipeline);
    expect(results[0].value, 'v2');
    expect(results[1].ok, isFalse);
    expect(results[1].error, isA<StateError>());
    expect(results[2].value, 'v6');
    wf.dispose();
  });

  test('exposes index and originalItem to stages', () async {
    final wf = Workflow();
    final seen = <String>[];
    final pipeline =
        Pipeline.input<String>().stage<String>('echo', (s, ctx) async {
      seen.add('${ctx.index}:${ctx.originalItem}');
      return s.toUpperCase();
    });
    final results = await wf.pipeline(['a', 'b'], pipeline);
    expect(results.map((r) => r.value), ['A', 'B']);
    expect(seen, containsAll(['0:a', '1:b']));
    wf.dispose();
  });

  test('does not barrier between stages (an item finishes while another lags)',
      () async {
    final wf = Workflow(maxConcurrency: 4);
    final gate = Completer<void>();
    var fastFinishedBeforeSlowStage2 = false;
    final pipeline =
        Pipeline.input<String>().stage<String>('stage1', (s, ctx) async {
      if (s == 'slow') await gate.future; // hold the slow item in stage 1
      return s;
    }).stage<String>('stage2', (s, ctx) async {
      if (s == 'fast') fastFinishedBeforeSlowStage2 = true;
      return s;
    });
    final future = wf.pipeline(['slow', 'fast'], pipeline);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // The fast item reached stage 2 while slow is still stuck in stage 1.
    expect(fastFinishedBeforeSlowStage2, isTrue);
    gate.complete();
    await future;
    wf.dispose();
  });
}
