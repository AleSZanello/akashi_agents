import 'dart:math';

/// A retry policy: how many attempts, and how long to wait between them.
///
/// Delays grow geometrically ([backoffFactor]) from [initialDelay], capped at
/// [maxDelay], with proportional [jitter] to avoid thundering-herd retries.
/// [retryIf] decides per-error whether a failure is retryable (default: retry
/// everything except cancellation/budget errors — see `Workflow`).
class RetryPolicy {
  /// Creates a retry policy.
  const RetryPolicy({
    this.maxAttempts = 1,
    this.initialDelay = const Duration(milliseconds: 200),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffFactor = 2.0,
    this.jitter = 0.25,
    this.retryIf,
  })  : assert(maxAttempts >= 1, 'maxAttempts must be >= 1'),
        assert(backoffFactor >= 1, 'backoffFactor must be >= 1'),
        assert(jitter >= 0 && jitter <= 1, 'jitter must be in [0, 1]');

  /// Total attempts including the first (1 = no retries).
  final int maxAttempts;

  /// Delay before the second attempt; the base for geometric backoff.
  final Duration initialDelay;

  /// Upper bound on any single backoff delay.
  final Duration maxDelay;

  /// Geometric growth factor applied per attempt.
  final double backoffFactor;

  /// Proportional random jitter in `[0, 1]` (0.25 → ±25%).
  final double jitter;

  /// Whether a given error is retryable. When null, `Workflow`'s default applies.
  final bool Function(Object error)? retryIf;

  /// No retries (a single attempt). The default.
  static const RetryPolicy none = RetryPolicy();

  /// A sensible network-ish default: 3 attempts with 200ms→ backoff.
  static const RetryPolicy standard = RetryPolicy(maxAttempts: 3);

  /// The delay to wait after a failed [attempt] (1-based) before the next one.
  Duration backoffFor(int attempt, Random random) {
    final base = initialDelay.inMicroseconds *
        pow(backoffFactor, attempt - 1).toDouble();
    final capped = min(base, maxDelay.inMicroseconds.toDouble());
    // Scale by a factor in [1 - jitter, 1 + jitter].
    final jitterFactor = 1 + (random.nextDouble() * 2 - 1) * jitter;
    final withJitter =
        (capped * jitterFactor).clamp(0, maxDelay.inMicroseconds.toDouble());
    return Duration(microseconds: withJitter.round());
  }
}
