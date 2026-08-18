import 'dart:convert';
import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ai_plus/ai_plus.dart';
import 'package:ai_plus/src/http/ai_http_client.dart';
import 'package:ai_plus/src/providers/gemini/gemini_provider.dart';

void main() {
  group('GeminiProvider', () {
    GeminiProvider createProvider(MockClient mockClient) {
      return GeminiProvider(
        apiKey: 'test-key',
        httpClient: AiHttpClient(client: mockClient),
      );
    }

    test('capabilities reflect supported features', () {
      final provider = GeminiProvider(apiKey: 'test-key');
      expect(provider.capabilities.streaming, isTrue);
      expect(provider.capabilities.toolCalling, isTrue);
      expect(provider.capabilities.structuredOutput, isTrue);
      expect(provider.capabilities.embeddings, isTrue);
      expect(provider.capabilities.imageInput, isTrue);
    });

    test('chat returns parsed response', () async {
      final mock = MockClient((request) async {
        expect(request.url.queryParameters['key'], 'test-key');
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Hello from Gemini!'}
                  ],
                  'role': 'model',
                },
                'finishReason': 'STOP',
              }
            ],
            'usageMetadata': {
              'promptTokenCount': 10,
              'candidatesTokenCount': 8,
              'totalTokenCount': 18,
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

      expect(response.text, 'Hello from Gemini!');
      expect(response.finishReason, AiFinishReason.stop);
      expect(response.usage.inputTokens, 10);
      expect(response.usage.outputTokens, 8);
    });

    test('chat parses function calls', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {
                      'functionCall': {
                        'name': 'get_weather',
                        'args': {'city': 'Paris'},
                      }
                    }
                  ],
                  'role': 'model',
                },
                'finishReason': 'STOP',
              }
            ],
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

      final toolCalls =
          response.message.content.whereType<AiToolCallContent>().toList();
      expect(toolCalls.length, 1);
      expect(toolCalls.first.name, 'get_weather');
      expect(toolCalls.first.arguments['city'], 'Paris');
    });

    test('embeddings single input', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'embedding': {
              'values': [0.1, 0.2, 0.3],
            },
          }),
          200,
        );
      });

      final provider = createProvider(mock);
      final result = await provider.embeddings(['Hello']);

      expect(result.embeddings.length, 1);
      expect(result.vector, [0.1, 0.2, 0.3]);
    });

    test('embeddings batch input', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'embeddings': [
              {
                'values': [0.1, 0.2]
              },
              {
                'values': [0.3, 0.4]
              },
            ],
          }),
          200,
        );
      });

      final provider = createProvider(mock);
      final result = await provider.embeddings(['A', 'B']);

      expect(result.embeddings.length, 2);
      expect(result.embeddings[0].vector, [0.1, 0.2]);
      expect(result.embeddings[1].vector, [0.3, 0.4]);
    });

    test('throws AiParsingException on empty candidates', () async {
      final mock = MockClient((request) async {
        return http.Response(jsonEncode({'candidates': <dynamic>[]}), 200);
      });

      final provider = createProvider(mock);
      expect(
        () => provider.chat(const AiRequest(
          messages: [
            AiMessage(role: AiMessageRole.user, content: [AiTextContent('Hi')])
          ],
        )),
        throwsA(isA<AiParsingException>()),
      );
    });
  });
}
