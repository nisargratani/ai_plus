import '../core/ai_request.dart';
import '../core/ai_response.dart';
import '../core/ai_stream.dart';
import '../logging/ai_logger.dart';
import 'ai_middleware.dart';

/// Middleware that logs incoming requests and outgoing responses.
class LoggingMiddleware implements AiMiddleware {
  final AiLogger logger;

  const LoggingMiddleware(this.logger);

  @override
  Future<AiResponse> handleChat(
      AiRequest request, AiRequestHandler next) async {
    logger.info('Sending chat request to model: ${request.model ?? "default"}');

    try {
      final response = await next(request);
      logger.info(
          'Received chat response. Finish reason: ${response.finishReason.name}');
      return response;
    } catch (e) {
      logger.error('Chat request failed: $e');
      rethrow;
    }
  }

  @override
  Stream<AiStreamChunk> handleStream(AiRequest request, AiStreamHandler next) {
    logger.info(
        'Starting stream request to model: ${request.model ?? "default"}');

    // We don't log every chunk here to avoid flooding, just the start and errors
    return next(request).handleError((Object e, StackTrace st) {
      logger.error('Stream request failed: $e');
      Error.throwWithStackTrace(e, st);
    });
  }
}
