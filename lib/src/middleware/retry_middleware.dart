import '../core/ai_request.dart';
import '../core/ai_response.dart';
import '../core/ai_stream.dart';
import '../errors/ai_exception.dart';
import '../logging/ai_logger.dart';
import '../retry/retry_policy.dart';
import 'ai_middleware.dart';

/// Middleware that handles retrying requests based on an [AiRetryPolicy].
class RetryMiddleware implements AiMiddleware {
  final AiRetryPolicy policy;
  final AiLogger? logger;

  const RetryMiddleware({
    required this.policy,
    this.logger,
  });

  @override
  Future<AiResponse> handleChat(
      AiRequest request, AiRequestHandler next) async {
    int attempt = 0;
    while (true) {
      try {
        return await next(request);
      } catch (e) {
        if (!_shouldRetry(e) || attempt >= policy.maxAttempts) {
          rethrow;
        }

        final delay = _getRetryDelay(e, attempt);
        logger?.warning(
            'Request failed, retrying in ${delay.inMilliseconds}ms (Attempt ${attempt + 1}/${policy.maxAttempts}): $e');

        await Future<void>.delayed(delay);
        attempt++;
      }
    }
  }

  @override
  Stream<AiStreamChunk> handleStream(
      AiRequest request, AiStreamHandler next) async* {
    int attempt = 0;
    while (true) {
      try {
        // Yield* doesn't cleanly allow catching errors inside the stream to trigger a full retry
        // once it has started emitting. We retry if the stream fails immediately upon creation.
        // For partial stream failures, advanced resumption is needed, which is out of scope for V1.
        yield* next(request);
        return;
      } catch (e) {
        if (!_shouldRetry(e) || attempt >= policy.maxAttempts) {
          rethrow;
        }

        final delay = _getRetryDelay(e, attempt);
        logger?.warning(
            'Stream request failed, retrying in ${delay.inMilliseconds}ms (Attempt ${attempt + 1}/${policy.maxAttempts}): $e');

        await Future<void>.delayed(delay);
        attempt++;
      }
    }
  }

  bool _shouldRetry(Object error) {
    if (error is AiRateLimitException) return true;
    if (error is AiTimeoutException) return true;
    if (error is AiNetworkException) return true;
    if (error is AiProviderException) {
      // Typically retry 5xx errors
      return error.statusCode != null && error.statusCode! >= 500;
    }
    return false;
  }

  Duration _getRetryDelay(Object error, int attempt) {
    if (error is AiRateLimitException && error.retryAfter != null) {
      return error.retryAfter!;
    }
    return policy.calculateDelay(attempt);
  }
}
