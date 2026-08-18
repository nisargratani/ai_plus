import 'dart:convert';
import 'package:http/http.dart' as http;
import '../errors/ai_exception.dart';

/// A lightweight HTTP abstraction used internally by providers.
///
/// This avoids coupling the core package heavily to any specific library like Dio,
/// but still provides a consistent way to handle JSON, errors, and streaming.
///
/// Providers receive an optional [AiHttpClient] for testability — tests can inject
/// a mock [http.Client] to simulate any HTTP response scenario.
class AiHttpClient {
  final http.Client _client;

  /// Creates an HTTP client.
  ///
  /// An optional [client] can be provided for testing purposes.
  AiHttpClient({http.Client? client}) : _client = client ?? http.Client();

  /// Performs a POST request and returns the decoded JSON map.
  ///
  /// Throws typed [AiException] subclasses for HTTP error codes.
  Future<Map<String, dynamic>> post(
    Uri url, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    try {
      final response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          ...?headers,
        },
        body: body != null ? jsonEncode(body) : null,
      );

      return _processResponse(response);
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiNetworkException('Failed to connect to ${url.host}: $e');
    }
  }

  /// Performs a POST request and streams back the response body as strings.
  ///
  /// Useful for Server-Sent Events (SSE) streaming responses.
  Stream<String> postStream(
    Uri url, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async* {
    try {
      final request = http.Request('POST', url);
      request.headers.addAll({
        'Content-Type': 'application/json',
        ...?headers,
      });
      if (body != null) {
        request.body = jsonEncode(body);
      }

      final response = await _client.send(request);

      if (response.statusCode >= 400) {
        final errorBody = await response.stream.bytesToString();
        _throwForStatusCode(response.statusCode, errorBody);
      }

      yield* response.stream.transform(utf8.decoder);
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiNetworkException('Failed to connect to ${url.host}: $e');
    }
  }

  /// Closes the HTTP client and releases resources.
  void close() {
    _client.close();
  }

  Map<String, dynamic> _processResponse(http.Response response) {
    if (response.statusCode >= 400) {
      _throwForStatusCode(response.statusCode, response.body);
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw AiParsingException(
        'Failed to parse JSON response',
        rawResponse: response.body,
      );
    }
  }

  Never _throwForStatusCode(int statusCode, String body) {
    switch (statusCode) {
      case 401:
        throw AiAuthenticationException(
          'Authentication failed',
          statusCode: statusCode,
        );
      case 403:
        throw AiAuthorizationException(
          'Authorization failed: insufficient permissions',
          statusCode: statusCode,
        );
      case 429:
        throw AiRateLimitException(
          'Rate limit exceeded',
          statusCode: statusCode,
        );
      default:
        if (statusCode >= 500) {
          throw AiProviderException(
            'Provider server error',
            statusCode: statusCode,
          );
        }
        throw AiInvalidRequestException(
          'Invalid request: $body',
          statusCode: statusCode,
        );
    }
  }
}
