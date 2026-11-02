/// Tracks the token usage of an AI request.
///
/// Counts are normalised across providers: [inputTokens] is the whole
/// prompt (including tokens served from the provider's prompt cache) and
/// [outputTokens] is everything generated (including thinking), so
/// `inputTokens + outputTokens == totalTokens` whenever all three are known.
class AiUsage {
  /// The number of tokens used in the input (prompt), cached ones included.
  final int? inputTokens;

  /// The number of tokens generated in the output (completion), including
  /// reasoning/thinking tokens, which providers bill as output.
  final int? outputTokens;

  /// The total number of tokens used.
  final int? totalTokens;

  /// Of [outputTokens], the reasoning/thinking tokens, when the provider
  /// reports them (OpenAI `reasoning_tokens`, Gemini `thoughtsTokenCount`).
  final int? reasoningTokens;

  /// Of [inputTokens], the tokens read from the provider's prompt cache
  /// (OpenAI `cached_tokens`, Gemini `cachedContentTokenCount`, Anthropic
  /// `cache_read_input_tokens`). Providers usually bill them at a discount.
  final int? cachedInputTokens;

  /// Creates a usage record. Unknown counts are `null`.
  const AiUsage({
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.reasoningTokens,
    this.cachedInputTokens,
  });

  /// An empty usage object.
  static const empty = AiUsage();

  @override
  String toString() => 'AiUsage(input: $inputTokens, output: $outputTokens, '
      'total: $totalTokens, reasoning: $reasoningTokens, '
      'cachedInput: $cachedInputTokens)';
}
