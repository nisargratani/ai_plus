// Regression tests for the issues found by the external QA pass of
// 2026-11-02 (AIP-01 … AIP-19). Each group is named after its issue id.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ai_plus/ai_plus.dart';
import 'package:ai_plus/src/providers/anthropic/anthropic_sampling.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  group('AIP-01: header values never leak into exceptions or logs', () {
    const secret = 'SECRET9f8e7d';

    final factories = <String, AiProvider Function(String, http.Client)>{
      'OpenAI': (key, c) =>
          AiProvider.openAI(apiKey: key, httpClient: AiHttpClient(client: c)),
      'Gemini': (key, c) =>
          AiProvider.gemini(apiKey: key, httpClient: AiHttpClient(client: c)),
      'Anthropic': (key, c) => AiProvider.anthropic(
          apiKey: key, httpClient: AiHttpClient(client: c)),
      'Custom api-key header': (key, c) => AiProvider.custom(
            baseUrl: 'https://example.com/v1',
            apiKey: '',
            headers: {'api-key': key},
            httpClient: AiHttpClient(client: c),
          ),
    };
    const suffixes = {
      'trailing newline': '\n',
      'non-breaking space': ' ',
      'zero-width space': '​',
    };

    for (final provider in factories.entries) {
      for (final suffix in suffixes.entries) {
        test('${provider.key}: key with a ${suffix.key}', () async {
          var sent = 0;
          final client = MockClient((_) async {
            sent++;
            return http.Response('{}', 200);
          });
          final log = RecordingLogger();
          final ai = AiClient(
            provider: provider.value('sk-$secret${suffix.value}', client),
            logger: log,
            retryPolicy: const AiRetryPolicy(
              maxAttempts: 2,
              initialDelay: Duration(milliseconds: 1),
              jitter: false,
            ),
          );

          final error = await _errorOf(ai.chat(messages: [_user]));

          expect(error, isA<AiInvalidRequestException>());
          expect('$error', isNot(contains(secret)));
          expect('$error', contains('header'));
          expect(log.all, isNot(contains(secret)));
          expect(log.all, isNot(contains('retrying')));
          expect(sent, 0, reason: 'nothing may be sent');
        });
      }
    }

    test('with the real dart:io client, nothing is sent or leaked', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((r) {
        requests++;
        r.response.close();
      });
      addTearDown(() => server.close(force: true));

      final ai = AiClient(
        provider: AiProvider.openAI(
          apiKey: 'sk-proj-$secret\n',
          baseUrl: 'http://127.0.0.1:${server.port}/v1',
        ),
      );
      addTearDown(ai.close);

      final error = await _errorOf(ai.chat(messages: [_user]));
      expect(error, isA<AiInvalidRequestException>());
      expect('$error', isNot(contains(secret)));
      expect('$error', contains('Authorization'));
      expect(requests, 0);
    });

    test('unknown transport errors are described by type only', () async {
      final client = AiHttpClient(
        client: MockClient((_) async => throw const FormatException(
            'Invalid HTTP header field value: "Bearer sk-$secret"')),
      );
      final error = await _errorOf(client.post(_url));
      expect(error, isA<AiNetworkException>());
      expect('$error', isNot(contains(secret)));
      expect('$error', contains('FormatException'));
    });

    test('tabs are allowed; invalid header names are rejected', () async {
      final client = AiHttpClient(
          client: MockClient((_) async => http.Response('{}', 200)));
      expect(await client.post(_url, headers: {'x-note': 'a\tb'}), isEmpty);
      expect(await _errorOf(client.post(_url, headers: {'bad name': 'x'})),
          isA<AiInvalidRequestException>());
    });

    test('a body that cannot be JSON-encoded is an AiInvalidRequestException',
        () async {
      var sent = 0;
      final client = AiHttpClient(
        client: MockClient((_) async {
          sent++;
          return http.Response('{}', 200);
        }),
      );
      final error = await _errorOf(
          client.post(_url, body: {'when': DateTime.utc(2026, 11, 2)}));
      expect(error, isA<AiInvalidRequestException>());
      expect('$error', contains('DateTime'));
      expect(sent, 0);

      final streamError = await _errorOf(
          client.postSse(_url, body: {'when': DateTime(2026)}).toList());
      expect(streamError, isA<AiInvalidRequestException>());
    });
  });

  group('AIP-02: Anthropic thinking blocks are passed back', () {
    final thinking = {'type': 'thinking', 'thinking': '', 'signature': 'EqQB'};
    final redacted = {'type': 'redacted_thinking', 'data': 'EmwKAhgB'};

    test('non-streaming tool loop sends thinking blocks back verbatim',
        () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        bodies.add(jsonDecode(req.body) as Map<String, dynamic>);
        if (bodies.length == 1) {
          return _json(_anthropicMessage([
            thinking,
            redacted,
            {'type': 'text', 'text': 'Let me check.'},
            _toolUse('toolu_1', 'get_weather', {'city': 'Pune'}),
          ], stopReason: 'tool_use'));
        }
        return _json(_anthropicMessage([
          {'type': 'text', 'text': 'Sunny'},
        ]));
      });
      final ai = AiClient(
        provider: AiProvider.anthropic(
            apiKey: 'k', httpClient: AiHttpClient(client: client)),
      );

      final agent = AiAgent(client: ai, tools: [_weatherTool()]);
      expect(await agent.run('Weather in Pune?'), 'Sunny');

      final assistant =
          (bodies[1]['messages'] as List).cast<Map<String, dynamic>>()[1];
      expect(assistant['role'], 'assistant');
      final content = (assistant['content'] as List).cast<Object?>();
      expect(content, [
        thinking,
        redacted,
        {'type': 'text', 'text': 'Let me check.'},
        _toolUse('toolu_1', 'get_weather', {'city': 'Pune'}),
      ]);
      // Unmodified, down to the key order.
      expect(jsonEncode(content.first), jsonEncode(thinking));
    });

    test('thinking is stored in the first tool call metadata', () async {
      final provider = AnthropicProvider(
        apiKey: 'k',
        httpClient: AiHttpClient(
          client: MockClient((_) async => _json(_anthropicMessage([
                thinking,
                _toolUse('a', 'get_weather', {}),
                _toolUse('b', 'get_weather', {}),
              ], stopReason: 'tool_use'))),
        ),
      );
      final response = await provider.chat(userRequest('x'));
      final calls =
          response.message.content.whereType<AiToolCallContent>().toList();
      expect(
          calls[0].metadata[AnthropicProvider.thinkingMetadataKey], [thinking]);
      expect(calls[1].metadata, isEmpty);
      expect(response.text, isEmpty, reason: 'thinking is not answer text');
    });

    test('streamed thinking is reassembled and sent back', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient.streaming((req, body) async {
        bodies.add(
            jsonDecode(await body.bytesToString()) as Map<String, dynamic>);
        if (bodies.length == 1) {
          return sseResponse([
            {
              'type': 'message_start',
              'message': {
                'usage': {'input_tokens': 5, 'output_tokens': 1},
              },
            },
            _blockStart(
                0, {'type': 'thinking', 'thinking': '', 'signature': ''}),
            _blockDelta(0, {'type': 'thinking_delta', 'thinking': 'Let me '}),
            _blockDelta(0, {'type': 'thinking_delta', 'thinking': 'think.'}),
            _blockDelta(0, {'type': 'signature_delta', 'signature': 'sig-1'}),
            {'type': 'content_block_stop', 'index': 0},
            _blockStart(1, redacted),
            {'type': 'content_block_stop', 'index': 1},
            _blockStart(2, {
              'type': 'tool_use',
              'id': 'toolu_2',
              'name': 'get_weather',
              'input': <String, dynamic>{},
            }),
            _blockDelta(2, {
              'type': 'input_json_delta',
              'partial_json': '{"city":"Pune"}',
            }),
            {'type': 'content_block_stop', 'index': 2},
            {
              'type': 'message_delta',
              'delta': {'stop_reason': 'tool_use'},
              'usage': {'output_tokens': 30},
            },
            {'type': 'message_stop'},
          ]);
        }
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode(_anthropicMessage([
            {'type': 'text', 'text': 'Sunny'},
          ])))),
          200,
        );
      });
      final ai = AiClient(
        provider: AiProvider.anthropic(
            apiKey: 'k', httpClient: AiHttpClient(client: client)),
      );

      final conversation = ai.conversation(tools: [_weatherTool()]);
      await conversation.stream('Weather in Pune?').drain<void>();
      final call = conversation.messages.last.content
          .whereType<AiToolCallContent>()
          .single;
      final streamedThinking = {
        'type': 'thinking',
        'thinking': 'Let me think.',
        'signature': 'sig-1',
      };
      expect(call.metadata[AnthropicProvider.thinkingMetadataKey],
          [streamedThinking, redacted]);

      conversation.addMessage(AiMessage(
        role: AiMessageRole.tool,
        content: [
          AiToolResultContent(id: call.id, name: call.name, result: 'Sunny'),
        ],
      ));
      final follow = await ai
          .chat(messages: conversation.messages, tools: [_weatherTool()]);
      expect(follow.text, 'Sunny');

      final assistant =
          (bodies[1]['messages'] as List).cast<Map<String, dynamic>>()[1];
      final content = (assistant['content'] as List).cast<Object?>();
      expect(jsonEncode(content.take(2).toList()),
          jsonEncode([streamedThinking, redacted]));
      expect(
          content.last, _toolUse('toolu_2', 'get_weather', {'city': 'Pune'}));
    });
  });

  group('AIP-03: cache keys include the provider endpoint', () {
    test('a shared cache never serves one provider to another', () async {
      final cache = MemoryAiCache();
      var calls = 0;
      http.Client reply(Object body) => MockClient((_) async {
            calls++;
            return _json(body);
          });
      AiClient client(AiProvider provider) =>
          AiClient(provider: provider, cache: cache);

      final openAi = client(AiProvider.openAI(
          apiKey: 'k',
          httpClient: AiHttpClient(
              client: reply(_openAiCompletion(content: 'from OpenAI')))));
      final gemini = client(AiProvider.gemini(
          apiKey: 'k',
          httpClient:
              AiHttpClient(client: reply(_geminiResponse('from Gemini')))));
      AiClient local(String host, String answer) => client(AiProvider.custom(
          baseUrl: 'http://$host:11434/v1',
          apiKey: '',
          httpClient:
              AiHttpClient(client: reply(_openAiCompletion(content: answer)))));
      final one = local('one', 'from one');
      final two = local('two', 'from two');

      final q = [AiMessage.user('Summarise our refund policy')];
      expect((await openAi.chat(messages: q)).text, 'from OpenAI');
      expect((await gemini.chat(messages: q)).text, 'from Gemini');
      expect((await one.chat(messages: q, model: 'llama3.2')).text, 'from one');
      expect((await two.chat(messages: q, model: 'llama3.2')).text, 'from two');
      expect(calls, 4);

      // Repeats are still served from the shared cache.
      expect((await gemini.chat(messages: q)).text, 'from Gemini');
      expect((await two.chat(messages: q, model: 'llama3.2')).text, 'from two');
      expect(calls, 4);
    });

    test('cacheKey uses the namespace and ignores abortTrigger', () {
      final request = userRequest('x');
      final key = CacheMiddleware.cacheKey(request);
      expect(key, startsWith('ai_plus:v2:'));
      expect(
          CacheMiddleware.cacheKey(request, namespace: 'OpenAI|a'), isNot(key));
      expect(CacheMiddleware.cacheKey(request, namespace: 'OpenAI|a'),
          isNot(CacheMiddleware.cacheKey(request, namespace: 'Gemini|a')));
      expect(
          CacheMiddleware.cacheKey(
              request.copyWith(abortTrigger: Completer<void>().future)),
          key);
    });
  });

  group('AIP-04: Gemini thinking tokens count as output', () {
    const usage = {
      'promptTokenCount': 10,
      'toolUsePromptTokenCount': 3,
      'candidatesTokenCount': 5,
      'thoughtsTokenCount': 200,
      'totalTokenCount': 218,
    };

    GeminiProvider gemini(http.Client client) =>
        GeminiProvider(apiKey: 'k', httpClient: AiHttpClient(client: client));

    test('chat usage and cost include thoughts and tool-use prompt', () async {
      final response = await gemini(MockClient(
              (_) async => _json(_geminiResponse('42', usage: usage))))
          .chat(userRequest('x'));

      expect(response.usage.inputTokens, 13);
      expect(response.usage.outputTokens, 205);
      expect(response.usage.totalTokens, 218);
      final tracker =
          AiCostTracker(pricing: const AiPricing(outputCostPerToken: 1))
            ..addUsage(response.usage);
      expect(tracker.estimatedCost, 205);
    });

    test('stream usage includes thoughts', () async {
      final chunks = await gemini(MockClient.streaming((_, __) async =>
              sseResponse([_geminiResponse('42', usage: usage)])))
          .stream(userRequest('x'))
          .toList();
      expect(chunks.last.usage?.outputTokens, 205);
    });

    test('counts stay null when Gemini omits them', () async {
      final response = await gemini(MockClient((_) async =>
              _json(_geminiResponse('x', usage: {'totalTokenCount': 1}))))
          .chat(userRequest('x'));
      expect(response.usage.inputTokens, isNull);
      expect(response.usage.outputTokens, isNull);
    });
  });

  group('AIP-05: Anthropic sampling parameters', () {
    Future<Map<String, dynamic>> sentBody({
      String? model,
      String apiVersion = '2023-06-01',
      AiLogger? logger,
    }) async {
      late Map<String, dynamic> body;
      final ai = AiClient(
        logger: logger,
        provider: AiProvider.anthropic(
          apiKey: 'k',
          apiVersion: apiVersion,
          httpClient: AiHttpClient(
            client: MockClient((req) async {
              body = jsonDecode(req.body) as Map<String, dynamic>;
              return _json(_anthropicMessage([
                {'type': 'text', 'text': 'ok'},
              ]));
            }),
          ),
        ),
      );
      await ai.chat(
        messages: [_user],
        model: model,
        temperature: 0.2,
        topP: 0.9,
        stop: ['END'],
      );
      return body;
    }

    test('are omitted for the default model', () async {
      final body = await sentBody();
      expect(body['model'], 'claude-sonnet-5');
      expect(body.containsKey('temperature'), isFalse);
      expect(body.containsKey('top_p'), isFalse);
      expect(body['stop_sequences'], ['END']);
    });

    test('are kept for older models that accept them', () async {
      final body = await sentBody(model: 'claude-3-5-haiku-20241022');
      expect(body['temperature'], 0.2);
      expect(body['top_p'], 0.9);
    });

    test('Claude 4.x gets only temperature when both are set', () async {
      for (final model in ['claude-sonnet-4-5', 'claude-opus-4-1']) {
        final body = await sentBody(model: model);
        expect(body['temperature'], 0.2, reason: model);
        expect(body.containsKey('top_p'), isFalse, reason: model);
      }
      expect(
          anthropicSamplingToSend('claude-sonnet-4-5', '2023-06-01',
              temperature: false, topP: true),
          (temperature: false, topP: true));
    });

    test('are omitted on API version 2026-10-21 for every model', () async {
      final body =
          await sentBody(model: 'claude-sonnet-4-5', apiVersion: '2026-10-21');
      expect(body.containsKey('temperature'), isFalse);
    });

    test('model table', () {
      const accepts = [
        'claude-3-haiku-20240307',
        'claude-3-7-sonnet-latest',
        'claude-3.5-sonnet',
        'claude-sonnet-4-20250514',
        'claude-sonnet-4-5',
        'claude-sonnet-4-5-20250929',
        'claude-opus-4-1',
        'claude-opus-4-6',
        'claude-haiku-4-5',
      ];
      const rejects = [
        'claude-sonnet-5',
        'claude-sonnet-5-5',
        'claude-opus-4-7',
        'claude-opus-5',
        'claude-haiku-5-5',
        'claude-fable-5-1',
        'my-proxy-model',
      ];
      for (final m in accepts) {
        expect(anthropicAcceptsSampling(m, '2023-06-01'), isTrue, reason: m);
        expect(anthropicAcceptsSampling(m, '2026-10-21'), isFalse, reason: m);
      }
      for (final m in rejects) {
        expect(anthropicAcceptsSampling(m, '2023-06-01'), isFalse, reason: m);
      }
    });

    test('a warning is logged once per model', () async {
      final log = RecordingLogger();
      final ai = AiClient(
        logger: log,
        provider: AiProvider.anthropic(
          apiKey: 'k',
          httpClient: AiHttpClient(
            client: MockClient((_) async => _json(_anthropicMessage([
                  {'type': 'text', 'text': 'ok'},
                ]))),
          ),
        ),
      );
      List<String> warnings() =>
          log.lines.where((l) => l.startsWith('WARNING')).toList();

      await ai.chat(messages: [_user]);
      expect(warnings(), isEmpty, reason: 'no sampling parameters set');
      await ai.chat(messages: [_user], temperature: 0.2);
      await ai.chat(messages: [_user], topP: 0.5);
      await ai.stream(messages: [_user], temperature: 0.2).drain<void>();
      expect(warnings(), hasLength(1));
      expect(warnings().single, contains('claude-sonnet-5'));
      await ai
          .chat(messages: [_user], temperature: 0.2, model: 'claude-opus-5');
      await ai.chat(
          messages: [_user], temperature: 0.2, model: 'claude-sonnet-4-5');
      expect(warnings(), hasLength(2));
      // Claude 4.x with both parameters: topP is dropped, warned once.
      for (var i = 0; i < 2; i++) {
        await ai.chat(
            messages: [_user],
            temperature: 0.2,
            topP: 0.9,
            model: 'claude-sonnet-4-5');
      }
      expect(warnings(), hasLength(3));
      expect(warnings().last, contains('only one of temperature/topP'));
    });
  });

  group('AIP-06: OpenAI default model', () {
    Future<Map<String, dynamic>> sentBody(
      AiProvider Function(AiHttpClient) create, {
      String? model,
      bool tools = false,
    }) async {
      late Map<String, dynamic> body;
      final http = AiHttpClient(
        client: MockClient((req) async {
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return _json(_openAiCompletion(content: 'ok'));
        }),
      );
      await AiClient(provider: create(http)).chat(
        messages: [_user],
        model: model,
        tools: tools ? [_weatherTool()] : null,
      );
      return body;
    }

    AiProvider openAi(AiHttpClient c) =>
        AiProvider.openAI(apiKey: 'k', httpClient: c);
    AiProvider custom(AiHttpClient c) =>
        AiProvider.custom(baseUrl: 'http://x/v1', apiKey: '', httpClient: c);

    test('is gpt-6-luna for OpenAI and custom providers', () async {
      expect(OpenAiProvider.defaultModel, 'gpt-6-luna');
      expect(CustomProvider.defaultModel, 'gpt-6-luna');
      expect((await sentBody(openAi))['model'], 'gpt-6-luna');
      expect((await sentBody(custom))['model'], 'gpt-6-luna');
    });

    test('gpt-6-luna with tools sends reasoning_effort none', () async {
      expect((await sentBody(openAi, tools: true))['reasoning_effort'], 'none');
      expect(
          (await sentBody(openAi,
              tools: true, model: 'gpt-6-luna-2026-10-01'))['reasoning_effort'],
          'none');
    });

    test('reasoning_effort is not sent otherwise', () async {
      expect((await sentBody(openAi)).containsKey('reasoning_effort'), isFalse);
      expect(
          (await sentBody(openAi, tools: true, model: 'gpt-5'))
              .containsKey('reasoning_effort'),
          isFalse);
      expect(
          (await sentBody(custom, tools: true)).containsKey('reasoning_effort'),
          isFalse);
    });
  });

  group('AIP-07: OpenAI streams end with the finish reason', () {
    Map<String, dynamic> delta(Map<String, dynamic> d, [String? finish]) => {
          'choices': [
            {'index': 0, 'delta': d, 'finish_reason': finish},
          ],
          'usage': null,
        };
    const usageChunk = {
      'choices': <Object>[],
      'usage': {'prompt_tokens': 7, 'completion_tokens': 2, 'total_tokens': 9},
    };

    Future<List<AiStreamChunk>> stream(List<Object> events,
            {bool custom = false}) =>
        (custom
                ? CustomProvider(
                    baseUrl: 'http://x/v1',
                    apiKey: '',
                    httpClient: AiHttpClient(
                        client: MockClient.streaming(
                            (_, __) async => sseResponse(events, done: true))),
                  )
                : OpenAiProvider(
                    apiKey: 'k',
                    httpClient: AiHttpClient(
                        client: MockClient.streaming(
                            (_, __) async => sseResponse(events, done: true))),
                  ) as AiProvider)
            .stream(userRequest('x'))
            .toList();

    test('the last chunk carries finishReason and usage', () async {
      final chunks = await stream([
        delta({'role': 'assistant', 'content': ''}),
        delta({'content': 'Hel'}),
        delta({'content': 'lo'}),
        delta({}, 'stop'),
        usageChunk,
      ]);
      expect(chunks.map((c) => c.text).join(), 'Hello');
      expect(chunks.last.finishReason, AiFinishReason.stop);
      expect(chunks.last.usage?.totalTokens, 9);
      expect(chunks.where((c) => c.finishReason != null), hasLength(1));
    });

    test('tool calls arrive in the last chunk', () async {
      final chunks = await stream([
        delta({
          'tool_calls': [
            {
              'index': 0,
              'id': 'c1',
              'function': {'name': 'get_weather', 'arguments': '{}'},
            },
          ],
        }),
        delta({}, 'tool_calls'),
        usageChunk,
      ]);
      expect(chunks.last.finishReason, AiFinishReason.toolCalls);
      expect(chunks.last.content.whereType<AiToolCallContent>(), hasLength(1));
      expect(chunks.last.usage?.totalTokens, 9);
    });

    test('the finish chunk is flushed when no usage chunk follows', () async {
      final chunks = await stream([
        delta({'content': 'Hi'}),
        delta({}, 'length'),
      ]);
      expect(chunks.last.finishReason, AiFinishReason.length);
      expect(chunks.map((c) => c.text).join(), 'Hi');
    });

    test('holding the finish chunk does not trip the idle timeout', () async {
      // Events 200 ms apart, idle timeout 500 ms: the finish chunk may only
      // be held until the usage chunk, not until the end of the stream.
      final events = [
        for (final t in ['a', 'b', 'c']) delta({'content': t}),
        delta({}, 'stop'),
        usageChunk,
      ];
      Stream<List<int>> slow() async* {
        for (final e in events) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          yield utf8.encode('data: ${jsonEncode(e)}\n\n');
        }
        await Future<void>.delayed(const Duration(milliseconds: 200));
        yield utf8.encode('data: [DONE]\n\n');
      }

      final ai = AiClient(
        provider: AiProvider.openAI(
          apiKey: 'k',
          httpClient: AiHttpClient(
            client: MockClient.streaming(
                (_, __) async => http.StreamedResponse(slow(), 200)),
          ),
        ),
        timeout: const Duration(milliseconds: 500),
        retryPolicy: AiRetryPolicy.none,
      );
      final chunks = await ai.stream(messages: [_user]).toList();
      expect(chunks.map((c) => c.text).join(), 'abc');
      expect(chunks.last.finishReason, AiFinishReason.stop);
      expect(chunks.last.usage?.totalTokens, 9);
    });

    test('custom providers (no usage chunk) are unchanged', () async {
      final chunks = await stream([
        delta({'content': 'Hi'}),
        delta({}, 'stop'),
      ], custom: true);
      expect(chunks.map((c) => c.finishReason), [null, AiFinishReason.stop]);
    });
  });

  group('AIP-08: invalid Gemini key', () {
    const invalidKey = {
      'error': {
        'code': 400,
        'message': 'API key not valid. Please pass a valid API key.',
        'status': 'INVALID_ARGUMENT',
        'details': [
          {
            '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
            'reason': 'API_KEY_INVALID',
            'domain': 'googleapis.com',
          },
        ],
      },
    };

    test('raises AiAuthenticationException', () async {
      final ai = AiClient(
        provider: AiProvider.gemini(
          apiKey: 'AIza-wrong',
          httpClient: AiHttpClient(
              client: MockClient((_) async => _json(invalidKey, 400))),
        ),
      );
      final error = await _errorOf(ai.chat(messages: [_user]));
      expect(error, isA<AiAuthenticationException>());
      final e = error as AiException;
      expect(e.message, contains('API key not valid'));
      expect(e.statusCode, 400);
      expect(e.provider, 'Gemini');
    });

    test('other 400s stay AiInvalidRequestException', () async {
      final client = AiHttpClient(
        client: MockClient((_) async => _json({
              'error': {
                'code': 400,
                'message': 'Mentions API_KEY_INVALID in text only',
                'status': 'INVALID_ARGUMENT',
              },
            }, 400)),
      );
      expect(
          await _errorOf(client.post(_url)), isA<AiInvalidRequestException>());
    });
  });

  group('AIP-09: Gemini tool results are JSON-normalised', () {
    Future<Object?> sentResponse(Object? result) async {
      late Map<String, dynamic> body;
      final provider = GeminiProvider(
        apiKey: 'k',
        httpClient: AiHttpClient(
          client: MockClient((req) async {
            body = jsonDecode(req.body) as Map<String, dynamic>;
            return _json(_geminiResponse('ok'));
          }),
        ),
      );
      await provider.chat(AiRequest(messages: [
        _user,
        AiMessage(role: AiMessageRole.tool, content: [
          AiToolResultContent(id: 'fc_1', name: 'issue_refund', result: result),
        ]),
      ]));
      final parts = ((body['contents'] as List).last as Map)['parts'] as List;
      return ((parts.single as Map)['functionResponse'] as Map)['response'];
    }

    test('DateTime values fall back to toString()', () async {
      expect(
        await sentResponse(
            {'amount': 40, 'issuedAt': DateTime.utc(2026, 11, 2)}),
        {'amount': 40, 'issuedAt': '2026-11-02 00:00:00.000Z'},
      );
    });

    test('objects use toJson(); other values are wrapped', () async {
      expect(await sentResponse(_Receipt()), {'id': 'r1'});
      expect(await sentResponse('Sunny'), {'result': 'Sunny'});
      expect(await sentResponse([1, 2]), {
        'result': [1, 2],
      });
      expect(await sentResponse(null), {'result': null});
    });
  });

  group('AIP-10: AiAgent never runs tools it cannot report back', () {
    AiResponse toolCall(String id) => AiResponse(
          message: AiMessage(role: AiMessageRole.assistant, content: [
            AiToolCallContent(id: id, name: 'refund', arguments: const {}),
          ]),
          finishReason: AiFinishReason.toolCalls,
        );

    late List<String> executed;
    late AiTool refund;
    setUp(() {
      executed = [];
      refund = AiTool(
        name: 'refund',
        description: 'Issues a refund',
        parameters: AiJsonSchema.object(properties: {}),
        execute: (_) async {
          executed.add('refund');
          return 'refunded';
        },
      );
    });

    test('the model answers after the last tool round', () async {
      final provider = FakeProvider(
        onChat: (r) => r.messages.last.role == AiMessageRole.tool
            ? textResponse('Refunded \$40.')
            : toolCall('c1'),
      );
      final agent = AiAgent(
          client: AiClient(provider: provider),
          tools: [refund],
          maxIterations: 1);
      expect(await agent.run('Refund A1001'), 'Refunded \$40.');
      expect(executed, hasLength(1));
      expect(provider.requests, hasLength(2));
    });

    test('tools requested after the limit are not executed', () async {
      var n = 0;
      final provider = FakeProvider(onChat: (_) => toolCall('c${n++}'));
      final agent = AiAgent(
          client: AiClient(provider: provider),
          tools: [refund],
          maxIterations: 1);
      final error = await _errorOf(agent.run('Refund A1001'));
      expect(error, isA<AiToolException>());
      expect((error as AiToolException).message, contains('1 iteration:'));
      expect(error.message, contains('refund'));
      expect(executed, hasLength(1), reason: 'only the reported round ran');
      expect(provider.requests, hasLength(2));
      // The executed round's result reached the model.
      expect(provider.requests.last.messages.last.role, AiMessageRole.tool);
    });

    test('maxIterations: 0 runs no tools', () async {
      final provider = FakeProvider(onChat: (_) => toolCall('c'));
      final agent = AiAgent(
          client: AiClient(provider: provider),
          tools: [refund],
          maxIterations: 0);
      expect(await _errorOf(agent.run('x')), isA<AiToolException>());
      expect(executed, isEmpty);
      expect(provider.requests, hasLength(1));
    });
  });

  group('AIP-11: timeouts and abortTrigger abort the HTTP request', () {
    late _HangingServer server;
    setUp(() async => server = await _HangingServer.start());
    tearDown(() => server.close());

    test('a chat timeout closes the connection', () async {
      final ai = AiClient(
        provider: AiProvider.openAI(apiKey: 'k', baseUrl: server.baseUrl),
        timeout: const Duration(milliseconds: 200),
        retryPolicy: AiRetryPolicy.none,
      );
      addTearDown(ai.close);

      expect(await _errorOf(ai.chat(messages: [_user])),
          isA<AiTimeoutException>());
      await server.waitUntilClosed(1);
    });

    test('every timed-out retry attempt is aborted', () async {
      final ai = AiClient(
        provider: AiProvider.openAI(apiKey: 'k', baseUrl: server.baseUrl),
        timeout: const Duration(milliseconds: 100),
        retryPolicy: const AiRetryPolicy(
          maxAttempts: 2,
          initialDelay: Duration(milliseconds: 1),
          jitter: false,
        ),
      );
      addTearDown(ai.close);

      expect(await _errorOf(ai.chat(messages: [_user])),
          isA<AiTimeoutException>());
      expect(server.connections, 3);
      await server.waitUntilClosed(3);
    });

    test('a completed abortTrigger aborts chat and is not retried', () async {
      final ai = AiClient(
        provider: AiProvider.openAI(apiKey: 'k', baseUrl: server.baseUrl),
        retryPolicy: const AiRetryPolicy(
            maxAttempts: 3, initialDelay: Duration(milliseconds: 1)),
        middlewares: [
          _AbortAfter(const Duration(milliseconds: 100)),
        ],
      );
      addTearDown(ai.close);

      final error = await _errorOf(ai.chat(messages: [_user]));
      expect(error, isA<AiTimeoutException>());
      expect('$error', contains('aborted'));
      await server.waitUntilClosed(1);
      expect(server.connections, 1);
    });

    test('abortTrigger aborts a stream that already started', () async {
      server.firstEvent = jsonEncode({
        'choices': [
          {
            'index': 0,
            'delta': {'content': 'Hi'},
            'finish_reason': null,
          },
        ],
      });
      final provider = OpenAiProvider(apiKey: 'k', baseUrl: server.baseUrl);
      addTearDown(provider.close);
      final abort = Completer<void>();

      final texts = <String>[];
      final error = await _errorOf(provider
          .stream(AiRequest(messages: [_user], abortTrigger: abort.future))
          .forEach((c) {
        texts.add(c.text);
        if (!abort.isCompleted) abort.complete();
      }));
      expect(texts, ['Hi']);
      expect(error, isA<AiTimeoutException>());
      await server.waitUntilClosed(1);
    });

    test('copyWith keeps abortTrigger', () {
      final trigger = Completer<void>().future;
      final request = AiRequest(messages: [_user], abortTrigger: trigger);
      expect(request.copyWith(model: 'm').abortTrigger, same(trigger));
    });
  });

  test('AIP-12: http >= 1.6.0 (fetch-based web client, abortable requests)',
      () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final constraint =
        RegExp(r'^\s+http:\s*\^?(\d+)\.(\d+)\.(\d+)\s*$', multiLine: true)
            .firstMatch(pubspec)!;
    final major = int.parse(constraint.group(1)!);
    final minor = int.parse(constraint.group(2)!);
    expect(major == 1 && minor >= 6, isTrue, reason: constraint.group(0));
  });

  group('AIP-13: OpenAI refusals are surfaced', () {
    const refusal = "I'm sorry, I can't help with that request.";

    AiClient client(http.Client c) => AiClient(
        provider: AiProvider.openAI(
            apiKey: 'k', httpClient: AiHttpClient(client: c)));

    test('chat returns the refusal as text with contentFilter', () async {
      final ai = client(
          MockClient((_) async => _json(_openAiCompletion(refusal: refusal))));
      final response = await ai.chat(messages: [_user]);
      expect(response.text, refusal);
      expect(response.finishReason, AiFinishReason.contentFilter);
    });

    test('generate reports the refusal', () async {
      final ai = client(
          MockClient((_) async => _json(_openAiCompletion(refusal: refusal))));
      final error = await _errorOf(ai.generate(
        prompt: 'x',
        schema: AiJsonSchema.object(
            properties: {'a': AiJsonSchema.string()}, required: ['a']),
        decoder: (j) => j,
      ));
      expect(error, isA<AiStructuredOutputException>());
      final e = error as AiStructuredOutputException;
      expect(e.message, contains('refused'));
      expect(e.rawResponse, refusal);
    });

    test('streamed refusals are text and end with contentFilter', () async {
      final ai = client(MockClient.streaming((_, __) async => sseResponse([
            {
              'choices': [
                {
                  'index': 0,
                  'delta': {'role': 'assistant', 'content': null},
                  'finish_reason': null,
                },
              ],
            },
            {
              'choices': [
                {
                  'index': 0,
                  'delta': {'refusal': "I'm sorry"},
                  'finish_reason': null,
                },
              ],
            },
            {
              'choices': [
                {
                  'index': 0,
                  'delta': <String, dynamic>{},
                  'finish_reason': 'stop'
                },
              ],
            },
          ], done: true)));
      final chunks = await ai.stream(messages: [_user]).toList();
      expect(chunks.map((c) => c.text).join(), "I'm sorry");
      expect(chunks.last.finishReason, AiFinishReason.contentFilter);
    });

    test('content with a null refusal is unaffected', () async {
      final ai = client(
          MockClient((_) async => _json(_openAiCompletion(content: 'Hello'))));
      final response = await ai.chat(messages: [_user]);
      expect(response.text, 'Hello');
      expect(response.finishReason, AiFinishReason.stop);
    });
  });

  group('AIP-14: generate() finds the first JSON object', () {
    Future<Object> generate(String reply) async {
      final ai =
          AiClient(provider: FakeProvider(onChat: (_) => textResponse(reply)));
      try {
        return await ai.generate(
          prompt: 'x',
          schema: AiJsonSchema.object(properties: {}),
          decoder: (j) => j,
        );
      } on AiStructuredOutputException catch (e) {
        return e;
      }
    }

    test('braces after the JSON are ignored', () async {
      expect(
        await generate('{"city": "Pune", "population": 7400000}\n\n'
            'Note: figures in {curly braces} are estimates.'),
        {'city': 'Pune', 'population': 7400000},
      );
    });

    test('braces before the JSON and inside strings are handled', () async {
      expect(await generate('Format {name}: {"a": "}{", "b": {"c": "\\"}"}}'), {
        'a': '}{',
        'b': {'c': '"}'},
      });
      expect(await generate('```json\n{"ok": true}\n```'), {'ok': true});
    });

    test('no valid object is an AiStructuredOutputException', () async {
      expect(await generate('{not json}'), isA<AiStructuredOutputException>());
      expect(await generate('no json'), isA<AiStructuredOutputException>());
      expect(
          await generate('{"truncated": '), isA<AiStructuredOutputException>());
    });
  });

  group('AIP-15: {{ name }} placeholders', () {
    test('are rendered', () {
      const t = AiPromptTemplate('Hello {{ name }}, order {{order}} shipped.');
      expect(t.variables, {'name', 'order'});
      expect(t.render({'name': 'Asha', 'order': 'A1001'}),
          'Hello Asha, order A1001 shipped.');
    });

    test('are reported when missing', () {
      expect(() => const AiPromptTemplate('Hi {{  name\t}}').render({}),
          throwsArgumentError);
    });
  });

  group('AIP-16: CustomProvider capabilities', () {
    test('default to the OpenAI set', () {
      final provider = CustomProvider(baseUrl: 'http://x/v1', apiKey: '');
      expect(provider.capabilities.embeddings, isTrue);
      expect(provider.capabilities.toolCalling, isTrue);
    });

    test('are configurable and enforced by AiClient', () async {
      const limited = AiCapabilities(streaming: true);
      expect(
          CustomProvider(
                  baseUrl: 'http://x/v1', apiKey: '', capabilities: limited)
              .capabilities,
          same(limited));
      final ai = AiClient(
        provider: AiProvider.custom(
            baseUrl: 'http://x/v1', apiKey: '', capabilities: limited),
      );
      expect(ai.provider.capabilities.embeddings, isFalse);
      expect(
          await _errorOf(ai.chat(messages: [_user], tools: [_weatherTool()])),
          isA<AiUnsupportedCapabilityException>());
    });
  });

  test('AIP-17: docs do not use retired or deprecated model ids', () {
    const retired = [
      'gemini-2.0-flash',
      'gemini-1.5',
      'text-embedding-004',
      'gpt-4o-mini',
    ];
    for (final path in [
      'README.md',
      'lib/src/models/ai_model.dart',
      'example/example.dart',
    ]) {
      final text = File(path).readAsStringSync();
      for (final id in retired) {
        // A migration note ("`old` → `new`") is allowed.
        final mentioned = text.replaceAll('`$id` →', '').contains(id);
        expect(mentioned, isFalse, reason: '$path mentions $id');
      }
    }
  });

  group('AIP-18: Retry-After on 5xx', () {
    test('is parsed into AiProviderException.retryAfter', () async {
      Future<Object> errorFor(Map<String, String> headers) => _errorOf(
          AiHttpClient(
              client: MockClient((_) async => http.Response(
                  '{"error": {"message": "overloaded"}}', 503,
                  headers: headers))).post(_url));
      expect(
          ((await errorFor({'retry-after': '2'})) as AiProviderException)
              .retryAfter,
          const Duration(seconds: 2));
      expect(
          ((await errorFor({'retry-after-ms': '250'})) as AiProviderException)
              .retryAfter,
          const Duration(milliseconds: 250));
      expect(((await errorFor({})) as AiProviderException).retryAfter, isNull);
    });

    Future<Duration> timeRetry(Duration retryAfter, Duration maxDelay) async {
      var calls = 0;
      final ai = AiClient(
        provider: FakeProvider(onChat: (_) {
          if (calls++ == 0) {
            throw AiProviderException('overloaded',
                statusCode: 503, retryAfter: retryAfter);
          }
          return textResponse('ok');
        }),
        retryPolicy: AiRetryPolicy(
          maxAttempts: 1,
          initialDelay: const Duration(milliseconds: 1),
          maxDelay: maxDelay,
          jitter: false,
        ),
      );
      final stopwatch = Stopwatch()..start();
      expect((await ai.chat(messages: [_user])).text, 'ok');
      return stopwatch.elapsed;
    }

    test('is honoured by RetryMiddleware', () async {
      expect(
          await timeRetry(
              const Duration(milliseconds: 300), const Duration(seconds: 5)),
          greaterThanOrEqualTo(const Duration(milliseconds: 280)));
    });

    test('is capped at maxDelay', () async {
      expect(
          await timeRetry(
              const Duration(seconds: 30), const Duration(milliseconds: 50)),
          lessThan(const Duration(seconds: 2)));
    });
  });

  group('AIP-19: ingestBatch respects embeddings input limits', () {
    late List<int> batchSizes;
    late int failOnRequest;
    late AiClient ai;

    setUp(() {
      batchSizes = [];
      failOnRequest = -1;
      ai = AiClient(
        provider: AiProvider.openAI(
          apiKey: 'k',
          httpClient: AiHttpClient(
            client: MockClient((req) async {
              final input = ((jsonDecode(req.body) as Map)['input'] as List)
                  .cast<String>();
              if (input.length > 2048) {
                return _json({
                  'error': {'message': "'\$.input' is invalid."},
                }, 400);
              }
              if (batchSizes.length == failOnRequest) {
                return _json({
                  'error': {'message': 'boom'},
                }, 400);
              }
              batchSizes.add(input.length);
              return _json({
                'data': [
                  for (var i = 0; i < input.length; i++)
                    {
                      'index': i,
                      'embedding': [double.parse(input[i].split(' ').last)],
                    },
                ],
              });
            }),
          ),
        ),
        retryPolicy: AiRetryPolicy.none,
      );
    });

    test('2500 documents go out in slices of 100, in order', () async {
      final store = _RecordingStore();
      final kb = AiKnowledgeBase(client: ai, store: store);
      await kb.ingestBatch(
          contents: [for (var i = 0; i < 2500; i++) 'FAQ entry $i']);

      expect(batchSizes, List.filled(25, 100));
      expect(store.documents, hasLength(2500));
      for (final i in [0, 99, 100, 1234, 2499]) {
        expect(store.documents[i].content, 'FAQ entry $i');
        expect(store.documents[i].embedding.vector, [i.toDouble()]);
      }
    });

    test('batchSize is configurable and validated', () async {
      final kb = AiKnowledgeBase(client: ai, store: _RecordingStore());
      await kb.ingestBatch(
          contents: [for (var i = 0; i < 5; i++) 'doc $i'], batchSize: 2);
      expect(batchSizes, [2, 2, 1]);
      expect(() => kb.ingestBatch(contents: ['a'], batchSize: 0),
          throwsArgumentError);
    });

    test('a failed slice stores nothing', () async {
      failOnRequest = 1;
      final store = _RecordingStore();
      final kb = AiKnowledgeBase(client: ai, store: store);
      expect(
          await _errorOf(kb
              .ingestBatch(contents: [for (var i = 0; i < 150; i++) 'doc $i'])),
          isA<AiInvalidRequestException>());
      expect(store.documents, isEmpty);
    });
  });

  // ── Follow-up decisions for 0.1.0 ─────────────────────────────────────

  group('abortTrigger on the client API', () {
    late _HangingServer server;
    setUp(() async => server = await _HangingServer.start());
    tearDown(() => server.close());

    AiClient hanging() {
      final ai = AiClient(
        provider: AiProvider.openAI(apiKey: 'k', baseUrl: server.baseUrl),
        retryPolicy: AiRetryPolicy.none,
      );
      addTearDown(ai.close);
      return ai;
    }

    test('chat(abortTrigger:) aborts the request', () async {
      final error = await _errorOf(hanging().chat(
        messages: [_user],
        abortTrigger: Future<void>.delayed(const Duration(milliseconds: 100)),
      ));
      expect(error, isA<AiTimeoutException>());
      await server.waitUntilClosed(1);
    });

    test('conversation.send(abortTrigger:) leaves the history unchanged',
        () async {
      final conversation = hanging().conversation();
      final error = await _errorOf(conversation.send(
        'hi',
        abortTrigger: Future<void>.delayed(const Duration(milliseconds: 100)),
      ));
      expect(error, isA<AiTimeoutException>());
      expect(conversation.messages, isEmpty);
      await server.waitUntilClosed(1);
    });

    test('stream, streamText, generate and conversation.stream pass it on',
        () async {
      final provider = FakeProvider(
        onChat: (_) => textResponse('{"a": 1}'),
        onStream: (_) => Stream.value(const AiStreamChunk(
            content: [AiTextContent('x')], finishReason: AiFinishReason.stop)),
      );
      final ai = AiClient(provider: provider);
      final trigger = Completer<void>().future;

      await ai.stream(messages: [_user], abortTrigger: trigger).drain<void>();
      await ai
          .streamText(messages: [_user], abortTrigger: trigger).drain<void>();
      await ai.generate(
        prompt: 'x',
        schema: AiJsonSchema.object(properties: {}),
        decoder: (j) => j,
        abortTrigger: trigger,
      );
      await ai.conversation().stream('x', abortTrigger: trigger).drain<void>();

      expect(provider.requests, hasLength(4));
      for (final r in provider.requests) {
        expect(r.abortTrigger, same(trigger));
      }
    });

    test('agent.run(abortTrigger:) starts no further tools or calls', () async {
      final cancel = Completer<void>();
      var executed = 0;
      final provider = FakeProvider(
        onChat: (_) => const AiResponse(
          message: AiMessage(role: AiMessageRole.assistant, content: [
            AiToolCallContent(id: 'c', name: 'work', arguments: {}),
          ]),
        ),
      );
      final tool = AiTool(
        name: 'work',
        description: 'd',
        parameters: AiJsonSchema.object(properties: {}),
        execute: (_) async {
          executed++;
          cancel.complete(); // e.g. the user pressed stop meanwhile
          return 'done';
        },
      );
      final agent =
          AiAgent(client: AiClient(provider: provider), tools: [tool]);

      final error =
          await _errorOf(agent.run('go', abortTrigger: cancel.future));
      expect(error, isA<AiTimeoutException>());
      expect(executed, 1);
      expect(provider.requests, hasLength(1));
      expect(provider.requests.single.abortTrigger, same(cancel.future));
    });
  });

  group('AiUsage reasoning and cached tokens', () {
    test('OpenAI', () async {
      final provider = OpenAiProvider(
        apiKey: 'k',
        httpClient: AiHttpClient(
          client: MockClient((_) async => _json({
                ..._openAiCompletion(content: 'ok'),
                'usage': {
                  'prompt_tokens': 100,
                  'completion_tokens': 50,
                  'total_tokens': 150,
                  'prompt_tokens_details': {'cached_tokens': 64},
                  'completion_tokens_details': {'reasoning_tokens': 30},
                },
              })),
        ),
      );
      final usage = (await provider.chat(userRequest('x'))).usage;
      expect(usage.inputTokens, 100);
      expect(usage.cachedInputTokens, 64);
      expect(usage.outputTokens, 50);
      expect(usage.reasoningTokens, 30);
    });

    test('Gemini', () async {
      final provider = GeminiProvider(
        apiKey: 'k',
        httpClient: AiHttpClient(
          client: MockClient((_) async => _json(_geminiResponse('ok', usage: {
                'promptTokenCount': 100,
                'cachedContentTokenCount': 80,
                'candidatesTokenCount': 5,
                'thoughtsTokenCount': 20,
                'totalTokenCount': 125,
              }))),
        ),
      );
      final usage = (await provider.chat(userRequest('x'))).usage;
      expect(usage.inputTokens, 100);
      expect(usage.cachedInputTokens, 80);
      expect(usage.outputTokens, 25);
      expect(usage.reasoningTokens, 20);
    });

    const anthropicUsage = {
      'input_tokens': 10,
      'cache_creation_input_tokens': 5,
      'cache_read_input_tokens': 100,
      'output_tokens': 7,
    };

    test('Anthropic counts cache reads and writes as input', () async {
      final provider = AnthropicProvider(
        apiKey: 'k',
        httpClient: AiHttpClient(
          client: MockClient((_) async => _json({
                ..._anthropicMessage([
                  {'type': 'text', 'text': 'ok'},
                ]),
                'usage': anthropicUsage,
              })),
        ),
      );
      final usage = (await provider.chat(userRequest('x'))).usage;
      expect(usage.inputTokens, 115);
      expect(usage.cachedInputTokens, 100);
      expect(usage.outputTokens, 7);
      expect(usage.totalTokens, 122);
    });

    test('Anthropic streams keep message_start input counts', () async {
      final provider = AnthropicProvider(
        apiKey: 'k',
        httpClient: AiHttpClient(
          client: MockClient.streaming((_, __) async => sseResponse([
                {
                  'type': 'message_start',
                  'message': {
                    'usage': {...anthropicUsage, 'output_tokens': 1},
                  },
                },
                {
                  'type': 'message_delta',
                  'delta': {'stop_reason': 'end_turn'},
                  'usage': {'output_tokens': 7, 'input_tokens': null},
                },
                {'type': 'message_stop'},
              ])),
        ),
      );
      final chunks = await provider.stream(userRequest('x')).toList();
      final usage = chunks.last.usage!;
      expect(usage.inputTokens, 115);
      expect(usage.cachedInputTokens, 100);
      expect(usage.outputTokens, 7);
    });

    test('AiCostTracker charges cached input at its own rate', () {
      const usage =
          AiUsage(inputTokens: 100, cachedInputTokens: 40, outputTokens: 10);
      final discounted = AiCostTracker(
        pricing: const AiPricing(
          inputCostPerToken: 1,
          cachedInputCostPerToken: 0.1,
          outputCostPerToken: 2,
        ),
      )..addUsage(usage);
      expect(discounted.estimatedCost, closeTo(60 + 4 + 20, 1e-9));
      expect(discounted.totalCachedInputTokens, 40);

      final flat = AiCostTracker(
          pricing: const AiPricing(inputCostPerToken: 1, outputCostPerToken: 2))
        ..addUsage(usage);
      expect(flat.estimatedCost, 120);
      expect((flat..reset()).totalCachedInputTokens, 0);
    });
  });

  group('Anthropic default max_tokens', () {
    Future<Object?> sentMaxTokens({String? model, int? maxTokens}) async {
      late Map<String, dynamic> body;
      final provider = AnthropicProvider(
        apiKey: 'k',
        httpClient: AiHttpClient(
          client: MockClient((req) async {
            body = jsonDecode(req.body) as Map<String, dynamic>;
            return _json(_anthropicMessage([
              {'type': 'text', 'text': 'ok'},
            ]));
          }),
        ),
      );
      await provider.chat(
          AiRequest(messages: [_user], model: model, maxTokens: maxTokens));
      return body['max_tokens'];
    }

    test('leaves room for thinking, and fits Claude 3.x limits', () async {
      expect(AnthropicProvider.defaultMaxTokens, 16000);
      expect(await sentMaxTokens(), 16000);
      expect(await sentMaxTokens(model: 'claude-haiku-4-5'), 16000);
      expect(await sentMaxTokens(model: 'claude-3-haiku-20240307'), 4096);
      expect(await sentMaxTokens(model: 'claude-3-5-sonnet-latest'), 4096);
      expect(await sentMaxTokens(maxTokens: 300), 300);
    });
  });

  group('provider names in exceptions', () {
    test('client-side errors use the same short names as HTTP errors',
        () async {
      final custom = AiClient(
        provider: AiProvider.custom(
            baseUrl: 'http://x/v1',
            apiKey: '',
            capabilities: const AiCapabilities()),
      );
      final error = await _errorOf(custom.stream(messages: [_user]).toList());
      expect((error as AiException).provider, 'Custom');

      final timeout = AiClient(
        provider: AiProvider.openAI(
          apiKey: 'k',
          httpClient: AiHttpClient(
            client: MockClient((_) => Completer<http.Response>().future),
          ),
        ),
        timeout: const Duration(milliseconds: 50),
        retryPolicy: AiRetryPolicy.none,
      );
      final timedOut = await _errorOf(timeout.chat(messages: [_user]));
      expect((timedOut as AiTimeoutException).provider, 'OpenAI');
    });

    test('other providers use their type name', () async {
      final ai = AiClient(
          provider: FakeProvider(capabilities: const AiCapabilities()));
      final error =
          await _errorOf(ai.chat(messages: [_user], tools: [_weatherTool()]));
      expect(error, isA<AiUnsupportedCapabilityException>());
      expect((error as AiException).provider, 'FakeProvider');
      final agentError = await _errorOf(AiAgent(
        client: AiClient(
          provider: FakeProvider(
            onChat: (_) => const AiResponse(
              message: AiMessage(role: AiMessageRole.assistant, content: [
                AiToolCallContent(id: 'c', name: 'get_weather', arguments: {}),
              ]),
            ),
          ),
        ),
        tools: [_weatherTool()],
        maxIterations: 0,
      ).run('x'));
      expect((agentError as AiToolException).provider, 'FakeProvider');
    });
  });

  group('AiKnowledgeBase cancellation (0.1.1)', () {
    test('ask passes the trigger to the answer request', () async {
      final provider = FakeProvider();
      final kb = AiKnowledgeBase(client: AiClient(provider: provider));
      await kb.ingest(id: 'a', content: 'Dart was created by Google.');
      final trigger = Completer<void>().future;

      await kb.ask('Who created Dart?', abortTrigger: trigger);
      expect(provider.requests.single.abortTrigger, same(trigger));
    });

    test('ask does not start the answer once the trigger fired', () async {
      final provider = FakeProvider();
      final kb = AiKnowledgeBase(client: AiClient(provider: provider));
      final error = await _errorOf(
          kb.ask('Who created Dart?', abortTrigger: Future<void>.value()));
      expect(error, isA<AiTimeoutException>());
      expect((error as AiException).provider, 'FakeProvider');
      expect(provider.requests, isEmpty);
    });

    test('ingestBatch stops between slices and stores nothing', () async {
      final cancel = Completer<void>();
      var requests = 0;
      final ai = AiClient(
        provider: AiProvider.openAI(
          apiKey: 'k',
          httpClient: AiHttpClient(
            client: MockClient((req) async {
              requests++;
              if (!cancel.isCompleted) cancel.complete();
              final n = ((jsonDecode(req.body) as Map)['input'] as List).length;
              return _json({
                'data': [
                  for (var i = 0; i < n; i++)
                    {
                      'index': i,
                      'embedding': [1.0],
                    },
                ],
              });
            }),
          ),
        ),
      );
      final store = _RecordingStore();
      final kb = AiKnowledgeBase(client: ai, store: store);

      final error = await _errorOf(kb.ingestBatch(
        contents: [for (var i = 0; i < 300; i++) 'doc $i'],
        abortTrigger: cancel.future,
      ));
      expect(error, isA<AiTimeoutException>());
      expect((error as AiException).provider, 'OpenAI');
      expect(requests, 1);
      expect(store.documents, isEmpty);
    });

    test('a trigger completed before ingestBatch sends nothing', () async {
      var requests = 0;
      final ai = AiClient(
        provider: AiProvider.openAI(
          apiKey: 'k',
          httpClient: AiHttpClient(
            client: MockClient((_) async {
              requests++;
              return _json({'data': <Object>[]});
            }),
          ),
        ),
      );
      final kb = AiKnowledgeBase(client: ai, store: _RecordingStore());
      expect(
          await _errorOf(kb.ingestBatch(
              contents: ['a'], abortTrigger: Future<void>.value())),
          isA<AiTimeoutException>());
      expect(requests, 0);
    });
  });
}

