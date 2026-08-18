/// Represents the capabilities of an AI provider or a specific model.
class AiCapabilities {
  /// Whether the provider supports streaming responses.
  final bool streaming;

  /// Whether the provider supports tool calling (function calling).
  final bool toolCalling;

  /// Whether the provider supports returning structured output (e.g. JSON schema).
  final bool structuredOutput;

  /// Whether the provider supports generating embeddings.
  final bool embeddings;

  /// Whether the provider supports accepting image inputs.
  final bool imageInput;

  /// Whether the provider supports accepting audio inputs.
  final bool audioInput;

  /// Whether the provider supports accepting arbitrary file inputs.
  final bool fileInput;

  const AiCapabilities({
    this.streaming = false,
    this.toolCalling = false,
    this.structuredOutput = false,
    this.embeddings = false,
    this.imageInput = false,
    this.audioInput = false,
    this.fileInput = false,
  });
}
