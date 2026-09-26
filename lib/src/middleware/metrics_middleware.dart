import '../core/ai_request.dart';
import '../core/ai_response.dart';
import '../core/ai_stream.dart';
import 'ai_middleware.dart';

/// Middleware that tracks request metrics such as count, latency, and errors.
///
/// Counts logical requests: when placed in `AiClient.middlewares` it runs
/// before the retry middleware, so retried attempts count once.
///
/// ```dart
/// final metrics = MetricsMiddleware();
/// final ai = AiClient(
///   provider: provider,
///   middlewares: [metrics],
/// );
///
/// // After some requests...
/// print('Total requests: ${metrics.requestCount}');
/// print('Error count: ${metrics.errorCount}');
/// ```
class MetricsMiddleware implements AiMiddleware {
  /// Creates a metrics middleware with all counters at zero.
  MetricsMiddleware();

  int _requestCount = 0;
  int _errorCount = 0;
  Duration _totalLatency = Duration.zero;

  /// The total number of requests processed.
  int get requestCount => _requestCount;

  /// The total number of requests that resulted in an error.
  int get errorCount => _errorCount;

  /// The total accumulated latency across all requests.
  Duration get totalLatency => _totalLatency;

  /// The average latency per request.
  Duration get averageLatency {
    if (_requestCount == 0) return Duration.zero;
    return Duration(
      microseconds: _totalLatency.inMicroseconds ~/ _requestCount,
    );
  }

  /// Resets all metrics.
  void reset() {
    _requestCount = 0;
    _errorCount = 0;
    _totalLatency = Duration.zero;
  }

  @override
  Future<AiResponse> handleChat(
      AiRequest request, AiRequestHandler next) async {
    _requestCount++;
    final stopwatch = Stopwatch()..start();

    try {
      return await next(request);
    } catch (_) {
      _errorCount++;
      rethrow;
    } finally {
      _totalLatency += stopwatch.elapsed;
    }
  }

  /// Counts the stream as one request; its latency is measured until the
  /// stream completes, fails or is cancelled.
  @override
  Stream<AiStreamChunk> handleStream(
      AiRequest request, AiStreamHandler next) async* {
    _requestCount++;
    final stopwatch = Stopwatch()..start();

    try {
      // `await for` (unlike `yield*`) rethrows stream errors here.
      await for (final chunk in next(request)) {
        yield chunk;
      }
    } catch (_) {
      _errorCount++;
      rethrow;
    } finally {
      _totalLatency += stopwatch.elapsed;
    }
  }
}
