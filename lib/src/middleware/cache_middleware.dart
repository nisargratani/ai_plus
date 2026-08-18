import '../core/ai_request.dart';
import '../core/ai_response.dart';
import '../core/ai_stream.dart';
import '../cache/ai_cache.dart';
import 'ai_middleware.dart';

/// Middleware that caches responses to avoid redundant network requests.
class CacheMiddleware implements AiMiddleware {
  final AiCache cache;

  const CacheMiddleware(this.cache);

  @override
  Future<AiResponse> handleChat(
      AiRequest request, AiRequestHandler next) async {
    // Generate a deterministic cache key. For V1, we stringify the request messages.
    // In a real scenario, this should hash model, messages, temperature, etc.
    final key = _generateCacheKey(request);

    final cached = await cache.get(key);
    if (cached != null) return cached;

    final response = await next(request);
    await cache.set(key, response);

    return response;
  }

  @override
  Stream<AiStreamChunk> handleStream(AiRequest request, AiStreamHandler next) {
    // We typically do not cache streaming responses in V1 due to complexity of replaying streams.
    return next(request);
  }

  String _generateCacheKey(AiRequest request) {
    final buffer = StringBuffer();
    buffer.write('model:${request.model};');
    for (final m in request.messages) {
      buffer.write('${m.role.name}:${m.text};');
    }
    return buffer.toString().hashCode.toString();
  }
}
