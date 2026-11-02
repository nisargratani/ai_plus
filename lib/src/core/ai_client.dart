import 'dart:async';
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
import '../models/ai_finish_reason.dart';
import '../models/ai_message.dart';
import '../providers/anthropic/anthropic_provider.dart';
import '../providers/anthropic/anthropic_sampling.dart';
import '../providers/closeable_provider.dart';
import '../providers/provider_name.dart';
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
  /// For [chat] this bounds each attempt, and an attempt that times out is
  /// aborted (through [AiRequest.abortTrigger]), so the provider stops
  /// generating it. For [stream] it bounds the gap between consecutive
  /// chunks (an idle timeout), so long streams that keep producing output
  /// are not cut off; a stream that times out is cancelled.
  final Duration? timeout;

  /// The retry policy. Defaults to exponential backoff with up to 3 retries.
  ///
  /// Use [AiRetryPolicy.none] to disable retries.
  final AiRetryPolicy retryPolicy;

  /// The logger used for debugging and info.
  ///
  /// Besides the request log lines, it receives one-time warnings, for
  /// example when an Anthropic model does not accept `temperature`/`topP`
  /// and they are omitted.
  final AiLogger? logger;

  /// The cache used to store and retrieve identical requests.
  ///
  /// Keys include the provider and its endpoint, so one cache can be shared
  /// by several clients.
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
    if (cache case final cache?)
      CacheMiddleware(cache, namespace: providerNamespace(provider)),
    if (retryPolicy.maxAttempts > 0)
      RetryMiddleware(policy: retryPolicy, logger: logger),
  ];

  /// [middlewares] is read on every call so later additions take effect.
  List<AiMiddleware> get _allMiddlewares =>
      [...middlewares, ..._builtInMiddlewares];

  String get _providerName => providerName(provider);

  /// Warnings already logged by [_warnIfSamplingOmitted].
  final Set<String> _samplingWarnings = {};

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
  /// Completing [abortTrigger] cancels the call: the HTTP request is
  /// aborted and the call fails with [AiTimeoutException] (and is not
  /// retried). See [AiRequest.abortTrigger].
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
    Future<void>? abortTrigger,
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
      abortTrigger: abortTrigger,
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
  /// the underlying HTTP request. So does completing [abortTrigger], which
  /// ends the stream with an [AiTimeoutException].
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
    Future<void>? abortTrigger,
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
      abortTrigger: abortTrigger,
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
    Future<void>? abortTrigger,
  }) {
    return stream(
      messages: messages,
      model: model,
      maxTokens: maxTokens,
      temperature: temperature,
      topP: topP,
      stop: stop,
      abortTrigger: abortTrigger,
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
  /// [abortTrigger] cancels the call, as for [chat].
  ///
  /// Throws [AiStructuredOutputException] if JSON extraction or decoding fails.
  Future<T> generate<T>({
    required String prompt,
    required AiJsonSchema schema,
    required T Function(Map<String, dynamic> json) decoder,
    String? model,
    int? maxTokens,
    double? temperature,
    Future<void>? abortTrigger,
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
      abortTrigger: abortTrigger,
    );

    final text = response.text;

    final Map<String, dynamic> decoded;
    final String jsonStr;
    switch (_firstJsonObject(text)) {
      case (final json, final source):
        decoded = json;
        jsonStr = source;
      case null:
        final refused = response.finishReason == AiFinishReason.contentFilter;
        throw AiStructuredOutputException(
          refused
              ? 'The model refused the request or its output was filtered '
                  '(finish reason: contentFilter); see rawResponse'
              : text.contains('{')
                  ? 'Failed to decode JSON: no valid JSON object in response'
                  : 'Failed to extract JSON from response',
          provider: _providerName,
          rawResponse: text,
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

  /// Returns the first balanced `{...}` in [text] that decodes to a JSON
  /// object, with its source, or `null`.
  ///
  /// Braces inside JSON strings are skipped, and each `{` is tried in turn,
  /// so prose before or after the object (even with braces) is ignored.
  static (Map<String, dynamic>, String)? _firstJsonObject(String text) {
    for (var start = text.indexOf('{');
        start != -1;
        start = text.indexOf('{', start + 1)) {
      final end = _matchingBrace(text, start);
      if (end == -1) continue;
      final source = text.substring(start, end + 1);
      try {
        final decoded = jsonDecode(source);
        if (decoded is Map<String, dynamic>) return (decoded, source);
      } on FormatException {
        // Not JSON; try the next brace.
      }
    }
    return null;
  }

  /// The index of the `}` closing the `{` at [start], or -1.
  static int _matchingBrace(String text, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final c = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (c == r'\') {
          escaped = true;
        } else if (c == '"') {
          inString = false;
        }
      } else if (c == '"') {
        inString = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}') {
        if (--depth == 0) return i;
      }
    }
    return -1;
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
    _warnIfSamplingOmitted(request);
    final timeout = this.timeout;
    if (timeout == null) return provider.chat(request);

    // A fresh trigger per attempt, combined with the caller's own trigger,
    // so a timed-out attempt is aborted instead of running (and being
    // billed) in the background.
    final abort = Completer<void>();
    void fire() {
      if (!abort.isCompleted) abort.complete();
    }

    if (request.abortTrigger case final trigger?) {
      unawaited(trigger.then((_) => fire(), onError: (Object _) => fire()));
    }

    return provider.chat(request.copyWith(abortTrigger: abort.future)).timeout(
      timeout,
      onTimeout: () {
        fire();
        throw AiTimeoutException(
          'Request timed out after ${_describe(timeout)}',
          provider: _providerName,
        );
      },
    );
  }

  Stream<AiStreamChunk> _executeProviderStream(AiRequest request) {
    _warnIfSamplingOmitted(request);
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

  /// Logs once per model (and case) when an Anthropic model will not
  /// receive the request's `temperature`/`topP` (see `AnthropicProvider`).
  void _warnIfSamplingOmitted(AiRequest request) {
    final logger = this.logger;
    final Object provider = this.provider;
    if (logger == null || provider is! AnthropicProvider) return;
    final temperature = request.temperature != null;
    final topP = request.topP != null;
    if (!temperature && !topP) return;
    final model = request.model ?? AnthropicProvider.defaultModel;
    final sent = anthropicSamplingToSend(model, provider.apiVersion,
        temperature: temperature, topP: topP);
    final omitted = [
      if (temperature && !sent.temperature) 'temperature',
      if (topP && !sent.topP) 'topP',
    ];
    if (omitted.isEmpty) return;
    // One warning per model and reason, whichever parameter triggered it.
    if (!_samplingWarnings.add('$model|${sent.temperature}')) return;
    final reason = sent.temperature
        ? 'accepts only one of temperature/topP per request'
        : 'does not accept sampling parameters on Anthropic API version '
            '${provider.apiVersion}';
    logger.warning('$model $reason; ${omitted.join(' and ')} '
        '${omitted.length == 1 ? 'was' : 'were'} omitted from the request. '
        'This warning is shown once per model.');
  }

  static String _describe(Duration d) => d.inMilliseconds % 1000 == 0
      ? '${d.inSeconds} seconds'
      : '${d.inMilliseconds} ms';
}