// ── Helpers ─────────────────────────────────────────────────────────────

final _url = Uri.parse('https://api.example.com/v1/chat');
final _user = AiMessage.user('hi');

Future<Object> _errorOf(Future<Object?> future) async {
  try {
    await future;
  } catch (e) {
    return e;
  }
  fail('expected an error');
}

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, dynamic> _openAiCompletion({String? content, String? refusal}) => {
      'choices': [
        {
          'index': 0,
          'message': {
            'role': 'assistant',
            'content': content,
            'refusal': refusal,
          },
          'finish_reason': 'stop',
        },
      ],
      'usage': {'prompt_tokens': 1, 'completion_tokens': 1, 'total_tokens': 2},
    };

Map<String, dynamic> _geminiResponse(String text,
        {Map<String, dynamic>? usage}) =>
    {
      'candidates': [
        {
          'content': {
            'role': 'model',
            'parts': [
              {'text': text},
            ],
          },
          'finishReason': 'STOP',
        },
      ],
      if (usage != null) 'usageMetadata': usage,
    };

Map<String, dynamic> _anthropicMessage(
  List<Map<String, dynamic>> content, {
  String stopReason = 'end_turn',
}) =>
    {
      'type': 'message',
      'role': 'assistant',
      'content': content,
      'stop_reason': stopReason,
      'usage': {'input_tokens': 10, 'output_tokens': 5},
    };

