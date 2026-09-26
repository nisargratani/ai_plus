/// Base class for all AI exceptions in the SDK.
///
/// All exceptions thrown by the `ai_plus` package extend this class,
/// providing a consistent interface for error handling.
///
/// ```dart
/// try {
///   final response = await ai.chat(messages: [...]);
/// } on AiRateLimitException catch (e) {
///   print('Rate limited. Retry after: ${e.retryAfter}');
/// } on AiAuthenticationException catch (e) {
///   print('Bad API key');
/// } on AiException catch (e) {
///   print('AI error: ${e.message}');
/// }
/// ```
abstract class AiException implements Exception {
  /// A human-readable description of the error.
  final String message;

  /// The provider that originated the error (if known).
  final String? provider;

  /// The HTTP status code associated with the error (if applicable).
  final int? statusCode;

  /// A unique identifier for the request that caused the error (if available).
  final String? requestId;

  /// Creates an exception with a human-readable [message].
  const AiException(
    this.message, {
    this.provider,
    this.statusCode,
    this.requestId,
  });

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (provider != null) buffer.write(' (Provider: $provider)');
    if (statusCode != null) buffer.write(' [Status: $statusCode]');
    if (requestId != null) buffer.write(' {Request ID: $requestId}');
    return buffer.toString();
  }
}

/// Thrown when authentication with the AI provider fails (e.g. invalid API key).
///
/// Typically corresponds to HTTP 401.
class AiAuthenticationException extends AiException {
  /// Creates an [AiAuthenticationException].
  const AiAuthenticationException(
    super.message, {
    super.provider,
    super.statusCode,
    super.requestId,
  });
}

/// Thrown when the authenticated user lacks permission for the requested resource.
///
/// Typically corresponds to HTTP 403.
class AiAuthorizationException extends AiException {
  /// Creates an [AiAuthorizationException].
  const AiAuthorizationException(
    super.message, {
    super.provider,
    super.statusCode,
    super.requestId,
  });
}

/// Thrown when the provider rate limits the request.
///
/// Check [retryAfter] for a provider-suggested wait duration (parsed from the
/// `retry-after` / `retry-after-ms` response headers when present).
class AiRateLimitException extends AiException {
  /// The duration to wait before retrying, if provided by the provider.
  final Duration? retryAfter;

  /// Creates an [AiRateLimitException].
  const AiRateLimitException(
    super.message, {
    super.provider,
    super.statusCode,
    super.requestId,
    this.retryAfter,
  });
}

/// Thrown when a network request to the provider fails.
///
/// This includes connection errors, DNS resolution failures, etc.
class AiNetworkException extends AiException {
  /// Creates an [AiNetworkException].
  const AiNetworkException(
    super.message, {
    super.provider,
    super.statusCode,
    super.requestId,
  });
}

/// Thrown when a request to the provider times out.
///
/// Raised either by the client-side `AiClient.timeout` or when the provider
/// responds with HTTP 408.
class AiTimeoutException extends AiException {
  /// Creates an [AiTimeoutException].
  const AiTimeoutException(
    super.message, {
    super.provider,
    super.statusCode,
    super.requestId,
  });
}

/// Thrown when the request is invalid (e.g. malformed parameters).
///
/// Typically corresponds to HTTP 400.
class AiInvalidRequestException extends AiException {
  /// Creates an [AiInvalidRequestException].
  const AiInvalidRequestException(
    super.message, {
    super.provider,
    super.statusCode,
    super.requestId,
  });
}

/// Thrown when a generic provider error occurs (e.g. server error).
///
/// Typically corresponds to HTTP 5xx errors.
class AiProviderException extends AiException {
  /// Creates an [AiProviderException].
  const AiProviderException(
    super.message, {
    super.provider,
    super.statusCode,
    super.requestId,
  });
}

/// Thrown when the SDK fails to parse the provider's response.
class AiParsingException extends AiException {
  /// The raw string that failed to parse.
  final String? rawResponse;

  /// Creates an [AiParsingException].
  const AiParsingException(
    super.message, {
    super.provider,
    this.rawResponse,
  });
}

/// Thrown when the content is filtered by the provider's safety systems.
///
/// For example, when Gemini blocks a prompt and returns no candidates.
class AiContentFilterException extends AiException {
  /// Creates an [AiContentFilterException].
  const AiContentFilterException(
    super.message, {
    super.provider,
    super.statusCode,
    super.requestId,
  });
}

/// Thrown when attempting to use a capability that the current provider does not support.
class AiUnsupportedCapabilityException extends AiException {
  /// Creates an [AiUnsupportedCapabilityException].
  const AiUnsupportedCapabilityException(
    super.message, {
    super.provider,
  });
}

/// Thrown when structured output extraction or validation fails.
///
/// This can occur when the AI model returns text that cannot be parsed
/// as valid JSON, or when the parsed JSON does not match the expected schema.
class AiStructuredOutputException extends AiException {
  /// The raw response text that failed to parse or validate.
  final String? rawResponse;

  /// Creates an [AiStructuredOutputException].
  const AiStructuredOutputException(
    super.message, {
    super.provider,
    this.rawResponse,
  });
}

/// Thrown when the AI model attempts to call a tool that is not registered.
class AiToolNotFoundException extends AiException {
  /// Creates an [AiToolNotFoundException].
  const AiToolNotFoundException(
    super.message, {
    super.provider,
  });
}

/// Thrown when the execution of a tool fails.
class AiToolException extends AiException {
  /// Creates an [AiToolException].
  const AiToolException(
    super.message, {
    super.provider,
  });
}
