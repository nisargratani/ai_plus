import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../cache/ai_cache.dart';
import '../core/ai_request.dart';
import '../core/ai_response.dart';
import '../core/ai_stream.dart';
import '../models/ai_content.dart';
import 'ai_middleware.dart';

/// Middleware that caches chat responses to avoid redundant network requests.
///
/// The cache key is a SHA-256 digest of every field that affects the
/// response: model, sampling parameters, stop sequences, tools, schema and
/// the full content of every message (including images and tool calls).
/// Keys are stable across processes, so persistent [AiCache]
/// implementations work as expected.
///
/// Streaming requests are not cached.
class CacheMiddleware implements AiMiddleware {
  /// The cache that responses are stored in.
  final AiCache cache;

  /// Creates a cache middleware backed by [cache].
  const CacheMiddleware(this.cache);

  @override
  Future<AiResponse> handleChat(
      AiRequest request, AiRequestHandler next) async {
    final key = cacheKey(request);

    final cached = await cache.get(key);
    if (cached != null) return cached;

    final response = await next(request);
    await cache.set(key, response);

    return response;
  }

  @override
  Stream<AiStreamChunk> handleStream(AiRequest request, AiStreamHandler next) {
    return next(request);
  }

  /// Computes the deterministic cache key for [request].
  static String cacheKey(AiRequest request) {
    final canonical = jsonEncode({
      'model': request.model,
      'maxTokens': request.maxTokens,
      'temperature': request.temperature,
      'topP': request.topP,
      'stop': request.stop,
      'tools': [
        for (final t in request.tools ?? const [])
          [t.name, t.description, t.parameters.toJson()],
      ],
      'schema': request.schema?.toJson(),
      'messages': [
        for (final m in request.messages)
          [m.role.name, for (final c in m.content) _contentKey(c)],
      ],
    }, toEncodable: (o) => o.toString());
    return 'ai_plus:v1:${sha256.convert(utf8.encode(canonical))}';
  }

  static Object? _contentKey(AiContent content) {
    switch (content) {
      case AiTextContent(:final text):
        return ['text', text];
      case AiImageContent(:final mimeType, :final bytes):
        return ['image', mimeType, sha256.convert(bytes).toString()];
      case AiAudioContent(:final mimeType, :final bytes):
        return ['audio', mimeType, sha256.convert(bytes).toString()];
      case AiFileContent(:final mimeType, :final bytes):
        return ['file', mimeType, sha256.convert(bytes).toString()];
      case AiToolCallContent(:final id, :final name, :final arguments):
        return ['tool_call', id, name, arguments];
      case AiToolResultContent(:final id, :final name, :final result):
        return ['tool_result', id, name, result, content.isError];
    }
  }
}
