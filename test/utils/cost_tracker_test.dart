import 'package:ai_plus/ai_plus.dart';
import 'package:test/test.dart';

void main() {
  group('AiCostTracker', () {
    test('starts at zero', () {
      final tracker = AiCostTracker();
      expect(tracker.requestCount, 0);
      expect(tracker.totalInputTokens, 0);
      expect(tracker.totalOutputTokens, 0);
      expect(tracker.totalTokens, 0);
      expect(tracker.estimatedCost, 0.0);
    });

    test('tracks single usage', () {
      final tracker = AiCostTracker();
      tracker.addUsage(const AiUsage(inputTokens: 100, outputTokens: 50));

      expect(tracker.requestCount, 1);
      expect(tracker.totalInputTokens, 100);
      expect(tracker.totalOutputTokens, 50);
      expect(tracker.totalTokens, 150);
    });

    test('accumulates multiple usages', () {
      final tracker = AiCostTracker();
      tracker.addUsage(const AiUsage(inputTokens: 100, outputTokens: 50));
      tracker.addUsage(const AiUsage(inputTokens: 200, outputTokens: 100));

      expect(tracker.requestCount, 2);
      expect(tracker.totalInputTokens, 300);
      expect(tracker.totalOutputTokens, 150);
      expect(tracker.totalTokens, 450);
    });

    test('handles null token counts gracefully', () {
      final tracker = AiCostTracker();
      tracker.addUsage(AiUsage.empty);

      expect(tracker.requestCount, 1);
      expect(tracker.totalInputTokens, 0);
      expect(tracker.totalOutputTokens, 0);
    });

    test('calculates cost with pricing', () {
      final tracker = AiCostTracker(
        pricing: const AiPricing(
          inputCostPerToken: 0.00001,
          outputCostPerToken: 0.00003,
        ),
      );
      tracker.addUsage(const AiUsage(inputTokens: 1000, outputTokens: 500));

      expect(tracker.estimatedCost, closeTo(0.025, 0.0001));
    });

    test('resets all counters', () {
      final tracker = AiCostTracker();
      tracker.addUsage(const AiUsage(inputTokens: 100, outputTokens: 50));
      tracker.reset();

      expect(tracker.requestCount, 0);
      expect(tracker.totalInputTokens, 0);
      expect(tracker.totalOutputTokens, 0);
      expect(tracker.estimatedCost, 0.0);
    });

    test('toString includes summary', () {
      final tracker = AiCostTracker();
      tracker.addUsage(const AiUsage(inputTokens: 100, outputTokens: 50));
      expect(tracker.toString(), contains('150'));
    });
  });

  group('AiPricing', () {
    test('default pricing is zero', () {
      const pricing = AiPricing();
      expect(pricing.inputCostPerToken, 0.0);
      expect(pricing.outputCostPerToken, 0.0);
    });

    test('custom pricing', () {
      const pricing = AiPricing(
        inputCostPerToken: 0.00001,
        outputCostPerToken: 0.00003,
      );
      expect(pricing.inputCostPerToken, 0.00001);
      expect(pricing.outputCostPerToken, 0.00003);
    });
  });
}
