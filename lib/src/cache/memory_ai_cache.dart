import 'dart:async';
import '../core/ai_response.dart';
import 'ai_cache.dart';

class _CacheEntry {
  final AiResponse response;
  final DateTime expiresAt;

  _CacheEntry({required this.response, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// A simple in-memory implementation of [AiCache].
class MemoryAiCache implements AiCache {
  final Duration ttl;
  final Map<String, _CacheEntry> _store = {};

  MemoryAiCache({this.ttl = const Duration(minutes: 60)});

  @override
  Future<AiResponse?> get(String key) async {
    final entry = _store[key];
    if (entry == null) return null;

    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }

    return entry.response;
  }

  @override
  Future<void> set(String key, AiResponse response) async {
    _store[key] = _CacheEntry(
      response: response,
      expiresAt: DateTime.now().add(ttl),
    );
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
