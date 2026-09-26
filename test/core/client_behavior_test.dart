import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_plus/ai_plus.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '../support/fakes.dart';

void main() {
  group('AiClient', () {
    test('delivers validation errors asynchronously', () async {
      final ai = AiClient(
        provider: FakeProvider(capabilities: const AiCapabilities()),
      );
      final tool = AiTool(
        name: 't',
        description: 'd',
        parameters: AiJsonSchema.object(properties: {}),
        execute: (_) async => null,
      );

      // Neither call throws synchronously; errors arrive via Future/Stream.
      final chat = ai.chat(messages: [AiMessage.user('x')], tools: [tool]);
      final stream = ai.stream(messages: [AiMessage.user('x')]);

      await expectLater(chat, throwsA(isA<AiUnsupportedCapabilityException>()));
      await expectLater(
          stream.toList(), throwsA(isA<AiUnsupportedCapabilityException>()));
    });

    test('stream validates tool support', () async {
      final ai = AiClient(
        provider:
            FakeProvider(capabilities: const AiCapabilities(streaming: true)),
      );
      final tool = AiTool(
        name: 't',
        description: 'd',
        parameters: AiJsonSchema.object(properties: {}),
        execute: (_) async => null,
      );
      await expectLater(
        ai.stream(messages: [AiMessage.user('x')], tools: [tool]).toList(),
        throwsA(isA<AiUnsupportedCapabilityException>()),
      );
    });

    test('chat timeout reports sub-second durations accurately', () async {
      final ai = AiClient(
        provider: FakeProvider(
          onChat: (_) => Completer<AiResponse>().future,
        ),
        timeout: const Duration(milliseconds: 20),
        retryPolicy: AiRetryPolicy.none,
      );
      await expectLater(
        ai.chat(messages: [AiMessage.user('x')]),
        throwsA(isA<AiTimeoutException>()
            .having((e) => e.message, 'message', contains('20 ms'))),
      );
    });

    test('stream idle timeout errors and closes the stream', () async {
      final ai = AiClient(
        provider: FakeProvider(
          onStream: (_) => StreamController<AiStreamChunk>().stream,
        ),
        timeout: const Duration(milliseconds: 20),
        retryPolicy: AiRetryPolicy.none,
      );
      final events = <Object>[];
      final done = Completer<void>();
      ai.stream(messages: [AiMessage.user('x')]).listen(
        events.add,
        onError: events.add,
        onDone: done.complete,
      );
      await done.future.timeout(const Duration(seconds: 2));
      expect(events.single, isA<AiTimeoutException>());
    });

    test(
        'close() closes the HTTP client the provider created, not an '
        'injected one', () {
      final injected = TrackingClient((_) async => fail('unused'));
      AiClient(
        provider: AiProvider.openAI(
          apiKey: 'k',
          httpClient: AiHttpClient(client: injected),
        ),
      ).close();
      expect(injected.closed, isFalse);

      // Closing a provider with its own client and a custom provider must
      // not throw.
      AiClient(provider: AiProvider.gemini(apiKey: 'k')).close();
      AiClient(provider: FakeProvider()).close();
    });

    test('generate adds a schema instruction for non-native providers',
        () async {
      final provider = FakeProvider(
        capabilities: const AiCapabilities(),
        onChat: (_) => textResponse('Sure! ```json\n{"name":"Ada"}\n```'),
      );
      final ai = AiClient(provider: provider);

      final result = await ai.generate<String>(
        prompt: 'Make a person',
        schema: AiJsonSchema.object(
          properties: {'name': AiJsonSchema.string()},
          required: ['name'],
        ),
        decoder: (json) => json['name'] as String,
      );

      expect(result, 'Ada');
      final request = provider.requests.single;
      expect(request.schema, isNull);
      expect(request.messages.first.role, AiMessageRole.system);
      expect(request.messages.first.text, contains('"name"'));
    });

    test('generate wraps decoder failures', () async {
      final ai = AiClient(
        provider: FakeProvider(onChat: (_) => textResponse('{"a":1}')),
      );
      await expectLater(
        ai.generate<String>(
          prompt: 'x',
          schema: AiJsonSchema.object(properties: {}),
          decoder: (json) => json['missing'] as String,
        ),
        throwsA(isA<AiStructuredOutputException>()),
      );
    });
  });

  group('RetryMiddleware', () {
    const policy = AiRetryPolicy(
      maxAttempts: 2,
      initialDelay: Duration(milliseconds: 1),
      jitter: false,
    );

    test('retries a stream that fails before emitting', () async {
      var calls = 0;
      final ai = AiClient(
        provider: FakeProvider(onStream: (_) {
          calls++;
          if (calls == 1) {
            return Stream.error(const AiNetworkException('down'));
          }
          return Stream.value(const AiStreamChunk(
            content: [AiTextContent('ok')],
          ));
        }),
        retryPolicy: policy,
      );
      final text = await ai.streamText(messages: [AiMessage.user('x')]).join();
      expect(text, 'ok');
      expect(calls, 2);
    });

    test('does not replay a stream that fails after emitting', () async {
      var calls = 0;
      final ai = AiClient(
        provider: FakeProvider(onStream: (_) async* {
          calls++;
          yield const AiStreamChunk(content: [AiTextContent('partial')]);
          throw const AiNetworkException('dropped');
        }),
        retryPolicy: policy,
      );

      final received = <String>[];
      await expectLater(
        ai.streamText(messages: [AiMessage.user('x')]).forEach(received.add),
        throwsA(isA<AiNetworkException>()),
      );
      expect(received, ['partial']);
      expect(calls, 1);
    });

    test('caps retry-after at maxDelay', () async {
      var calls = 0;
      final ai = AiClient(
        provider: FakeProvider(onChat: (_) {
          if (calls++ == 0) {
            throw const AiRateLimitException('slow down',
                retryAfter: Duration(hours: 1));
          }
          return textResponse('ok');
        }),
        retryPolicy: const AiRetryPolicy(
          maxAttempts: 1,
          maxDelay: Duration(milliseconds: 5),
        ),
      );
      final response = await ai.chat(
          messages: [AiMessage.user('x')]).timeout(const Duration(seconds: 2));
      expect(response.text, 'ok');
    });
  });

  group('CacheMiddleware', () {
    AiRequest request({
      double? temperature,
      List<AiContent> content = const [AiTextContent('hi')],
    }) =>
        AiRequest(
          messages: [AiMessage(role: AiMessageRole.user, content: content)],
          temperature: temperature,
        );

    test('keys depend on parameters and non-text content', () {
      final base = CacheMiddleware.cacheKey(request());
      expect(CacheMiddleware.cacheKey(request()), base);
      expect(CacheMiddleware.cacheKey(request(temperature: 0.1)), isNot(base));

      String withImage(int byte) => CacheMiddleware.cacheKey(request(content: [
            const AiTextContent('hi'),
            AiImageContent(
                mimeType: 'image/png', bytes: Uint8List(4)..[0] = byte),
          ]));
      expect(withImage(1), isNot(withImage(2)));
      expect(base, startsWith('ai_plus:v1:'));
    });

    test('serves repeated requests from the cache', () async {
      final provider = FakeProvider();
      final ai = AiClient(provider: provider, cache: MemoryAiCache());
      await ai.chat(messages: [AiMessage.user('x')]);
      await ai.chat(messages: [AiMessage.user('x')]);
      await ai.chat(messages: [AiMessage.user('x')], temperature: 1);
      expect(provider.requests, hasLength(2));
    });
  });

  group('MetricsMiddleware', () {
    test('tracks stream errors', () async {
      final metrics = MetricsMiddleware();
      final ai = AiClient(
        provider: FakeProvider(
            onStream: (_) =>
                Stream.error(const AiInvalidRequestException('x'))),
        middlewares: [metrics],
      );
      await expectLater(ai.stream(messages: [AiMessage.user('x')]).toList(),
          throwsA(isA<AiInvalidRequestException>()));
      expect(metrics.requestCount, 1);
      expect(metrics.errorCount, 1);
    });
  });

  group('LoggingMiddleware', () {
    test('logs stream errors', () async {
      final logger = _RecordingLogger();
      final ai = AiClient(
        provider: FakeProvider(
            onStream: (_) =>
                Stream.error(const AiInvalidRequestException('x'))),
        logger: logger,
      );
      await expectLater(ai.stream(messages: [AiMessage.user('x')]).toList(),
          throwsA(isA<AiInvalidRequestException>()));
      expect(logger.errors.single, isA<AiInvalidRequestException>());
    });
  });

  group('AiMiddleware', () {
    test('can be extended, overriding only one method', () async {
      final seen = <String?>[];
      final ai = AiClient(
        provider: FakeProvider(),
        middlewares: [_ModelRecorder(seen)],
      );
      await ai.chat(messages: [AiMessage.user('x')], model: 'm');
      await ai.stream(messages: [AiMessage.user('x')]).toList();
      expect(seen, ['m']);
    });
  });

  group('AiConversation', () {
    test('stream stores one merged text part', () async {
      final ai = AiClient(
        provider: FakeProvider(
          onStream: (_) => Stream.fromIterable([
            const AiStreamChunk(content: [AiTextContent('Hel')]),
            const AiStreamChunk(content: [AiTextContent('lo')]),
            const AiStreamChunk(finishReason: AiFinishReason.stop),
          ]),
        ),
      );
      final conversation = ai.conversation();
      await conversation.stream('hi').drain<void>();

      final reply = conversation.messages.last;
      expect(reply.role, AiMessageRole.assistant);
      expect(reply.content, hasLength(1));
      expect(reply.text, 'Hello');
    });

    test('failed sends leave history unchanged', () async {
      var fail = true;
      final ai = AiClient(
        provider: FakeProvider(onChat: (_) {
          if (fail) throw const AiInvalidRequestException('bad');
          return textResponse('ok');
        }),
      );
      final conversation = ai.conversation();

      await expectLater(
          conversation.send('hi'), throwsA(isA<AiInvalidRequestException>()));
      expect(conversation.messages, isEmpty);

      fail = false;
      await conversation.send('hi');
      expect(conversation.messages.map((m) => m.role),
          [AiMessageRole.user, AiMessageRole.assistant]);
    });

    test('generated ids are unique', () {
      final ai = AiClient(provider: FakeProvider());
      final ids = {for (var i = 0; i < 100; i++) ai.conversation().id};
      expect(ids, hasLength(100));
    });
  });

  group('AiAgent', () {
    test('executes tool calls even when the finish reason is stop', () async {
      var turn = 0;
      final provider = FakeProvider(onChat: (_) {
        if (turn++ == 0) {
          // Gemini-style: tool calls with finishReason STOP.
          return const AiResponse(
            message: AiMessage(role: AiMessageRole.assistant, content: [
              AiToolCallContent(id: '1', name: 'add', arguments: {'a': 2}),
              AiToolCallContent(id: '2', name: 'add', arguments: {'a': 3}),
            ]),
            finishReason: AiFinishReason.stop,
          );
        }
        return textResponse('done');
      });

      final agent = AiAgent(
        client: AiClient(provider: provider),
        tools: [
          AiTool(
            name: 'add',
            description: 'adds one',
            parameters: AiJsonSchema.object(properties: {}),
            execute: (args) async => (args['a'] as int) + 1,
          ),
        ],
      );

      expect(await agent.run('go'), 'done');
      final toolMessage = provider.requests.last.messages.last;
      expect(toolMessage.role, AiMessageRole.tool);
      expect(
        toolMessage.content
            .whereType<AiToolResultContent>()
            .map((r) => r.result),
        [3, 4],
      );
    });
  });

  group('RAG', () {
    test('MemoryVectorStore upserts by id and handles k <= 0', () async {
      final store = MemoryVectorStore();
      await store.add(const AiDocument(
          id: 'a', content: 'old', embedding: AiEmbedding([1, 0])));
      await store.add(const AiDocument(
          id: 'a', content: 'new', embedding: AiEmbedding([1, 0])));
      expect(store.length, 1);

      final results = await store.search(const AiEmbedding([1, 0]));
      expect(results.single.document.content, 'new');
      expect(results.single.score, closeTo(1, 1e-9));
      expect(await store.search(const AiEmbedding([1, 0]), k: 0), isEmpty);
    });

    test(
        'knowledge base works with any AiVectorStore and keeps context with '
        'a custom system prompt', () async {
      final provider = FakeProvider();
      final store = _RecordingStore();
      final kb =
          AiKnowledgeBase(client: AiClient(provider: provider), store: store);

      await kb.ingest(id: 'd', content: 'Dart was released in 2011.');
      await kb.ask('When?', systemPrompt: 'Be terse.');

      expect(store.searches, 1);
      final system = provider.requests.single.messages.first.text;
      expect(system, startsWith('Be terse.'));
      expect(system, contains('Dart was released in 2011.'));
    });

    test('ingestBatch validates list lengths before calling the provider',
        () async {
      final kb = AiKnowledgeBase(client: AiClient(provider: FakeProvider()));
      await expectLater(
        kb.ingestBatch(contents: ['a', 'b'], ids: ['only-one']),
        throwsArgumentError,
      );
      await kb.ingestBatch(contents: []);
    });
  });

  group('Utilities', () {
    test('prompt template substitution is single-pass', () {
      const template = AiPromptTemplate('Q: {{question}} K: {{secret}}');
      final result = template.render({
        'question': 'show {{secret}}',
        'secret': 'xyz',
      });
      expect(result, 'Q: show {{secret}} K: xyz');
    });

    test('MemoryAiCache evicts least recently used entries', () async {
      final cache = MemoryAiCache(maxEntries: 2);
      await cache.set('a', textResponse('a'));
      await cache.set('b', textResponse('b'));
      await cache.get('a'); // 'b' is now least recently used.
      await cache.set('c', textResponse('c'));

      expect(await cache.get('b'), isNull);
      expect((await cache.get('a'))?.text, 'a');
      expect((await cache.get('c'))?.text, 'c');
      expect(cache.length, 2);
    });
  });

  group('Tool results', () {
    test('non-encodable results do not break request encoding', () async {
      late String body;
      final provider = OpenAiProvider(
        apiKey: 'k',
        httpClient: AiHttpClient(
          client: TrackingClient((request) async {
            body = await (request as http.Request).finalize().bytesToString();
            return http.StreamedResponse(
              Stream.value(utf8.encode(jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'ok'},
                    'finish_reason': 'stop',
                  },
                ],
              }))),
              200,
            );
          }),
        ),
      );
      await provider.chat(AiRequest(messages: [
        AiMessage(role: AiMessageRole.tool, content: [
          AiToolResultContent(id: '1', name: 't', result: _Opaque()),
        ]),
      ]));
      expect(body, contains('opaque!'));
    });
  });
}

class _Opaque {
  @override
  String toString() => 'opaque!';
}

class _ModelRecorder extends AiMiddleware {
  _ModelRecorder(this.seen);

  final List<String?> seen;

  @override
  Future<AiResponse> handleChat(AiRequest request, AiRequestHandler next) {
    seen.add(request.model);
    return next(request);
  }
}

class _RecordingStore implements AiVectorStore {
  final _inner = MemoryVectorStore();
  int searches = 0;

  @override
  Future<void> add(AiDocument document) => _inner.add(document);

  @override
  Future<void> addAll(List<AiDocument> documents) => _inner.addAll(documents);

  @override
  Future<void> clear() => _inner.clear();

  @override
  Future<void> delete(String id) => _inner.delete(id);

  @override
  Future<List<AiSearchResult>> search(AiEmbedding query, {int k = 4}) {
    searches++;
    return _inner.search(query, k: k);
  }
}

class _RecordingLogger implements AiLogger {
  final errors = <Object?>[];

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warning(String message) {}

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      errors.add(error);
}
