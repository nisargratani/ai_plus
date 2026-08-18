import 'dart:convert';
import '../models/ai_message.dart';
import '../tools/ai_tool.dart';
import '../structured_output/schema.dart';
import '../chat/conversation.dart';
import '../embeddings/embedding_service.dart';
import 'ai_provider.dart';
import 'ai_request.dart';
import 'ai_response.dart';
import 'ai_stream.dart';
import '../errors/ai_exception.dart';
import '../logging/ai_logger.dart';
import '../retry/retry_policy.dart';
import '../cache/ai_cache.dart';
import '../middleware/ai_middleware.dart';
import '../middleware/retry_middleware.dart';
import '../middleware/cache_middleware.dart';
import '../middleware/logging_middleware.dart';

/// The main entry point for the `ai_plus` SDK.
///
/// [AiClient] provides a high-level, provider-agnostic API for interacting
/// with AI services. It wraps an [AiProvider] and adds middleware support
/// for logging, caching, retries, and custom interceptors.
///
/// ```dart
/// final ai = AiClient(
///   provider: AiProvider.openAI(apiKey: apiKey),
///   timeout: const Duration(seconds: 60),
///   retryPolicy: AiRetryPolicy(maxAttempts: 3),
/// );
///
/// final response = await ai.chat(
///   messages: [AiMessage.user('Hello!')],
/// );
/// print(response.text);
/// ```
class AiClient {
  /// The underlying AI provider (e.g. OpenAI, Gemini).
  final AiProvider provider;

  /// The default model to use if one is not specified in the request.
  final String? defaultModel;

  /// The maximum duration to wait for a request before throwing a timeout exception.
  final Duration? timeout;

  /// The retry policy. Defaults to a standard exponential backoff with 3 attempts.
  final AiRetryPolicy retryPolicy;

  /// The logger used for debugging and info.
  final AiLogger? logger;

  /// The cache used to store and retrieve identical requests.
  final AiCache? cache;

  /// Custom middleware to be executed before built-in middlewares.
  final List<AiMiddleware> middlewares;

  /// Service for creating embeddings.
  late final AiEmbeddingService embeddings;

  List<AiMiddleware> get _allMiddlewares {
    final list = <AiMiddleware>[...middlewares];

    if (logger != null) {
      list.add(LoggingMiddleware(logger!));
    }
    if (cache != null) {
      list.add(CacheMiddleware(cache!));
    }
    if (retryPolicy.maxAttempts > 0) {
      list.add(RetryMiddleware(policy: retryPolicy, logger: logger));
    }

    return list;
  }

  /// Creates an [AiClient] with the given [provider] and optional configuration.
  ///
  /// - [defaultModel]: The default model to use when none is specified per-request.
  /// - [timeout]: Maximum duration for a request before it times out.
  /// - [retryPolicy]: Configures automatic retry behavior for transient failures.
  /// - [logger]: An [AiLogger] instance for SDK logging.
  /// - [cache]: An [AiCache] instance for response caching.
  /// - [middlewares]: Custom middleware to intercept requests/responses.
  AiClient({
    required this.provider,
    this.defaultModel,
    this.timeout,
    this.retryPolicy = const AiRetryPolicy(),
    this.logger,
    this.cache,
    this.middlewares = const [],
  }) {
    embeddings = AiEmbeddingService(provider);
  }

  /// Creates a new conversation with this client.
  ///
  /// A conversation maintains message history across multiple exchanges.
  ///
  /// ```dart
  /// final conversation = ai.conversation();
  /// final response = await conversation.send('Hello');
  /// final followUp = await conversation.send('Tell me more');
  /// ```
  AiConversation conversation({
    String? id,
    String? model,
    List<AiTool>? tools,
    int? maxTokens,
    double? temperature,
    List<AiMessage> initialMessages = const [],
  }) {
    return AiConversation(
      this,
      id: id,
      model: model ?? defaultModel,
      tools: tools,
      maxTokens: maxTokens,
      temperature: temperature,
      initialMessages: initialMessages,
    );
  }

  /// Sends a chat request to the configured AI provider.
  ///
  /// Returns an [AiResponse] containing the model's response, usage statistics,
  /// and finish reason.
  ///
  /// Throws [AiAuthenticationException] when authentication fails.
  /// Throws [AiRateLimitException] when the provider rate limits the request.
  /// Throws [AiTimeoutException] when the request exceeds the configured timeout.
  /// Throws [AiUnsupportedCapabilityException] when the provider doesn't support
  /// a requested feature (e.g. tools when toolCalling is false).
  Future<AiResponse> chat({
    required List<AiMessage> messages,
    String? model,
    int? maxTokens,
    double? temperature,
    double? topP,
    List<String>? stop,
    List<AiTool>? tools,
    AiJsonSchema? schema,
  }) {
    // Validate tool calling capability
    if (tools != null &&
        tools.isNotEmpty &&
        !provider.capabilities.toolCalling) {
      throw AiUnsupportedCapabilityException(
        'The configured provider does not support tool calling.',
        provider: provider.runtimeType.toString(),
      );
    }

    // Validate structured output capability
    if (schema != null && !provider.capabilities.structuredOutput) {
      throw AiUnsupportedCapabilityException(
        'The configured provider does not support structured output.',
        provider: provider.runtimeType.toString(),
      );
    }

    final request = AiRequest(
      messages: messages,
      model: model ?? defaultModel,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      stop: stop,
      tools: tools,
      schema: schema,
    );

    // Build the middleware chain
    AiRequestHandler handler = _executeProviderChat;

    // Apply middlewares in reverse order so the first one wraps the outer call
    for (final middleware in _allMiddlewares.reversed) {
      final next = handler;
      handler = (req) => middleware.handleChat(req, next);
    }

    return handler(request);
  }

