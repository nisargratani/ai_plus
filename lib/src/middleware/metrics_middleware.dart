import '../core/ai_request.dart';
import '../core/ai_response.dart';
import '../core/ai_stream.dart';
import 'ai_middleware.dart';

/// Middleware that tracks request metrics such as count, latency, and errors.
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
      final response = await next(request);
      stopwatch.stop();
      _totalLatency += stopwatch.elapsed;
      return response;
    } catch (e) {
      stopwatch.stop();
      _totalLatency += stopwatch.elapsed;
      _errorCount++;
      rethrow;
    }
  }

  @override
  Stream<AiStreamChunk> handleStream(AiRequest request, AiStreamHandler next) {
    _requestCount++;
    return next(request);
  }
}
