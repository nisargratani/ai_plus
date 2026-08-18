import '../core/ai_response.dart';

/// The interface for caching AI responses.
abstract interface class AiCache {
  /// Retrieves a cached response for the given key.
  Future<AiResponse?> get(String key);

  /// Caches a response with the given key.
  Future<void> set(String key, AiResponse response);

  /// Removes a cached response for the given key.
  Future<void> remove(String key);

  /// Clears the entire cache.
  Future<void> clear();
}