Map<String, dynamic> _toolUse(
        String id, String name, Map<String, dynamic> input) =>
    {'type': 'tool_use', 'id': id, 'name': name, 'input': input};

Map<String, dynamic> _blockStart(int index, Map<String, dynamic> block) =>
    {'type': 'content_block_start', 'index': index, 'content_block': block};

Map<String, dynamic> _blockDelta(int index, Map<String, dynamic> delta) =>
    {'type': 'content_block_delta', 'index': index, 'delta': delta};

AiTool _weatherTool() => AiTool(
      name: 'get_weather',
      description: 'Gets the weather',
      parameters: AiJsonSchema.object(
        properties: {'city': AiJsonSchema.string()},
        required: ['city'],
      ),
      execute: (args) async => 'Sunny',
    );

class _Receipt {
  Map<String, dynamic> toJson() => {'id': 'r1'};
}

class RecordingLogger implements AiLogger {
  final lines = <String>[];

  String get all => lines.join('\n');

  @override
  void debug(String message) => lines.add('DEBUG $message');

  @override
  void info(String message) => lines.add('INFO $message');

  @override
  void warning(String message) => lines.add('WARNING $message');

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      lines.add('ERROR $message ${error ?? ''}');
}

/// Sets an abort trigger that fires after [delay].
class _AbortAfter extends AiMiddleware {
  _AbortAfter(this.delay);

