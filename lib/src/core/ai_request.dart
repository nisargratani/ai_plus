import '../errors/ai_exception.dart';
import '../models/ai_message.dart';
import '../structured_output/schema.dart';
import '../tools/ai_tool.dart';

/// Represents a request to an AI provider.
///
/// This is an immutable value object that encapsulates all parameters
/// needed for a chat completion request.
class AiRequest {
  /// The list of messages in the conversation so far.
  final List<AiMessage> messages;

  /// The model to use for the request (optional, falls back to provider default).
  final String? model;

  /// The maximum number of tokens to generate.
  final int? maxTokens;

  /// The sampling temperature to use (0–2 for OpenAI and Gemini, 0–1 for
  /// Anthropic).
  ///
  /// Higher values (e.g. 0.8) make output more random, lower values
  /// (e.g. 0.2) make it more focused and deterministic.
  ///
  /// Anthropic models that reject sampling parameters (Claude Sonnet 5,
  /// Opus 4.7 and later, Haiku 5.5, Fable, and every model on API version
  /// `2026-10-21` or later) do not receive it: `AnthropicProvider` omits it,
  /// and `AiClient` logs a one-time warning through its logger.
  final double? temperature;

  /// An alternative to sampling with temperature, called nucleus sampling.
  ///
  /// The model considers the results of the tokens with top_p probability mass.
  /// Omitted for Anthropic models that reject it, like [temperature].
  final double? topP;

  /// Stop sequences where the model will stop generating further tokens.
  final List<String>? stop;

  /// A list of tools the model may call.
  final List<AiTool>? tools;

  /// An optional JSON schema for structured output.
  ///
  /// When provided, providers that support structured output natively
  /// will use this to constrain the model's response format.
  final AiJsonSchema? schema;

  /// Aborts the HTTP request when this future completes.
  ///
  /// A cancellation hook: the built-in providers pass it to the HTTP client,
  /// which aborts the request (or the response stream) and fails it with an
  /// [AiTimeoutException]. `RetryMiddleware` does not retry a request whose
  /// trigger has fired. Set it from a middleware with [copyWith], or when
  /// calling an `AiProvider` directly. It must not complete with an error.
  ///
  /// `AiClient` also uses it to abort a `chat` attempt that exceeds
  /// `AiClient.timeout`. It is not part of the cache key.
  final Future<void>? abortTrigger;

  /// Creates a request.
  const AiRequest({
    required this.messages,
    this.model,
    this.maxTokens,
    this.temperature,
    this.topP,
    this.stop,
    this.tools,
    this.schema,
    this.abortTrigger,
  });

  /// Creates a copy of this request with the given fields replaced.
  ///
  /// Fields cannot be reset to `null` through this method.
  AiRequest copyWith({
    List<AiMessage>? messages,
    String? model,
    int? maxTokens,
    double? temperature,
    double? topP,
    List<String>? stop,
    List<AiTool>? tools,
    AiJsonSchema? schema,
    Future<void>? abortTrigger,
  }) {
    return AiRequest(
      messages: messages ?? this.messages,
      model: model ?? this.model,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      stop: stop ?? this.stop,
      tools: tools ?? this.tools,
      schema: schema ?? this.schema,
      abortTrigger: abortTrigger ?? this.abortTrigger,
    );
  }
}
