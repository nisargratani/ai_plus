import '../models/ai_usage.dart';

/// Tracks token usage and estimated costs across multiple AI requests.
///
/// Record each response's usage with [addUsage].
///
/// ```dart
/// final tracker = AiCostTracker();
/// tracker.addUsage(response.usage);
///
/// print('Total tokens: ${tracker.totalTokens}');
/// print('Estimated cost: \$${tracker.estimatedCost.toStringAsFixed(4)}');
/// ```
class AiCostTracker {
  int _requestCount = 0;
  int _totalInputTokens = 0;
  int _totalOutputTokens = 0;

  /// The pricing configuration for cost estimation.
  final AiPricing pricing;

  /// Creates a cost tracker with optional [pricing] configuration.
  ///
  /// If no pricing is provided, cost estimation will return 0.
  AiCostTracker({this.pricing = const AiPricing()});

  /// The total number of requests tracked.
  int get requestCount => _requestCount;

  /// The total number of input (prompt) tokens across all requests.
  int get totalInputTokens => _totalInputTokens;

  /// The total number of output (completion) tokens across all requests.
  int get totalOutputTokens => _totalOutputTokens;

  /// The total number of tokens across all requests.
  int get totalTokens => _totalInputTokens + _totalOutputTokens;

  /// The estimated cost based on the configured [pricing].
  double get estimatedCost {
    return (_totalInputTokens * pricing.inputCostPerToken) +
        (_totalOutputTokens * pricing.outputCostPerToken);
  }

  /// Records usage from a single AI request.
  void addUsage(AiUsage usage) {
    _requestCount++;
    _totalInputTokens += usage.inputTokens ?? 0;
    _totalOutputTokens += usage.outputTokens ?? 0;
  }

  /// Resets all tracked usage statistics.
  void reset() {
    _requestCount = 0;
    _totalInputTokens = 0;
    _totalOutputTokens = 0;
  }

  @override
  String toString() =>
      'AiCostTracker(requests: $_requestCount, tokens: $totalTokens, '
      'estimatedCost: \$${estimatedCost.toStringAsFixed(4)})';
}

/// Configurable pricing information for cost estimation.
///
/// Prices are specified per-token. For example, if the provider charges
/// \$0.01 per 1K input tokens, set [inputCostPerToken] to `0.00001`.
///
/// ```dart
/// const gpt4oPricing = AiPricing(
///   inputCostPerToken: 0.0000025,   // $2.50 per 1M tokens
///   outputCostPerToken: 0.00001,    // $10 per 1M tokens
/// );
/// ```
class AiPricing {
  /// The cost per input token.
  final double inputCostPerToken;

  /// The cost per output token.
  final double outputCostPerToken;

  /// Creates a pricing configuration.
  const AiPricing({
    this.inputCostPerToken = 0.0,
    this.outputCostPerToken = 0.0,
  });
}
