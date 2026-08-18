import '../core/ai_request.dart';
import '../core/ai_response.dart';
import '../core/ai_stream.dart';

/// Represents a function that handles an AI request and returns an AI response.
typedef AiRequestHandler = Future<AiResponse> Function(AiRequest request);

/// Represents a function that handles an AI streaming request.
typedef AiStreamHandler = Stream<AiStreamChunk> Function(AiRequest request);

/// Middleware interface to intercept and modify requests and responses.
abstract interface class AiMiddleware {
  /// Intercepts a standard chat request.
  Future<AiResponse> handleChat(AiRequest request, AiRequestHandler next) {
    return next(request);
  }

  /// Intercepts a streaming request.
  Stream<AiStreamChunk> handleStream(AiRequest request, AiStreamHandler next) {
    return next(request);
  }
}
