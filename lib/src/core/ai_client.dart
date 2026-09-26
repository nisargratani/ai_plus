import 'dart:convert';

import '../cache/ai_cache.dart';
import '../chat/conversation.dart';
import '../embeddings/embedding_service.dart';
import '../errors/ai_exception.dart';
import '../logging/ai_logger.dart';
import '../middleware/ai_middleware.dart';
import '../middleware/cache_middleware.dart';
import '../middleware/logging_middleware.dart';
import '../middleware/retry_middleware.dart';
import '../models/ai_message.dart';
import '../providers/closeable_provider.dart';
import '../retry/retry_policy.dart';
import '../structured_output/schema.dart';
import '../tools/ai_tool.dart';
import 'ai_provider.dart';
import 'ai_request.dart';
import 'ai_response.dart';
import 'ai_stream.dart';

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

  /// The maximum duration to wait for a request before throwing an
  /// [AiTimeoutException].
  ///
  /// For [chat] this bounds each attempt; for [stream] it bounds the gap
  /// between consecutive chunks (an idle timeout), so long streams that keep
  /// producing output are not cut off.
  final Duration? timeout;

  /// The retry policy. Defaults to exponential backoff with up to 3 retries.
  ///
  /// Use [AiRetryPolicy.none] to disable retries.
  final AiRetryPolicy retryPolicy;

  /// The logger used for debugging and info.
  final AiLogger? logger;

  /// The cache used to store and retrieve identical requests.
  final AiCache? cache;

  /// Custom middleware to be executed before built-in middlewares.
  ///
  /// The effective order is: [middlewares] → logging → cache → retry →
  /// provider (with [timeout]).
  final List<AiMiddleware> middlewares;

  /// Service for creating embeddings.
  late final AiEmbeddingService embeddings;

  /// Built-in middleware derived from the constructor arguments.
  late final List<AiMiddleware> _builtInMiddlewares = [
    if (logger case final logger?) LoggingMiddleware(logger),
    if (cache case final cache?) CacheMiddleware(cache),
    if (retryPolicy.maxAttempts > 0)
      RetryMiddleware(policy: retryPolicy, logger: logger),
  ];

  /// [middlewares] is read on every call so later additions take effect.
  List<AiMiddleware> get _allMiddlewares =>
      [...middlewares, ..._builtInMiddlewares];

  String get _providerName => provider.runtimeType.toString();

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
  ///
  /// All errors, including validation errors, are delivered through the
  /// returned [Future].
  Future<AiResponse> chat({
    required List<AiMessage> messages,
    String? model,
    int? maxTokens,
    double? temperature,
    double? topP,
    List<String>? stop,
    List<AiTool>? tools,
    AiJsonSchema? schema,
  }) async {
    _checkToolSupport(tools);

    if (schema != null && !provider.capabilities.structuredOutput) {
      throw AiUnsupportedCapabilityException(
        'The configured provider does not support structured output.',
        provider: _providerName,
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

    return await handler(request);
  }

  /// Sends a request to the configured AI provider and streams the response.
  ///
  /// Returns a [Stream] of [AiStreamChunk]s. Each chunk may contain partial text,
  /// tool calls, or usage information.
  ///
  /// Cancelling the subscription (e.g. breaking out of `await for`) aborts
  /// the underlying HTTP request.
  ///
  /// ```dart
  /// await for (final chunk in ai.stream(messages: [...])) {
  ///   stdout.write(chunk.text);
  /// }
  /// ```
  ///
  /// Tool calls are emitted once, with complete arguments, typically in the
  /// final chunk. [AiStreamChunk.finishReason] is non-null only on the chunk
  /// that ends the generation.
  ///
  /// Emits [AiUnsupportedCapabilityException] if the provider doesn't support
  /// streaming (or tools, when [tools] is non-empty). All errors are delivered
  /// through the stream.
  Stream<AiStreamChunk> stream({
    required List<AiMessage> messages,
    String? model,
    int? maxTokens,
    double? temperature,
    double? topP,
    List<String>? stop,
    List<AiTool>? tools,
  }) {
    try {
      if (!provider.capabilities.streaming) {
        throw AiUnsupportedCapabilityException(
          'The configured provider does not support streaming.',
          provider: _providerName,
        );
      }
      _checkToolSupport(tools);
    } on AiException catch (e, st) {
      return Stream.error(e, st);
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
  /// Providers with native structured output (OpenAI, Gemini, custom) receive
  /// [schema] as a response-format constraint. For other providers (such as
  /// Anthropic) the schema is added to the prompt as an instruction. The
  /// first JSON object found in the reply is then passed to [decoder].
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
    final native = provider.capabilities.structuredOutput;
    final response = await chat(
      messages: [
        if (!native)
          AiMessage.system(
            'Respond only with a single JSON object, with no surrounding '
            'text or code fences, that conforms to this JSON Schema:\n'
            '${jsonEncode(schema.toJson())}',
          ),
        AiMessage.user(prompt),
      ],
      model: model,
      maxTokens: maxTokens,
      temperature: temperature,
      schema: native ? schema : null,
    );

    final text = response.text;

    // Find JSON block if present
    final jsonStart = text.indexOf('{');
    final jsonEnd = text.lastIndexOf('}');

    if (jsonStart == -1 || jsonEnd == -1 || jsonStart > jsonEnd) {
      throw AiStructuredOutputException(
        'Failed to extract JSON from response',
        provider: _providerName,
        rawResponse: text,
      );
    }

    final jsonStr = text.substring(jsonStart, jsonEnd + 1);

    final Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    } catch (e) {
      throw AiStructuredOutputException(
        'Failed to decode JSON: $e',
        provider: _providerName,
        rawResponse: jsonStr,
      );
    }

    try {
      return decoder(decoded);
    } catch (e) {
      throw AiStructuredOutputException(
        'Decoder rejected the JSON: $e',
        provider: _providerName,
        rawResponse: jsonStr,
      );
    }
  }

  /// Closes the client and releases the provider's HTTP connections.
  ///
  /// Built-in providers close only HTTP clients they created themselves;
  /// an `AiHttpClient` you passed in stays open. After calling this method
  /// the client should not be used.
  void close() {
    final Object provider = this.provider;
    if (provider is CloseableProvider) provider.close();
  }

  void _checkToolSupport(List<AiTool>? tools) {
    if (tools != null &&
        tools.isNotEmpty &&
        !provider.capabilities.toolCalling) {
      throw AiUnsupportedCapabilityException(
        'The configured provider does not support tool calling.',
        provider: _providerName,
      );
    }
  }

  Future<AiResponse> _executeProviderChat(AiRequest request) {
    final future = provider.chat(request);
    final timeout = this.timeout;
    if (timeout == null) return future;

    return future.timeout(
      timeout,
      onTimeout: () => throw AiTimeoutException(
        'Request timed out after ${_describe(timeout)}',
        provider: _providerName,
      ),
    );
  }

  Stream<AiStreamChunk> _executeProviderStream(AiRequest request) {
    final stream = provider.stream(request);
    final timeout = this.timeout;
    if (timeout == null) return stream;

    return stream.timeout(
      timeout,
      onTimeout: (sink) {
        sink
          ..addError(AiTimeoutException(
            'Stream received no data for ${_describe(timeout)}',
            provider: _providerName,
          ))
          // Closing cancels the underlying request.
          ..close();
      },
    );
  }

  static String _describe(Duration d) => d.inMilliseconds % 1000 == 0
      ? '${d.inSeconds} seconds'
      : '${d.inMilliseconds} ms';
}