  /// Sends a request to the configured AI provider and streams the response.
  ///
  /// Returns a [Stream] of [AiStreamChunk]s. Each chunk may contain partial text,
  /// tool calls, or usage information.
  ///
  /// Supports cancellation via standard [StreamSubscription.cancel].
  ///
  /// ```dart
  /// await for (final chunk in ai.stream(messages: [...])) {
  ///   stdout.write(chunk.text);
  /// }
  /// ```
  ///
  /// Throws [AiUnsupportedCapabilityException] if the provider doesn't support streaming.
  Stream<AiStreamChunk> stream({
    required List<AiMessage> messages,
    String? model,
    int? maxTokens,
    double? temperature,
    double? topP,
    List<String>? stop,
    List<AiTool>? tools,
  }) {
    if (!provider.capabilities.streaming) {
      throw AiUnsupportedCapabilityException(
        'The configured provider does not support streaming.',
        provider: provider.runtimeType.toString(),
      );
    }

    final request = AiRequest(
      messages: messages,
      model: model ?? defaultModel,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      stop: stop,
      tools: tools,
    );

    // Build the middleware chain
    AiStreamHandler handler = _executeProviderStream;

    for (final middleware in _allMiddlewares.reversed) {
      final next = handler;
      handler = (req) => middleware.handleStream(req, next);
    }

    return handler(request);
  }

  /// Convenience method to stream only text, as a simple [Stream<String>].
  ///
  /// This is equivalent to calling [stream] and extracting the text from each chunk.
  ///
  /// ```dart
  /// await for (final text in ai.streamText(messages: [...])) {
  ///   stdout.write(text);
  /// }
  /// ```
  Stream<String> streamText({
    required List<AiMessage> messages,
    String? model,
    int? maxTokens,
    double? temperature,
    double? topP,
    List<String>? stop,
  }) {
    return stream(
      messages: messages,
      model: model,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      stop: stop,
    ).map((chunk) => chunk.text);
  }

  /// Generates a structured output and decodes it into a Dart object.
  ///
  /// The method sends a chat request with an optional [schema] hint, extracts
  /// JSON from the response, and passes it through the [decoder] function.
  ///
  /// ```dart
  /// final profile = await ai.generate<UserProfile>(
  ///   prompt: 'Create a fictional user profile.',
  ///   schema: AiJsonSchema.object(properties: {...}),
  ///   decoder: UserProfile.fromJson,
  /// );
  /// ```
  ///
  /// Throws [AiStructuredOutputException] if JSON extraction or decoding fails.
  Future<T> generate<T>({
    required String prompt,
    required AiJsonSchema schema,
    required T Function(Map<String, dynamic> json) decoder,
    String? model,
    int? maxTokens,
    double? temperature,
  }) async {
    final response = await chat(
      messages: [AiMessage.user(prompt)],
      model: model,
      maxTokens: maxTokens,
      temperature: temperature,
      schema: provider.capabilities.structuredOutput ? schema : null,
    );

    final text = response.text;

    // Find JSON block if present
    final jsonStart = text.indexOf('{');
    final jsonEnd = text.lastIndexOf('}');

    if (jsonStart == -1 || jsonEnd == -1 || jsonStart > jsonEnd) {
      throw AiStructuredOutputException(
        'Failed to extract JSON from response',
        provider: provider.runtimeType.toString(),
        rawResponse: text,
      );
    }

    final jsonStr = text.substring(jsonStart, jsonEnd + 1);

    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return decoder(decoded);
    } catch (e) {
      throw AiStructuredOutputException(
        'Failed to decode JSON: $e',
        provider: provider.runtimeType.toString(),
        rawResponse: jsonStr,
      );
    }
  }

  /// Closes the client and releases any resources.
  ///
  /// After calling this method, the client should not be used.
  void close() {
    // Provider implementations may hold HTTP clients
    // This is a no-op for the base client but signals intent
  }

  Future<AiResponse> _executeProviderChat(AiRequest request) {
    Future<AiResponse> future = provider.chat(request);

    if (timeout != null) {
      future = future.timeout(
        timeout!,
        onTimeout: () => throw AiTimeoutException(
            'Request timed out after ${timeout!.inSeconds} seconds'),
      );
    }

    return future;
  }

  Stream<AiStreamChunk> _executeProviderStream(AiRequest request) {
    Stream<AiStreamChunk> resultStream = provider.stream(request);

    if (timeout != null) {
      resultStream = resultStream.timeout(
        timeout!,
        onTimeout: (sink) => sink.addError(AiTimeoutException(
            'Stream timed out after ${timeout!.inSeconds} seconds')),
      );
    }

    return resultStream;
  }
}
