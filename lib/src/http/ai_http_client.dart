import 'dart:convert';

import 'package:http/http.dart' as http;

import '../errors/ai_exception.dart';

/// A lightweight HTTP abstraction used by the built-in providers.
///
/// It centralises JSON encoding, Server-Sent Events (SSE) parsing and the
/// mapping of HTTP failures to typed [AiException]s, without coupling the
/// package to a heavier HTTP library.
///
/// Inject a custom [http.Client] to add proxies, certificate pinning, or to
/// mock responses in tests:
///
/// ```dart
/// final provider = OpenAiProvider(
///   apiKey: apiKey,
///   httpClient: AiHttpClient(client: MockClient((req) async => ...)),
/// );
/// ```
class AiHttpClient {
  final http.Client _client;

  /// Maximum number of characters of an error body kept in exception
  /// messages, to avoid dumping very large payloads into logs.
  static const _maxErrorBodyLength = 500;

  /// Creates an HTTP client.
  ///
  /// When [client] is omitted a default [http.Client] is created.
  AiHttpClient({http.Client? client}) : _client = client ?? http.Client();

  /// Performs a JSON POST request and returns the decoded JSON object.
  ///
  /// [provider] is attached to any thrown [AiException] for diagnostics.
  ///
  /// Throws a typed [AiException] subclass for HTTP errors, an
  /// [AiNetworkException] for transport failures and an [AiParsingException]
  /// when the body is not a JSON object.
  Future<Map<String, dynamic>> post(
    Uri url, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    String? provider,
  }) async {
    final encodedBody = body != null ? jsonEncode(body) : null;
    final http.Response response;
    try {
      response = await _client.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          ...?headers,
        },
        body: encodedBody,
      );
    } catch (e, st) {
      Error.throwWithStackTrace(_networkError(e, url, provider), st);
    }

    if (response.statusCode >= 400) {
      throw _errorForResponse(
        response.statusCode,
        response.body,
        response.headers,
        provider,
      );
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw AiParsingException(
        'Failed to parse JSON response',
        provider: provider,
        rawResponse: response.body,
      );
    }
  }

  /// Performs a JSON POST request and streams back the raw response body.
  ///
  /// The body is decoded as UTF-8 incrementally, so multi-byte characters
  /// split across network chunks are handled correctly.
  Stream<String> postStream(
    Uri url, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    String? provider,
  }) async* {
    final request = http.Request('POST', url)
      ..headers.addAll({
        'Content-Type': 'application/json',
        ...?headers,
      });
    if (body != null) {
      request.body = jsonEncode(body);
    }

    final http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (e, st) {
      Error.throwWithStackTrace(_networkError(e, url, provider), st);
    }

    if (response.statusCode >= 400) {
      final String errorBody;
      try {
        errorBody = await response.stream.bytesToString();
      } catch (e, st) {
        Error.throwWithStackTrace(_networkError(e, url, provider), st);
      }
      throw _errorForResponse(
        response.statusCode,
        errorBody,
        response.headers,
        provider,
      );
    }

    try {
      // `await for` (unlike `yield*`) rethrows stream errors here, so
      // mid-stream connection failures are mapped too.
      await for (final text in response.stream.transform(utf8.decoder)) {
        yield text;
      }
    } on http.ClientException catch (e, st) {
      Error.throwWithStackTrace(_networkError(e, url, provider), st);
    }
  }

  /// Performs a streaming POST request and yields the `data:` payloads of the
  /// Server-Sent Events it returns.
  ///
  /// Comment lines, `event:`/`id:`/`retry:` fields and blank lines are
  /// skipped. Both `data: value` and `data:value` forms are accepted, as are
  /// `\n` and `\r\n` line endings.
  Stream<String> postSse(
    Uri url, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
    String? provider,
  }) async* {
    final lines = postStream(
      url,
      headers: {'Accept': 'text/event-stream', ...?headers},
      body: body,
      provider: provider,
    ).transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      var data = line.substring(5);
      if (data.startsWith(' ')) data = data.substring(1);
      if (data.isEmpty) continue;
      yield data;
    }
  }

  /// Closes the underlying [http.Client] and releases its connections.
  void close() {
    _client.close();
  }

  AiNetworkException _networkError(Object error, Uri url, String? provider) {
    // `ClientException.toString()` includes the full URI, which may carry
    // credentials in its query string, so only its message is surfaced.
    final detail = error is http.ClientException ? error.message : '$error';
    return AiNetworkException(
      'Failed to connect to ${url.host}: $detail',
      provider: provider,
    );
  }

  AiException _errorForResponse(
    int statusCode,
    String body,
    Map<String, String> headers,
    String? provider,
  ) {
    final requestId = headers['x-request-id'] ?? headers['request-id'];
    final detail = _extractErrorMessage(body);
    String describe(String summary) =>
        detail.isEmpty ? summary : '$summary: $detail';

    switch (statusCode) {
      case 401:
        return AiAuthenticationException(
          describe('Authentication failed'),
          provider: provider,
          statusCode: statusCode,
          requestId: requestId,
        );
      case 403:
        return AiAuthorizationException(
          describe('Authorization failed'),
          provider: provider,
          statusCode: statusCode,
          requestId: requestId,
        );
      case 408:
        return AiTimeoutException(
          describe('Provider timed out'),
          provider: provider,
          statusCode: statusCode,
          requestId: requestId,
        );
      case 429:
        return AiRateLimitException(
          describe('Rate limit exceeded'),
          provider: provider,
          statusCode: statusCode,
          requestId: requestId,
          retryAfter: _parseRetryAfter(headers),
        );
    }
    if (statusCode >= 500) {
      return AiProviderException(
        describe('Provider server error'),
        provider: provider,
        statusCode: statusCode,
        requestId: requestId,
      );
    }
    return AiInvalidRequestException(
      describe('Invalid request'),
      provider: provider,
      statusCode: statusCode,
      requestId: requestId,
    );
  }

  /// Extracts a human-readable message from a provider error body.
  ///
  /// OpenAI, Anthropic and Gemini all use `{"error": {"message": "..."}}`;
  /// other OpenAI-compatible servers sometimes use `{"error": "..."}` or
  /// `{"message": "..."}`. Falls back to the (truncated) raw body.
  static String _extractErrorMessage(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        if (error is String) return error;
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } on FormatException {
      // Not JSON; fall through to the raw body.
    }
    return trimmed.length > _maxErrorBodyLength
        ? '${trimmed.substring(0, _maxErrorBodyLength)}…'
        : trimmed;
  }

  static Duration? _parseRetryAfter(Map<String, String> headers) {
    final ms = double.tryParse(headers['retry-after-ms'] ?? '');
    if (ms != null && ms >= 0) return Duration(milliseconds: ms.round());

    final seconds = double.tryParse(headers['retry-after'] ?? '');
    if (seconds != null && seconds >= 0) {
      return Duration(milliseconds: (seconds * 1000).round());
    }
    return null;
  }
}
