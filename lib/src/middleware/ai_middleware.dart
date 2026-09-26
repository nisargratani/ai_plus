import '../core/ai_request.dart';
import '../core/ai_response.dart';
import '../core/ai_stream.dart';

/// Represents a function that handles an AI request and returns an AI response.
typedef AiRequestHandler = Future<AiResponse> Function(AiRequest request);

/// Represents a function that handles an AI streaming request.
typedef AiStreamHandler = Stream<AiStreamChunk> Function(AiRequest request);

/// Middleware to intercept and modify requests and responses.
///
/// Both methods pass the request through unchanged by default, so a
/// middleware that `extends AiMiddleware` only needs to override the one it
/// cares about:
///
/// ```dart
/// class ModelLoggerMiddleware extends AiMiddleware {
///   @override
///   Future<AiResponse> handleChat(AiRequest request, AiRequestHandler next) {
///     print('model: ${request.model}');
///     return next(request);
///   }
/// }
/// ```
///
/// Classes may also `implements AiMiddleware`, in which case both methods
/// must be provided.
abstract class AiMiddleware {
  /// Base constructor for subclasses.
  const AiMiddleware();

  /// Intercepts a standard chat request.
  Future<AiResponse> handleChat(AiRequest request, AiRequestHandler next) {
    return next(request);
  }

  /// Intercepts a streaming request.
  Stream<AiStreamChunk> handleStream(AiRequest request, AiStreamHandler next) {
    return next(request);
  }
}
