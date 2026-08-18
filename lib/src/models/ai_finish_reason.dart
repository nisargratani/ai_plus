/// Indicates why an AI model stopped generating content.
enum AiFinishReason {
  /// The model reached a natural stopping point.
  stop,

  /// The model reached its maximum allowed length or token limit.
  length,

  /// The model stopped because it needs to call a tool.
  toolCalls,

  /// The model stopped due to a content filter flag.
  contentFilter,

  /// The generation was cancelled by the user.
  cancelled,

  /// The finish reason is unknown or not supported by the provider.
  unknown,
}
