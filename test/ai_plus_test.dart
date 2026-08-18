import 'package:test/test.dart';
import 'package:ai_plus/ai_plus.dart';

void main() {
  group('ai_plus core tests', () {
    test('Can instantiate AiClient with OpenAI provider', () {
      final client = AiClient(
        provider: AiProvider.openAI(apiKey: 'test-key'),
      );
      expect(client.provider, isNotNull);
    });

    test('Can instantiate AiClient with Gemini provider', () {
      final client = AiClient(
        provider: AiProvider.gemini(apiKey: 'test-key'),
      );
      expect(client.provider, isNotNull);
    });

    test('Can instantiate AiClient with Anthropic provider', () {
      final client = AiClient(
        provider: AiProvider.anthropic(apiKey: 'test-key'),
      );
      expect(client.provider, isNotNull);
    });

    test('Can create conversation', () {
      final client = AiClient(
        provider: AiProvider.openAI(apiKey: 'test-key'),
      );
      final conversation = client.conversation();
      expect(conversation.messages, isEmpty);
      conversation.addMessage(AiMessage.user('Hello'));
      expect(conversation.messages.length, 1);
    });
  });
}
