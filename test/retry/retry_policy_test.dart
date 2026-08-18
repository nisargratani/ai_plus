import 'package:test/test.dart';
import 'package:ai_plus/ai_plus.dart';

void main() {
  group('AiRetryPolicy', () {
    test('default values', () {
      const policy = AiRetryPolicy();
      expect(policy.maxAttempts, 3);
      expect(policy.initialDelay, const Duration(milliseconds: 500));
      expect(policy.maxDelay, const Duration(seconds: 10));
      expect(policy.backoffFactor, 2.0);
      expect(policy.jitter, isTrue);
    });

    test('AiRetryPolicy.none has zero attempts', () {
      expect(AiRetryPolicy.none.maxAttempts, 0);
    });

    test('calculateDelay returns zero when attempt >= maxAttempts', () {
      const policy = AiRetryPolicy(maxAttempts: 3);
      expect(policy.calculateDelay(3), Duration.zero);
      expect(policy.calculateDelay(5), Duration.zero);
    });

    test('calculateDelay increases exponentially', () {
      const policy = AiRetryPolicy(
        initialDelay: Duration(milliseconds: 100),
        backoffFactor: 2.0,
        jitter: false,
        maxAttempts: 5,
        maxDelay: Duration(seconds: 60),
      );

      final d0 = policy.calculateDelay(0).inMilliseconds;
      final d1 = policy.calculateDelay(1).inMilliseconds;
      final d2 = policy.calculateDelay(2).inMilliseconds;

      expect(d0, 100);
      expect(d1, 200);
      expect(d2, 400);
    });

    test('calculateDelay respects maxDelay', () {
      const policy = AiRetryPolicy(
        initialDelay: Duration(seconds: 5),
        maxDelay: Duration(seconds: 10),
        backoffFactor: 3.0,
        jitter: false,
        maxAttempts: 5,
      );

      final d2 = policy.calculateDelay(2); // 5 * 9 = 45s, capped at 10s
      expect(d2.inSeconds, 10);
    });

    test('calculateDelay with jitter adds randomness', () {
      const policy = AiRetryPolicy(
        initialDelay: Duration(milliseconds: 1000),
        jitter: true,
        maxAttempts: 5,
      );

      // Run multiple times to see variance
      final results = <int>{};
      for (int i = 0; i < 20; i++) {
        results.add(policy.calculateDelay(0).inMilliseconds);
      }

      // With 20% jitter on 1000ms, values should be between ~800 and ~1200
      // At least *some* variance expected
      // (There's a tiny chance all 20 are identical, but extremely unlikely)
      expect(results.length, greaterThan(1));
    });

    test('custom configuration', () {
      const policy = AiRetryPolicy(
        maxAttempts: 5,
        initialDelay: Duration(seconds: 1),
        maxDelay: Duration(seconds: 30),
        backoffFactor: 3.0,
        jitter: false,
      );

      expect(policy.maxAttempts, 5);
      expect(policy.initialDelay, const Duration(seconds: 1));
      expect(policy.maxDelay, const Duration(seconds: 30));
      expect(policy.backoffFactor, 3.0);
      expect(policy.jitter, isFalse);
    });
  });
}
