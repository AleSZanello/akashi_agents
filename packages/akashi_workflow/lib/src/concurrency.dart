import 'dart:async';
import 'dart:collection';

/// A counting semaphore bounding how many operations run at once.
///
/// Acquirers beyond [maxConcurrency] queue FIFO and resume as permits are
/// released. This is what keeps a fan-out of hundreds of tasks from launching
/// hundreds of concurrent model calls.
class Semaphore {
  /// Creates a semaphore allowing [maxConcurrency] concurrent holders.
  Semaphore(this.maxConcurrency)
      : assert(maxConcurrency > 0, 'maxConcurrency must be > 0'),
        _available = maxConcurrency;

  /// The maximum number of permits held simultaneously.
  final int maxConcurrency;

  int _available;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  /// Permits currently free.
  int get available => _available;

  /// Number of acquirers currently queued.
  int get waiting => _waiters.length;

  /// Acquire a permit, waiting (FIFO) if none are free.
  Future<void> acquire() {
    if (_available > 0) {
      _available--;
      return Future<void>.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  /// Release a permit, waking the next waiter if any.
  void release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
    } else {
      _available++;
    }
  }

  /// Run [action] holding a permit, releasing it even if [action] throws.
  Future<T> withPermit<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }
}
