import 'package:test/test.dart';
import 'package:ai_plus/ai_plus.dart';

void main() {
  group('AiException hierarchy', () {
    test('AiAuthenticationException', () {
      const e = AiAuthenticationException('bad key',
          statusCode: 401, provider: 'OpenAI');
      expect(e.message, 'bad key');
      expect(e.statusCode, 401);
      expect(e.provider, 'OpenAI');
      expect(e, isA<AiException>());
      expect(e.toString(), contains('AiAuthenticationException'));
    });

    test('AiAuthorizationException', () {
      const e = AiAuthorizationException('no perms',
          statusCode: 403, provider: 'OpenAI');
      expect(e.message, 'no perms');
      expect(e.statusCode, 403);
      expect(e, isA<AiException>());
    });

    test('AiRateLimitException with retryAfter', () {
      const e = AiRateLimitException(
        'too many requests',
        statusCode: 429,
        retryAfter: Duration(seconds: 30),
      );
      expect(e.retryAfter, const Duration(seconds: 30));
      expect(e.statusCode, 429);
    });

    test('AiNetworkException', () {
      const e = AiNetworkException('connection failed');
      expect(e, isA<AiException>());
    });

    test('AiTimeoutException', () {
      const e = AiTimeoutException('request timed out');
      expect(e, isA<AiException>());
    });

    test('AiInvalidRequestException', () {
      const e = AiInvalidRequestException('bad request', statusCode: 400);
      expect(e.statusCode, 400);
    });

    test('AiProviderException', () {
      const e = AiProviderException('server error', statusCode: 500);
      expect(e.statusCode, 500);
    });

    test('AiParsingException', () {
      const e = AiParsingException('bad json', rawResponse: '{invalid}');
      expect(e.rawResponse, '{invalid}');
    });

    test('AiContentFilterException', () {
      const e = AiContentFilterException('filtered');
      expect(e, isA<AiException>());
    });

    test('AiUnsupportedCapabilityException', () {
      const e = AiUnsupportedCapabilityException('no streaming');
      expect(e, isA<AiException>());
    });

    test('AiStructuredOutputException extends AiException', () {
      const e =
          AiStructuredOutputException('parse error', rawResponse: 'bad json');
      expect(e, isA<AiException>());
      expect(e.rawResponse, 'bad json');
    });

    test('AiToolNotFoundException', () {
      const e = AiToolNotFoundException('tool not found');
      expect(e, isA<AiException>());
    });

    test('AiToolException', () {
      const e = AiToolException('tool failed');
      expect(e, isA<AiException>());
    });

    test('toString includes type, message, provider, statusCode, requestId',
        () {
      const e = AiRateLimitException(
        'rate limited',
        provider: 'OpenAI',
        statusCode: 429,
        requestId: 'req_123',
      );
      final str = e.toString();
      expect(str, contains('AiRateLimitException'));
      expect(str, contains('rate limited'));
      expect(str, contains('OpenAI'));
      expect(str, contains('429'));
      expect(str, contains('req_123'));
    });

    test('toString omits null fields', () {
      const e = AiNetworkException('connection failed');
      final str = e.toString();
      expect(str, isNot(contains('Provider')));
      expect(str, isNot(contains('Status')));
    });
  });
}
