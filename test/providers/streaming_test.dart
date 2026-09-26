import 'dart:convert';

import 'package:ai_plus/ai_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  group('OpenAI-compatible streaming', () {
    late Map<String, dynamic> sentBody;

    OpenAiProvider openAi(List<Object> events) => OpenAiProvider(
          apiKey: 'k',
          httpClient: AiHttpClient(
            client: MockClient.streaming((request, bodyStream) async {
              sentBody = jsonDecode(await bodyStream.bytesToString())
                  as Map<String, dynamic>;
              return sseResponse(events, done: true);
            }),
          ),
        );

    Map<String, dynamic> delta(Map<String, dynamic> delta,
            [String? finishReason]) =>
        {
          'choices': [
            {'index': 0, 'delta': delta, 'finish_reason': finishReason},
          ],
        };

    test('assembles fragmented tool calls into complete calls', () async {
      final chunks = await openAi([
        delta({
          'tool_calls': [
            {
              'index': 0,
              'id': 'call_1',
              'function': {'name': 'get_weather', 'arguments': ''},
            },
          ],
        }),
        delta({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': '{"city":'},
            },
          ],
        }),
        delta({
          'tool_calls': [
            {
              'index': 1,
              'id': 'call_2',
              'function': {'name': 'get_time', 'arguments': '{}'},
            },
          ],
        }),
        delta({
          'tool_calls': [
            {
              'index': 0,
              'function': {'arguments': '"Paris"}'},
            },
          ],
        }),
        delta({}, 'tool_calls'),
        {
          'choices': <Object>[],
          'usage': {
            'prompt_tokens': 3,
            'completion_tokens': 4,
            'total_tokens': 7,
          },
        },
      ]).stream(userRequest('hi')).toList();

      final calls = chunks
          .expand((c) => c.content)
          .whereType<AiToolCallContent>()
          .toList();
      expect(calls, hasLength(2));
      expect(calls[0].id, 'call_1');
      expect(calls[0].name, 'get_weather');
      expect(calls[0].arguments, {'city': 'Paris'});
      expect(calls[1].name, 'get_time');

      // Only the terminating chunk carries a finish reason.
      final reasons =
          chunks.map((c) => c.finishReason).whereType<AiFinishReason>();
      expect(reasons, [AiFinishReason.toolCalls]);

      expect(chunks.last.usage?.totalTokens, 7);
      expect(sentBody['stream_options'], {'include_usage': true});
    });

    test('text chunks have no finish reason until the end', () async {
      final chunks = await openAi([
        delta({'content': 'Hel'}),
        delta({'content': 'lo'}),
        delta({}, 'stop'),
      ]).stream(userRequest('hi')).toList();

      expect(chunks.map((c) => c.text).join(), 'Hello');
      expect(
          chunks.map((c) => c.finishReason), [null, null, AiFinishReason.stop]);
    });

    test('in-stream error payloads raise AiProviderException', () async {
      await expectLater(
        openAi([
          {
            'error': {'message': 'boom'},
          },
        ]).stream(userRequest('hi')).toList(),
        throwsA(isA<AiProviderException>()
            .having((e) => e.message, 'message', contains('boom'))),
      );
    });
  });

  group('Anthropic streaming', () {
    AnthropicProvider anthropic(List<Object> events) => AnthropicProvider(
          apiKey: 'k',
          httpClient: AiHttpClient(
            client: MockClient.streaming((_, __) async => sseResponse(events)),
          ),
        );

    test('assembles tool_use input and reports full usage', () async {
      final chunks = await anthropic([
        {
          'type': 'message_start',
          'message': {
            'usage': {'input_tokens': 11, 'output_tokens': 1},
          },
        },
        {
          'type': 'content_block_start',
          'index': 0,
          'content_block': {'type': 'text', 'text': ''},
        },
        {
          'type': 'content_block_delta',
          'index': 0,
          'delta': {'type': 'text_delta', 'text': 'Checking.'},
        },
        {'type': 'content_block_stop', 'index': 0},
        {
          'type': 'content_block_start',
          'index': 1,
          'content_block': {
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'get_weather',
            'input': <String, dynamic>{},
          },
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': '{"city": "Be'},
        },
        {
          'type': 'content_block_delta',
          'index': 1,
          'delta': {'type': 'input_json_delta', 'partial_json': 'rlin"}'},
        },
        {'type': 'content_block_stop', 'index': 1},
        {
          'type': 'message_delta',
          'delta': {'stop_reason': 'tool_use'},
          'usage': {'output_tokens': 20},
        },
        {'type': 'message_stop'},
      ]).stream(userRequest('hi')).toList();

      expect(chunks.map((c) => c.text).join(), 'Checking.');
      final calls = chunks
          .expand((c) => c.content)
          .whereType<AiToolCallContent>()
          .toList();
      expect(calls, hasLength(1));
      expect(calls.single.id, 'toolu_1');
      expect(calls.single.arguments, {'city': 'Berlin'});

      final last = chunks.last;
      expect(last.finishReason, AiFinishReason.toolCalls);
      expect(last.usage?.inputTokens, 11);
      expect(last.usage?.outputTokens, 20);
      expect(last.usage?.totalTokens, 31);
    });

    test('error events are raised instead of silently ending', () async {
      await expectLater(
        anthropic([
          {
            'type': 'error',
            'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
          },
        ]).stream(userRequest('hi')).toList(),
        throwsA(isA<AiProviderException>()
            .having((e) => e.statusCode, 'statusCode', 529)),
      );
    });
  });

  group('Gemini streaming', () {
    test('uses the SSE endpoint and reports finish only at the end', () async {
      late Uri url;
      final provider = GeminiProvider(
        apiKey: 'k',
        httpClient: AiHttpClient(
          client: MockClient.streaming((request, _) async {
            url = request.url;
            return sseResponse([
              {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'Hel'},
                      ],
                    },
                  },
                ],
              },
              {
                'candidates': [
                  {
                    'content': {
                      'parts': [
                        {'text': 'lo'},
                      ],
                    },
                    'finishReason': 'STOP',
                  },
                ],
                'usageMetadata': {'totalTokenCount': 9},
              },
            ]);
          }),
        ),
      );

      final chunks = await provider.stream(userRequest('hi')).toList();
      expect(url.path, endsWith(':streamGenerateContent'));
      expect(url.queryParameters, {'alt': 'sse'});
      expect(chunks.map((c) => c.text).join(), 'Hello');
      expect(chunks.map((c) => c.finishReason), [null, AiFinishReason.stop]);
      expect(chunks.last.usage?.totalTokens, 9);
    });
  });

  group('Request encoding', () {
    Future<Map<String, dynamic>> bodyFor(
      AiProvider Function(AiHttpClient) create,
      AiRequest request, {
      Map<String, dynamic>? response,
      void Function(http.Request)? inspect,
    }) async {
      late Map<String, dynamic> body;
      final provider = create(AiHttpClient(
        client: MockClient((req) async {
          inspect?.call(req);
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode(response ??
                {
                  'choices': [
                    {
                      'message': {'role': 'assistant', 'content': 'ok'},
                      'finish_reason': 'stop',
                    },
                  ],
                }),
            200,
          );
        }),
      ));
      await provider.chat(request);
      return body;
    }

    final toolTurn = [
      AiMessage.user('weather?'),
      const AiMessage(role: AiMessageRole.assistant, content: [
        AiToolCallContent(id: 'a', name: 'w', arguments: {'city': 'A'}),
        AiToolCallContent(id: 'b', name: 'w', arguments: {'city': 'B'}),
      ]),
      const AiMessage(role: AiMessageRole.tool, content: [
        AiToolResultContent(id: 'a', name: 'w', result: 'sunny'),
        AiToolResultContent(id: 'b', name: 'w', result: {'temp': 20}),
      ]),
    ];

    test('OpenAI sends one tool message per tool result', () async {
      final body = await bodyFor(
        (c) => OpenAiProvider(apiKey: 'k', httpClient: c),
        AiRequest(messages: toolTurn),
      );
      final messages = (body['messages'] as List).cast<Map<String, dynamic>>();
      final tools = messages.where((m) => m['role'] == 'tool').toList();
      expect(tools.map((m) => m['tool_call_id']), ['a', 'b']);
      expect(tools[1]['content'], '{"temp":20}');
    });

    test('non-JSON tool results fall back to toString', () async {
      final body = await bodyFor(
        (c) => OpenAiProvider(apiKey: 'k', httpClient: c),
        AiRequest(messages: [
          AiMessage(role: AiMessageRole.tool, content: [
            AiToolResultContent(
                id: 'a', name: 'w', result: {'at': Uri(path: 'x')}),
          ]),
        ]),
      );
      expect((body['messages'] as List).single['content'], '{"at":"x"}');
    });

    test('OpenAI uses max_completion_tokens; custom uses max_tokens', () async {
      final request = AiRequest(
          messages: [AiMessage.developer('d'), AiMessage.user('u')],
          maxTokens: 50);

      final openAi = await bodyFor(
          (c) => OpenAiProvider(apiKey: 'k', httpClient: c), request);
      expect(openAi['max_completion_tokens'], 50);
      expect(openAi.containsKey('max_tokens'), isFalse);
      expect((openAi['messages'] as List).first['role'], 'developer');

      final custom = await bodyFor(
        (c) =>
            CustomProvider(baseUrl: 'http://x/v1', apiKey: '', httpClient: c),
        request,
        inspect: (req) {
          expect(req.headers.containsKey('Authorization'), isFalse);
        },
      );
      expect(custom['max_tokens'], 50);
      expect((custom['messages'] as List).first['role'], 'system');
    });

    test('custom headers are sent', () async {
      await bodyFor(
        (c) => CustomProvider(
          baseUrl: 'http://x/v1/',
          apiKey: '',
          headers: {'api-key': 'azure'},
          httpClient: c,
        ),
        userRequest('hi'),
        inspect: (req) {
          expect(req.headers['api-key'], 'azure');
          expect(req.url.path, '/v1/chat/completions');
        },
      );
    });

    test('OpenAI strict mode only for fully-required schemas', () async {
      Future<Map<String, dynamic>> formatFor(AiJsonSchema schema) async {
        final body = await bodyFor(
          (c) => OpenAiProvider(apiKey: 'k', httpClient: c),
          AiRequest(messages: [AiMessage.user('x')], schema: schema),
        );
        return (body['response_format'] as Map)['json_schema']
            as Map<String, dynamic>;
      }

      final optional = await formatFor(AiJsonSchema.object(
        properties: {'a': AiJsonSchema.string(), 'b': AiJsonSchema.string()},
        required: ['a'],
      ));
      expect(optional['strict'], isFalse);

      final strict = await formatFor(AiJsonSchema.object(
        properties: {
          'a': AiJsonSchema.array(
            items: AiJsonSchema.object(
              properties: {'x': AiJsonSchema.integer()},
              required: ['x'],
            ),
          ),
        },
        required: ['a'],
      ));
      expect(strict['strict'], isTrue);
      final schema = strict['schema'] as Map<String, dynamic>;
      expect(schema['additionalProperties'], isFalse);
      expect(
        ((schema['properties'] as Map)['a'] as Map)['items']
            ['additionalProperties'],
        isFalse,
      );
    });

    test(
        'Gemini echoes thought signatures and uses the user role for '
        'function responses', () async {
      final body = await bodyFor(
        (c) => GeminiProvider(apiKey: 'k', httpClient: c),
        AiRequest(messages: [
          AiMessage.user('q'),
          const AiMessage(role: AiMessageRole.assistant, content: [
            AiToolCallContent(
              id: 'w',
              name: 'w',
              arguments: {},
              metadata: {'thoughtSignature': 'sig'},
            ),
          ]),
          const AiMessage(role: AiMessageRole.tool, content: [
            AiToolResultContent(id: 'w', name: 'w', result: 'ok'),
          ]),
        ]),
        response: {
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'done'},
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        },
      );
      final contents = (body['contents'] as List).cast<Map<String, dynamic>>();
      expect(contents.map((c) => c['role']), ['user', 'model', 'user']);
      expect((contents[1]['parts'] as List).single['thoughtSignature'], 'sig');
    });
  });

  group('Response parsing', () {
    AiProvider withResponse(
      AiProvider Function(AiHttpClient) create,
      Map<String, dynamic> json,
    ) =>
        create(AiHttpClient(
          client: MockClient((_) async => http.Response(jsonEncode(json), 200)),
        ));

    test('Gemini reports toolCalls and keeps the thought signature', () async {
      final response = await withResponse(
        (c) => GeminiProvider(apiKey: 'k', httpClient: c),
        {
          'candidates': [
            {
              'content': {
                'parts': [
                  {
                    'functionCall': {
                      'id': 'fc_1',
                      'name': 'w',
                      'args': {'q': 1},
                    },
                    'thoughtSignature': 'sig',
                  },
                ],
              },
              'finishReason': 'STOP',
            },
          ],
        },
      ).chat(userRequest('q'));

      expect(response.finishReason, AiFinishReason.toolCalls);
      final call =
          response.message.content.whereType<AiToolCallContent>().single;
      expect(call.id, 'fc_1');
      expect(call.metadata['thoughtSignature'], 'sig');
    });

    test('Gemini blocked prompts raise AiContentFilterException', () async {
      await expectLater(
        withResponse(
          (c) => GeminiProvider(apiKey: 'k', httpClient: c),
          {
            'promptFeedback': {'blockReason': 'SAFETY'},
          },
        ).chat(userRequest('q')),
        throwsA(isA<AiContentFilterException>()),
      );
    });

    test('Anthropic accepts an empty content array', () async {
      final response = await withResponse(
        (c) => AnthropicProvider(apiKey: 'k', httpClient: c),
        {'content': <Object>[], 'stop_reason': 'end_turn'},
      ).chat(userRequest('q'));
      expect(response.text, '');
      expect(response.finishReason, AiFinishReason.stop);
    });

    test('OpenAI embeddings are returned in input order', () async {
      final result = await withResponse(
        (c) => OpenAiProvider(apiKey: 'k', httpClient: c),
        {
          'data': [
            {
              'index': 1,
              'embedding': [2.0],
            },
            {
              'index': 0,
              'embedding': [1.0],
            },
          ],
        },
      ).embeddings(['a', 'b']);
      expect(result.embeddings.map((e) => e.vector.single), [1.0, 2.0]);
    });

    test('empty embedding batches make no request', () async {
      final provider = OpenAiProvider(
        apiKey: 'k',
        httpClient: AiHttpClient(
          client: MockClient((_) async => fail('no request expected')),
        ),
      );
      expect((await provider.embeddings([])).embeddings, isEmpty);
    });
  });
}
