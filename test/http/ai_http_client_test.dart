import 'dart:convert';

import 'package:ai_plus/ai_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final url = Uri.parse('https://api.example.com/v1/chat?key=secret-key');

  group('AiHttpClient errors', () {
    Future<Object> errorFor(http.Response response) async {
      final client = AiHttpClient(client: MockClient((_) async => response));
      try {
        await client.post(url, provider: 'Test');
      } catch (e) {
        return e;
      }
      fail('expected an exception');
    }

    test('includes provider error message, provider and request id', () async {
      final error = await errorFor(http.Response(
        jsonEncode({
          'error': {'message': 'Incorrect API key provided'},
        }),
        401,
        headers: {'x-request-id': 'req_123'},
      ));

      expect(error, isA<AiAuthenticationException>());
      final e = error as AiException;
      expect(e.message, contains('Incorrect API key provided'));
      expect(e.provider, 'Test');
      expect(e.statusCode, 401);
      expect(e.requestId, 'req_123');
    });

    test('accepts string error bodies', () async {
      final error = await errorFor(
          http.Response(jsonEncode({'error': 'model not found'}), 404));
      expect(error, isA<AiInvalidRequestException>());
      expect((error as AiException).message, contains('model not found'));
    });

    test('parses retry-after seconds', () async {
      final error = await errorFor(
          http.Response('{}', 429, headers: {'retry-after': '7'}));
      expect((error as AiRateLimitException).retryAfter,
          const Duration(seconds: 7));
    });

    test('prefers retry-after-ms', () async {
      final error = await errorFor(http.Response('{}', 429,
          headers: {'retry-after': '7', 'retry-after-ms': '1500'}));
      expect((error as AiRateLimitException).retryAfter,
          const Duration(milliseconds: 1500));
    });

    test('maps 408 to AiTimeoutException and 5xx to AiProviderException',
        () async {
      expect(await errorFor(http.Response('', 408)), isA<AiTimeoutException>());
      expect(
          await errorFor(http.Response('', 503)), isA<AiProviderException>());
    });

    test('truncates very large non-JSON error bodies', () async {
      final error = await errorFor(http.Response('x' * 5000, 400));
      expect((error as AiException).message.length, lessThan(600));
    });

    test('network errors do not leak the URL (which may hold credentials)',
        () async {
      final client = AiHttpClient(
        client: MockClient(
            (_) async => throw http.ClientException('Connection refused', url)),
      );

      await expectLater(
        client.post(url),
        throwsA(isA<AiNetworkException>()
            .having((e) => e.toString(), 'toString', isNot(contains('secret')))
            .having(
                (e) => e.message, 'message', contains('Connection refused'))),
      );
    });

    test('non-object JSON bodies raise AiParsingException', () async {
      final client = AiHttpClient(
          client: MockClient((_) async => http.Response('[]', 200)));
      await expectLater(client.post(url), throwsA(isA<AiParsingException>()));
    });
  });

  group('AiHttpClient.postSse', () {
    Stream<String> sse(String body, {int chunkSize = 3}) {
      final bytes = utf8.encode(body);
      final chunks = [
        for (var i = 0; i < bytes.length; i += chunkSize)
          bytes.sublist(
              i, i + chunkSize > bytes.length ? bytes.length : i + chunkSize),
      ];
      final client = AiHttpClient(
        client: MockClient.streaming((_, __) async =>
            http.StreamedResponse(Stream.fromIterable(chunks), 200)),
      );
      return client.postSse(url);
    }

    test('yields data payloads across arbitrary chunk boundaries', () async {
      final data = await sse(
        ': comment\n'
        'event: message\n'
        'data: {"a":1}\n\n'
        'data:{"b":"héllo 👋"}\r\n\r\n'
        'id: 5\n'
        'data: [DONE]\n\n',
      ).toList();

      expect(data, ['{"a":1}', '{"b":"héllo 👋"}', '[DONE]']);
    });

    test('handles a final line without trailing newline', () async {
      expect(await sse('data: {"a":1}').toList(), ['{"a":1}']);
    });

    test('maps mid-stream connection failures to AiNetworkException', () async {
      final client = AiHttpClient(
        client: MockClient.streaming((_, __) async => http.StreamedResponse(
              Stream.fromIterable([utf8.encode('data: {"a":1}\n\n')])
                  .followedByError(http.ClientException('reset', url)),
              200,
            )),
      );
      final received = <String>[];
      await expectLater(
        client.postSse(url).forEach(received.add),
        throwsA(isA<AiNetworkException>()),
      );
      expect(received, ['{"a":1}']);
    });

    test('surfaces HTTP errors before streaming', () async {
      final client = AiHttpClient(
        client: MockClient.streaming((_, __) async => http.StreamedResponse(
            Stream.value(utf8.encode('{"error":{"message":"nope"}}')), 429)),
      );
      await expectLater(
        client.postSse(url).toList(),
        throwsA(isA<AiRateLimitException>()
            .having((e) => e.message, 'message', contains('nope'))),
      );
    });
  });
}

extension<T> on Stream<T> {
  Stream<T> followedByError(Exception error) async* {
    yield* this;
    throw error;
  }
}
