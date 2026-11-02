import 'dart:async';

import '../core/ai_request.dart';
import '../core/ai_response.dart';
import '../core/ai_stream.dart';
import '../errors/ai_exception.dart';
import '../logging/ai_logger.dart';
import '../retry/retry_policy.dart';
import 'ai_middleware.dart';

/// Middleware that handles retrying requests based on an [AiRetryPolicy].
///
/// Retries rate-limit (429), timeout, network and 5xx errors. The delay
/// honours the provider's `retry-after` hint (on 429 and 5xx responses) when
/// present, capped at [AiRetryPolicy.maxDelay].
///
/// A request whose [AiRequest.abortTrigger] has completed is not retried.
///
/// Streams are retried only if they fail before emitting their first chunk;
/// once output has been delivered, replaying it would duplicate content, so
/// the error is propagated instead.
class RetryMiddleware implements AiMiddleware {
  /// The policy controlling attempts and backoff.
  final AiRetryPolicy policy;

  /// Optional logger notified before each retry.
  final AiLogger? logger;

  /// Creates a retry middleware.
  const RetryMiddleware({
    required this.policy,
    this.logger,
  });

  @override
  Future<AiResponse> handleChat(
      AiRequest request, AiRequestHandler next) async {
    final aborted = _watchAbort(request);
    var attempt = 0;
    while (true) {
      try {
        return await next(request);
      } catch (e) {
        if (aborted() || !_shouldRetry(e) || attempt >= policy.maxAttempts) {
          rethrow;
        }
        await _backoff(e, attempt++, 'Request');
      }
    }
  }

  @override
  Stream<AiStreamChunk> handleStream(
      AiRequest request, AiStreamHandler next) async* {
    final aborted = _watchAbort(request);
    var attempt = 0;
    while (true) {
      var emitted = false;
      try {
        await for (final chunk in next(request)) {
          emitted = true;
          yield chunk;
        }
        return;
      } catch (e) {
        if (emitted ||
            aborted() ||
            !_shouldRetry(e) ||
            attempt >= policy.maxAttempts) {
          rethrow;
        }
        await _backoff(e, attempt++, 'Stream request');
      }
    }
  }

  /// Returns a function telling whether [request]'s abort trigger fired.
  static bool Function() _watchAbort(AiRequest request) {
    final trigger = request.abortTrigger;
    if (trigger == null) return () => false;
    var fired = false;
    void markFired() => fired = true;
    unawaited(trigger.then((_) => markFired(), onError: (Object _) {
      markFired();
    }));
    return () => fired;
  }

  Future<void> _backoff(Object error, int attempt, String what) {
    final delay = _getRetryDelay(error, attempt);
    logger?.warning('$what failed, retrying in ${delay.inMilliseconds}ms '
        '(Attempt ${attempt + 1}/${policy.maxAttempts}): $error');
    return Future<void>.delayed(delay);
  }

  bool _shouldRetry(Object error) {
    if (error is AiRateLimitException) return true;
    if (error is AiTimeoutException) return true;
    if (error is AiNetworkException) return true;
    if (error is AiProviderException) {
      // Errors without a status (e.g. mid-stream errors) are not retried.
      final status = error.statusCode;
      return status != null && status >= 500;
    }
    return false;
  }

  Duration _getRetryDelay(Object error, int attempt) {
    final retryAfter = switch (error) {
      AiRateLimitException(:final retryAfter) => retryAfter,
      AiProviderException(:final retryAfter) => retryAfter,
      _ => null,
    };
    if (retryAfter != null) {
      return retryAfter > policy.maxDelay ? policy.maxDelay : retryAfter;
    }
    return policy.calculateDelay(attempt);
  }
}
