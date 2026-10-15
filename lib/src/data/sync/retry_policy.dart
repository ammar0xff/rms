import 'dart:math';

class RetryPolicy {
  RetryPolicy({
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 5),
    this.maxAttempts = 8,
    Random? random,
  }) : _random = random ?? Random();

  final Duration baseDelay;
  final Duration maxDelay;
  final int maxAttempts;
  final Random _random;

  bool shouldRetry(int attemptCount) => attemptCount < maxAttempts;

  Duration nextDelay(int attemptCount) {
    final exponential = baseDelay.inMilliseconds * pow(2, attemptCount).toInt();
    final capped = min(exponential, maxDelay.inMilliseconds);
    // Robust to zero/degenerate policies (tests use baseDelay: Duration.zero
    // for immediate retries): the old clamp(1, capped) threw when capped < 1,
    // and nextInt(0) throws, so a non-positive spread means no jitter at all.
    final spread = (capped * 0.2).toInt();
    final jitter = spread <= 0 ? 0 : _random.nextInt(spread);
    return Duration(milliseconds: min(capped + jitter, maxDelay.inMilliseconds));
  }
}
