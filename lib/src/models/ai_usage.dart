/// Tracks the token usage of an AI request.
class AiUsage {
  /// The number of tokens used in the input (prompt).
  final int? inputTokens;

  /// The number of tokens generated in the output (completion).
  final int? outputTokens;

  /// The total number of tokens used.
  final int? totalTokens;

  /// Creates a usage record. Unknown counts are `null`.
  const AiUsage({
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
  });

  /// An empty usage object.
  static const empty = AiUsage();
}
