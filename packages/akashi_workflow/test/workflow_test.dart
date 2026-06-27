import 'dart:async';
import 'dart:math';

import 'package:akashi/akashi.dart';
import 'package:akashi_workflow/akashi_workflow.dart';
import 'package:test/test.dart';

void main() {
  group('run / retry', () {
    test('runs a task to success', () async {
      final wf = Workflow();
      final value =
          await wf.run(Task<int>((ctx) async => 21 * 2, label: 'answer'));
      expect(value, 42);
      wf.dispose();
    });

    test('retries a flaky task until it succeeds', () async {
      final wf = Workflow();
      var calls = 0;
      final value = await wf.run(Task<String>(
        (ctx) async {
          calls++;
          if (calls < 3) throw StateError('transient $calls');
          return 'ok';
        },
        retry: const RetryPolicy(maxAttempts: 3, initialDelay: Duration.zero),
      ));
      expect(value, 'ok');
      expect(calls, 3);
      wf.dispose();
    });

    test('rethrows after exhausting retries', () async {
      final wf = Workflow();
      await expectLater(
        wf.run(Task<int>(
          (ctx) async => throw StateError('always'),
          retry: const RetryPolicy(maxAttempts: 2, initialDelay: Duration.zero),
        )),
        throwsA(isA<StateError>()),
      );
      wf.dispose();
    });

    test('retryIf can veto a retry', () async {
      final wf = Workflow();
      var calls = 0;
      final result = await wf.runCatching(Task<int>(
        (ctx) async {
          calls++;
          throw StateError('nope');
        },
        retry: RetryPolicy(
          maxAttempts: 5,
          initialDelay: Duration.zero,
          retryIf: (e) => e is! StateError,
        ),
      ));
      expect(result.ok, isFalse);
      expect(calls, 1); // never retried
      wf.dispose();
    });
  });

  group('concurrency', () {
    test('bounds simultaneous executions to maxConcurrency', () async {
      final wf = Workflow(maxConcurrency: 2);
      var active = 0;
      var peak = 0;
      final tasks = [
        for (var i = 0; i < 6; i++)
          Task<int>((ctx) async {
            active++;
            peak = max(peak, active);
            await Future<void>.delayed(const Duration(milliseconds: 25));
            active--;
            return i;
          }, label: 't$i'),
      ];
      final results = await wf.parallel(tasks);
      expect(results, [0, 1, 2, 3, 4, 5]);
      expect(peak, 2);
      wf.dispose();
    });
  });

  group('parallel', () {
    test('fail-fast rethrows and cancels siblings', () async {
      final wf = Workflow();
      var siblingObservedCancel = false;
      final tasks = <Task<int>>[
        Task((ctx) async => throw StateError('boom'), label: 'bad'),
        Task((ctx) async {
          await Future.any<void>([
            Future<void>.delayed(const Duration(seconds: 5)),
            ctx.cancel.whenCancelled,
          ]);
          if (ctx.cancel.isCancelled) {
            siblingObservedCancel = true;
            throw const WorkflowCancelled();
          }
          return 1;
        }, label: 'sibling'),
      ];
      await expectLater(wf.parallel(tasks), throwsA(isA<StateError>()));
      expect(siblingObservedCancel, isTrue);
      wf.dispose();
    });

    test('parallelSettled returns successes and failures in order', () async {
      final wf = Workflow();
      final results = await wf.parallelSettled<int>([
        Task((ctx) async => 1, label: 'a'),
        Task((ctx) async => throw StateError('x'), label: 'b'),
        Task((ctx) async => 3, label: 'c'),
      ]);
      expect(results.map((r) => r.ok), [true, false, true]);
      expect(results[0].value, 1);
      expect(results[1].error, isA<StateError>());
      expect(results[2].value, 3);
      wf.dispose();
    });
  });

  group('timeout', () {
    test('a slow task times out', () async {
      final wf = Workflow();
      final result = await wf.runCatching(Task<int>(
        (ctx) async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return 1;
        },
        timeout: const Duration(milliseconds: 40),
      ));
      expect(result.ok, isFalse);
      expect(result.error, isA<WorkflowTimeout>());
      wf.dispose();
    });
  });

  group('budget', () {
    test('maxTasks caps total executions', () async {
      final wf = Workflow(maxTasks: 2);
      final results = await wf.parallelSettled<int>([
        Task((ctx) async => 1),
        Task((ctx) async => 2),
        Task((ctx) async => 3),
      ]);
      expect(results.where((r) => r.ok).length, 2);
      expect(
        results.where((r) => r.error is WorkflowBudgetExceeded).length,
        1,
      );
      wf.dispose();
    });
  });

  group('cancellation', () {
    test('an external token cancels in-flight tasks', () async {
      final external = CancellationToken();
      final wf = Workflow(cancel: external);
      final future = wf.runCatching(Task<int>((ctx) async {
        await Future.any<void>([
          Future<void>.delayed(const Duration(seconds: 5)),
          ctx.cancel.whenCancelled,
        ]);
        if (ctx.cancel.isCancelled) throw const WorkflowCancelled();
        return 1;
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      external.cancel();
      final result = await future;
      expect(result.ok, isFalse);
      expect(result.error, isA<WorkflowCancelled>());
      wf.dispose();
    });
  });

  group('events', () {
    test('emits started/succeeded for a task', () async {
      final wf = Workflow();
      final events = <WorkflowEvent>[];
      final sub = wf.events.listen(events.add);
      await wf.run(Task<int>((ctx) async => 7, label: 'lucky'));
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<TaskStarted>().length, 1);
      expect(events.whereType<TaskSucceeded>().length, 1);
      expect(events.first.label, 'lucky');
      await sub.cancel();
      wf.dispose();
    });

    test('emits failed + retrying across attempts', () async {
      final wf = Workflow();
      final events = <WorkflowEvent>[];
      final sub = wf.events.listen(events.add);
      await wf.runCatching(Task<int>(
        (ctx) async => throw StateError('x'),
        retry: const RetryPolicy(maxAttempts: 2, initialDelay: Duration.zero),
      ));
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<TaskFailed>().length, 2);
      expect(events.whereType<TaskRetrying>().length, 1);
      await sub.cancel();
      wf.dispose();
    });
  });
}
