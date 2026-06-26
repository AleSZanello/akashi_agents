import 'dart:async';

/// A cooperative cancellation signal threaded through a model request and the
/// agent loop.
///
/// Cancellation is cooperative: callers observe [isCancelled] (or await
/// [whenCancelled]) and stop work. Nothing is forcibly aborted.
class CancellationToken {
  CancellationToken();

  final Completer<void> _completer = Completer<void>();
  bool _cancelled = false;

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _completer.future;

  /// Requests cancellation. Idempotent.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    if (!_completer.isCompleted) _completer.complete();
  }
}