  final Duration delay;

  @override
  Future<AiResponse> handleChat(AiRequest request, AiRequestHandler next) =>
      next(request.copyWith(abortTrigger: Future<void>.delayed(delay)));
}

class _RecordingStore implements AiVectorStore {
  final documents = <AiDocument>[];

  @override
  Future<void> add(AiDocument document) async => documents.add(document);

  @override
  Future<void> addAll(List<AiDocument> documents) async =>
      this.documents.addAll(documents);

  @override
  Future<void> clear() async => documents.clear();

  @override
  Future<void> delete(String id) async =>
      documents.removeWhere((d) => d.id == id);

  @override
  Future<List<AiSearchResult>> search(AiEmbedding query, {int k = 4}) async =>
      const [];
}

/// A server that never finishes its responses and records when clients
/// close their connections.
class _HangingServer {
  _HangingServer._(this._server) {
    _server.listen(_handle);
  }

  static Future<_HangingServer> start() async =>
      _HangingServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final _sockets = <Socket>[];
  final _closedEvents = StreamController<void>.broadcast();

  /// When set, sent as one SSE event before the server stalls.
  String? firstEvent;

  int connections = 0;
  int closed = 0;

  String get baseUrl => 'http://127.0.0.1:${_server.port}/v1';

  Future<void> _handle(HttpRequest request) async {
    connections++;
    await request.drain<void>();
    final socket = await request.response.detachSocket(writeHeaders: false);
    _sockets.add(socket);
    final event = firstEvent;
    if (event != null) {
      final chunk = utf8.encode('data: $event\n\n');
      socket
        ..write('HTTP/1.1 200 OK\r\n'
            'content-type: text/event-stream\r\n'
            'transfer-encoding: chunked\r\n\r\n')
        ..write('${chunk.length.toRadixString(16)}\r\n')
        ..add(chunk)
        ..write('\r\n');
    }
    socket.listen(
      (_) {},
      onDone: _markClosed,
      onError: (Object _) => _markClosed(),
      cancelOnError: true,
    );
  }

  void _markClosed() {
    closed++;
    _closedEvents.add(null);
  }

  /// Waits until [count] client connections have been closed.
  Future<void> waitUntilClosed(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (closed < count) {
      final left = deadline.difference(DateTime.now());
      if (left <= Duration.zero) {
        fail('only $closed of $count connections were closed by the client');
      }
      await _closedEvents.stream.first.timeout(left, onTimeout: () {});
    }
  }

  Future<void> close() async {
    for (final s in _sockets) {
      s.destroy();
    }
    await _closedEvents.close();
    await _server.close(force: true);
  }
}
