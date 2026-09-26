import 'dart:collection';

import '../core/ai_response.dart';
import 'ai_cache.dart';

class _CacheEntry {
  final AiResponse response;
  final DateTime expiresAt;

  _CacheEntry({required this.response, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// A simple in-memory implementation of [AiCache] with TTL expiry and an
/// optional size limit.
///
/// ```dart
/// final cache = MemoryAiCache(
///   ttl: const Duration(minutes: 30),
///   maxEntries: 500,
/// );
/// ```
class MemoryAiCache implements AiCache {
  /// How long an entry remains valid after it is stored.
  final Duration ttl;

  /// The maximum number of entries kept, or `null` for no limit.
  ///
  /// When the limit is exceeded the least recently used entry is evicted.
  /// Set a limit in long-running apps to bound memory usage.
  final int? maxEntries;

  // Insertion order doubles as recency order (entries are re-inserted on
  // access), giving O(1) LRU eviction.
  final LinkedHashMap<String, _CacheEntry> _store = LinkedHashMap();

  /// Creates an in-memory cache.
  MemoryAiCache({this.ttl = const Duration(minutes: 60), this.maxEntries})
      : assert(maxEntries == null || maxEntries > 0,
            'maxEntries must be positive');

  /// The number of entries currently stored (including expired entries that
  /// have not been evicted yet).
  int get length => _store.length;

  @override
  Future<AiResponse?> get(String key) async {
    final entry = _store.remove(key);
    if (entry == null || entry.isExpired) return null;

    _store[key] = entry; // Mark as most recently used.
    return entry.response;
  }

  @override
  Future<void> set(String key, AiResponse response) async {
    _store.remove(key);
    _store[key] = _CacheEntry(
      response: response,
      expiresAt: DateTime.now().add(ttl),
    );

    final limit = maxEntries;
    if (limit != null && _store.length > limit) {
      _store.removeWhere((_, entry) => entry.isExpired);
      while (_store.length > limit) {
        _store.remove(_store.keys.first);
      }
    }
  }

  @override
  Future<void> remove(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }
}
