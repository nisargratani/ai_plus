import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_plus/ai_plus.dart';
import 'package:ai_plus/src/http/ai_http_client.dart';
import 'package:ai_plus/src/providers/anthropic/anthropic_provider.dart';

void main() {
  group('AnthropicProvider', () {
    AnthropicProvider createProvider(MockClient mockClient) {
      return AnthropicProvider(
        apiKey: 'test-key',
        httpClient: AiHttpClient(client: mockClient),
      );
    }

    test('capabilities reflect supported features', () {
      final provider = AnthropicProvider(apiKey: 'test-key');
      expect(provider.capabilities.streaming, isTrue);
      expect(provider.capabilities.toolCalling, isTrue);
      expect(provider.capabilities.structuredOutput, isFalse);
      expect(provider.capabilities.embeddings, isFalse);
      expect(provider.capabilities.imageInput, isTrue);
    });

    test('chat returns parsed response', () async {
      final mock = MockClient((request) async {
        expect(request.headers['x-api-key'], 'test-key');
        expect(request.headers['anthropic-version'], '2023-06-01');
        return http.Response(
          jsonEncode({
            'id': 'msg_123',
            'content': [
              {'type': 'text', 'text': 'Hello from Claude!'}
            ],
            'stop_reason': 'end_turn',
            'usage': {
              'input_tokens': 15,
              'output_tokens': 10,
            },
          }),
          200,
        );
      });

      final provider = createProvider(mock);
      final response = await provider.chat(const AiRequest(
        messages: [
          AiMessage(role: AiMessageRole.user, content: [AiTextContent('Hi')])
        ],
      ));

      expect(response.text, 'Hello from Claude!');
      expect(response.finishReason, AiFinishReason.stop);
      expect(response.usage.inputTokens, 15);
      expect(response.usage.outputTokens, 10);
    });

    test('chat parses tool use blocks', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'id': 'msg_456',
            'content': [
              {'type': 'text', 'text': 'Let me check the weather.'},
              {
                'type': 'tool_use',
                'id': 'toolu_01',
                'name': 'get_weather',
                'input': {'city': 'Berlin'},
              }
            ],
            'stop_reason': 'tool_use',
            'usage': {'input_tokens': 20, 'output_tokens': 15},
          }),
          200,
        );
      });

      final provider = createProvider(mock);
      final response = await provider.chat(const AiRequest(
        messages: [
          AiMessage(
              role: AiMessageRole.user, content: [AiTextContent('Weather?')])
        ],
      ));

      expect(response.finishReason, AiFinishReason.toolCalls);
      final textParts =
          response.message.content.whereType<AiTextContent>().toList();
      expect(textParts.first.text, 'Let me check the weather.');

      final toolCalls =
          response.message.content.whereType<AiToolCallContent>().toList();
      expect(toolCalls.length, 1);
      expect(toolCalls.first.name, 'get_weather');
      expect(toolCalls.first.arguments['city'], 'Berlin');
    });

    test('system messages sent at top level', () async {
      final mock = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['system'], 'Be helpful');

        // Ensure system message not in messages array
        final messages = body['messages'] as List;
        for (final msg in messages) {
          expect(msg['role'], isNot('system'));
        }

        return http.Response(
          jsonEncode({
            'content': [
              {'type': 'text', 'text': 'ok'}
            ],
            'stop_reason': 'end_turn',
            'usage': {'input_tokens': 10, 'output_tokens': 5},
          }),
          200,
        );
      });

      final provider = createProvider(mock);
      await provider.chat(const AiRequest(
        messages: [
          AiMessage(
              role: AiMessageRole.system,
              content: [AiTextContent('Be helpful')]),
          AiMessage(role: AiMessageRole.user, content: [AiTextContent('Hi')]),
        ],
      ));
    });

    test('embeddings throws AiUnsupportedCapabilityException', () {
      final provider = AnthropicProvider(apiKey: 'test-key');
      expect(
        () => provider.embeddings(['text']),
        throwsA(isA<AiUnsupportedCapabilityException>()),
      );
    });
  });
}
