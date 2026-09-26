import 'dart:math';

/// Defines how the SDK should retry failed requests.
///
/// Delays grow as `initialDelay * backoffFactor^attempt`, capped at
/// [maxDelay], with ±20% jitter when [jitter] is enabled.
class AiRetryPolicy {
  static final _random = Random();

  /// The maximum number of retries after the initial attempt.
  ///
  /// A value of 3 allows up to 4 calls in total; 0 disables retries.
  final int maxAttempts;

  /// The initial delay before the first retry.
  final Duration initialDelay;

  /// The maximum delay between any two retries.
  final Duration maxDelay;

  /// The multiplier to use for exponential backoff.
  final double backoffFactor;

  /// Whether to add jitter (randomness) to the delay to prevent thundering herd problems.
  final bool jitter;

  /// Creates a retry policy.
  const AiRetryPolicy({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 10),
    this.backoffFactor = 2.0,
    this.jitter = true,
  });

  /// An empty policy that disables retries.
  static const none = AiRetryPolicy(maxAttempts: 0);

  /// Calculates the delay for the next attempt (0-indexed).
  Duration calculateDelay(int attempt) {
    if (attempt >= maxAttempts) return Duration.zero;

    final delayMs = initialDelay.inMilliseconds * pow(backoffFactor, attempt);
    var finalDelayMs = min(delayMs, maxDelay.inMilliseconds.toDouble());

    if (jitter) {
      // Jitter up to 20%
      final jitterAmount = finalDelayMs * 0.2;
      final jitterValue =
          (_random.nextDouble() * jitterAmount * 2) - jitterAmount;
      finalDelayMs += jitterValue;
    }

    return Duration(milliseconds: finalDelayMs.round());
  }
}
