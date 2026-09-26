import 'package:ai_plus/ai_plus.dart';
import 'package:test/test.dart';

void main() {
  group('MemoryAiCache', () {
    late MemoryAiCache cache;

    setUp(() {
      cache = MemoryAiCache(ttl: const Duration(seconds: 2));
    });

    test('returns null for cache miss', () async {
      final result = await cache.get('nonexistent');
      expect(result, isNull);
    });

    test('returns response for cache hit', () async {
      final response = AiResponse(
        message: AiMessage.assistant('cached response'),
      );

      await cache.set('key1', response);
      final result = await cache.get('key1');

      expect(result, isNotNull);
      expect(result!.text, 'cached response');
    });

    test('stores multiple entries', () async {
      await cache.set('a', AiResponse(message: AiMessage.assistant('A')));
      await cache.set('b', AiResponse(message: AiMessage.assistant('B')));

      expect((await cache.get('a'))?.text, 'A');
      expect((await cache.get('b'))?.text, 'B');
    });

    test('removes specific entry', () async {
      await cache.set('key1', AiResponse(message: AiMessage.assistant('v')));
      await cache.remove('key1');

      expect(await cache.get('key1'), isNull);
    });

    test('clears all entries', () async {
      await cache.set('a', AiResponse(message: AiMessage.assistant('A')));
      await cache.set('b', AiResponse(message: AiMessage.assistant('B')));
      await cache.clear();

      expect(await cache.get('a'), isNull);
      expect(await cache.get('b'), isNull);
    });

    test('respects TTL', () async {
      final shortTtlCache =
          MemoryAiCache(ttl: const Duration(milliseconds: 50));

      await shortTtlCache.set(
          'key', AiResponse(message: AiMessage.assistant('v')));

      // Immediately available
      expect(await shortTtlCache.get('key'), isNotNull);

      // Wait for TTL to expire
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(await shortTtlCache.get('key'), isNull);
    });

    test('overwriting a key resets TTL', () async {
      await cache.set('key', AiResponse(message: AiMessage.assistant('v1')));
      await cache.set('key', AiResponse(message: AiMessage.assistant('v2')));

      final result = await cache.get('key');
      expect(result?.text, 'v2');
    });
  });
}
