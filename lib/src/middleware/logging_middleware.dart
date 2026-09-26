import '../core/ai_request.dart';
import '../core/ai_response.dart';
import '../core/ai_stream.dart';
import '../logging/ai_logger.dart';
import 'ai_middleware.dart';

/// Middleware that logs request metadata, latency and failures.
///
/// Message contents and API keys are never logged.
class LoggingMiddleware implements AiMiddleware {
  /// The logger that receives the log lines.
  final AiLogger logger;

  /// Creates a logging middleware writing to [logger].
  const LoggingMiddleware(this.logger);

  @override
  Future<AiResponse> handleChat(
      AiRequest request, AiRequestHandler next) async {
    logger.info('Sending chat request to model: ${request.model ?? "default"}');
    final stopwatch = Stopwatch()..start();

    try {
      final response = await next(request);
      logger.info('Received chat response in ${stopwatch.elapsedMilliseconds}'
          'ms. Finish reason: ${response.finishReason.name}');
      return response;
    } catch (e, st) {
      logger.error(
        'Chat request failed after ${stopwatch.elapsedMilliseconds}ms: $e',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }

  @override
  Stream<AiStreamChunk> handleStream(
      AiRequest request, AiStreamHandler next) async* {
    logger.info(
        'Starting stream request to model: ${request.model ?? "default"}');
    final stopwatch = Stopwatch()..start();

    // Individual chunks are not logged to avoid flooding the output.
    try {
      // `await for` (unlike `yield*`) rethrows stream errors here.
      await for (final chunk in next(request)) {
        yield chunk;
      }
      logger.debug('Stream completed in ${stopwatch.elapsedMilliseconds}ms');
    } catch (e, st) {
      logger.error(
        'Stream request failed after ${stopwatch.elapsedMilliseconds}ms: $e',
        error: e,
        stackTrace: st,
      );
      rethrow;
    }
  }
}
