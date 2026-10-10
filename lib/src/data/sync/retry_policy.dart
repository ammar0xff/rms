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
    final jitter = _random.nextInt((capped * 0.2).clamp(1, capped).toInt());
    return Duration(milliseconds: min(capped + jitter, maxDelay.inMilliseconds));
  }
}
