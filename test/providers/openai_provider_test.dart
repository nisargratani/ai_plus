import 'dart:convert';

import 'package:ai_plus/ai_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  group('OpenAiProvider', () {
    OpenAiProvider createProvider(MockClient mockClient) {
      return OpenAiProvider(
        apiKey: 'test-key',
        httpClient: AiHttpClient(client: mockClient),
      );
    }

    test('capabilities reflect supported features', () {
      final provider = OpenAiProvider(apiKey: 'test-key');
      expect(provider.capabilities.streaming, isTrue);
      expect(provider.capabilities.toolCalling, isTrue);
      expect(provider.capabilities.structuredOutput, isTrue);
      expect(provider.capabilities.embeddings, isTrue);
      expect(provider.capabilities.imageInput, isTrue);
      expect(provider.capabilities.audioInput, isFalse);
    });

    test('chat returns parsed response', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/v1/chat/completions');
        expect(request.headers['Authorization'], 'Bearer test-key');

        return http.Response(
          jsonEncode({
            'id': 'chatcmpl-123',
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': 'Hello world!',
                },
                'finish_reason': 'stop',
              }
            ],
            'usage': {
              'prompt_tokens': 10,
              'completion_tokens': 5,
              'total_tokens': 15,
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

      expect(response.text, 'Hello world!');
      expect(response.finishReason, AiFinishReason.stop);
      expect(response.usage.inputTokens, 10);
      expect(response.usage.outputTokens, 5);
      expect(response.usage.totalTokens, 15);
      expect(response.raw, isNotNull);
    });

    test('chat parses tool calls', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'role': 'assistant',
                  'content': null,
                  'tool_calls': [
                    {
                      'id': 'call_abc',
                      'type': 'function',
                      'function': {
                        'name': 'get_weather',
                        'arguments': '{"city":"London"}',
                      },
                    }
                  ],
                },
                'finish_reason': 'tool_calls',
              }
            ],
            'usage': {
              'prompt_tokens': 20,
              'completion_tokens': 10,
              'total_tokens': 30
            },
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
      final toolCalls =
          response.message.content.whereType<AiToolCallContent>().toList();
      expect(toolCalls.length, 1);
      expect(toolCalls.first.name, 'get_weather');
      expect(toolCalls.first.arguments['city'], 'London');
    });

    test('throws AiAuthenticationException on 401', () async {
      final mock = MockClient((request) async {
        return http.Response('{"error": "invalid_api_key"}', 401);
      });

      final provider = createProvider(mock);
      expect(
        () => provider.chat(const AiRequest(
          messages: [
            AiMessage(role: AiMessageRole.user, content: [AiTextContent('Hi')])
          ],
        )),
        throwsA(isA<AiAuthenticationException>()),
      );
    });

    test('throws AiRateLimitException on 429', () async {
      final mock = MockClient((request) async {
        return http.Response('{"error": "rate_limit"}', 429);
      });

      final provider = createProvider(mock);
      expect(
        () => provider.chat(const AiRequest(
          messages: [
            AiMessage(role: AiMessageRole.user, content: [AiTextContent('Hi')])
          ],
        )),
        throwsA(isA<AiRateLimitException>()),
      );
    });

    test('throws AiProviderException on 500', () async {
      final mock = MockClient((request) async {
        return http.Response('Internal server error', 500);
      });

      final provider = createProvider(mock);
      expect(
        () => provider.chat(const AiRequest(
          messages: [
            AiMessage(role: AiMessageRole.user, content: [AiTextContent('Hi')])
          ],
        )),
        throwsA(isA<AiProviderException>()),
      );
    });

    test('throws AiInvalidRequestException on 400', () async {
      final mock = MockClient((request) async {
        return http.Response('Bad request', 400);
      });

      final provider = createProvider(mock);
      expect(
        () => provider.chat(const AiRequest(
          messages: [
            AiMessage(role: AiMessageRole.user, content: [AiTextContent('Hi')])
          ],
        )),
        throwsA(isA<AiInvalidRequestException>()),
      );
    });

    test('sends tools in request body', () async {
      final mock = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['tools'], isNotNull);
        expect((body['tools'] as List).length, 1);

        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'ok'},
                'finish_reason': 'stop'
              }
            ],
            'usage': {
              'prompt_tokens': 10,
              'completion_tokens': 5,
              'total_tokens': 15
            },
          }),
          200,
        );
      });

      final provider = createProvider(mock);
      await provider.chat(AiRequest(
        messages: const [
          AiMessage(role: AiMessageRole.user, content: [AiTextContent('Hi')])
        ],
        tools: [
          AiTool(
            name: 'test',
            description: 'test tool',
            parameters: AiJsonSchema.object(properties: {}),
            execute: (args) async => null,
          ),
        ],
      ));
    });

    test('embeddings returns parsed result', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/v1/embeddings');
        return http.Response(
          jsonEncode({
            'data': [
              {
                'embedding': [0.1, 0.2, 0.3]
              }
            ],
            'usage': {'prompt_tokens': 5, 'total_tokens': 5},
          }),
          200,
        );
      });

      final provider = createProvider(mock);
      final result = await provider.embeddings(['Hello']);

      expect(result.embeddings.length, 1);
      expect(result.vector, [0.1, 0.2, 0.3]);
      expect(result.usage.inputTokens, 5);
    });
  });
}
