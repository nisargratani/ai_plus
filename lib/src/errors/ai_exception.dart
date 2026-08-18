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
  const AiAuthorizationException(
    super.message, {
    super.provider,
    super.statusCode,
    super.requestId,
  });
}

/// Thrown when the provider rate limits the request.
///
/// Check [retryAfter] for a provider-suggested wait duration.
class AiRateLimitException extends AiException {
  /// The duration to wait before retrying, if provided by the provider.
  final Duration? retryAfter;

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
  const AiNetworkException(
    super.message, {
    super.provider,
  });
}

/// Thrown when a request to the provider times out.
class AiTimeoutException extends AiException {
  const AiTimeoutException(
    super.message, {
    super.provider,
  });
}

/// Thrown when the request is invalid (e.g. malformed parameters).
///
/// Typically corresponds to HTTP 400.
class AiInvalidRequestException extends AiException {
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

  const AiParsingException(
    super.message, {
    super.provider,
    this.rawResponse,
  });
}

/// Thrown when the content is filtered by the provider's safety systems.
class AiContentFilterException extends AiException {
  const AiContentFilterException(
    super.message, {
    super.provider,
    super.statusCode,
    super.requestId,
  });
}

/// Thrown when attempting to use a capability that the current provider does not support.
class AiUnsupportedCapabilityException extends AiException {
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

  const AiStructuredOutputException(
    super.message, {
    super.provider,
    this.rawResponse,
  });
}

/// Thrown when the AI model attempts to call a tool that is not registered.
class AiToolNotFoundException extends AiException {
  const AiToolNotFoundException(
    super.message, {
    super.provider,
  });
}

/// Thrown when the execution of a tool fails.
class AiToolException extends AiException {
  const AiToolException(
    super.message, {
    super.provider,
  });
}
