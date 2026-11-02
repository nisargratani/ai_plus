# ai_plus

[![pub package](https://img.shields.io/pub/v/ai_plus.svg)](https://pub.dev/packages/ai_plus)
[![CI](https://github.com/nisargratani/ai_plus/actions/workflows/ci.yml/badge.svg)](https://github.com/nisargratani/ai_plus/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)

A provider-agnostic AI SDK for Dart and Flutter.

Write your AI logic once against a single API, then switch between OpenAI,
Google Gemini, Anthropic Claude, or any OpenAI-compatible server (Ollama,
vLLM, Groq, OpenRouter, Azure OpenAI, ...) by changing one line.

- Chat, streaming and multi-turn conversations
- Tool calling, including streamed tool calls, and an automatic agent loop
- Typed structured output (`generate<T>`)
- Embeddings and a small RAG helper (`AiKnowledgeBase`)
- Middleware: retries with backoff, response caching, logging, metrics
- Typed exceptions with provider error messages, status codes and request IDs
- Pure Dart, with only `http` and `crypto` as dependencies

---

## Installation

```bash
dart pub add ai_plus
# or
flutter pub add ai_plus
```

**Requirements:** Dart 3.4+ (Flutter 3.22+). Runs on every Dart platform:
Android, iOS, macOS, Windows, Linux, web and server.

---

## Quick start

```dart
import 'package:ai_plus/ai_plus.dart';

Future<void> main() async {
  final ai = AiClient(
    provider: AiProvider.openAI(apiKey: 'YOUR_API_KEY'),
  );

  final response = await ai.chat(
    messages: [
      AiMessage.system('You are a helpful assistant.'),
      AiMessage.user('Explain quantum computing in one sentence.'),
    ],
  );

  print(response.text);
  print('Tokens used: ${response.usage.totalTokens}');

  ai.close(); // Releases HTTP connections.
}
```

Switch providers by changing one line:

```dart
final ai = AiClient(provider: AiProvider.gemini(apiKey: geminiKey));
final ai = AiClient(provider: AiProvider.anthropic(apiKey: anthropicKey));

// Local Ollama (no key needed). Describe what the model supports:
final ai = AiClient(
  provider: AiProvider.custom(
    baseUrl: 'http://localhost:11434/v1',
    apiKey: '',
    capabilities: const AiCapabilities(streaming: true, toolCalling: true),
  ),
  defaultModel: 'llama3.2',
);

// Azure OpenAI (key in an `api-key` header)
final ai = AiClient(
  provider: AiProvider.custom(
    baseUrl: 'https://my-resource.openai.azure.com/openai/v1',
    apiKey: '',
    headers: {'api-key': azureKey},
  ),
  defaultModel: 'my-deployment',
);
```

---

## Providers

| Provider | Chat | Streaming | Tools | Structured output | Embeddings | Images | Audio |
|----------|:----:|:---------:|:-----:|:-----------------:|:----------:|:------:|:-----:|
| OpenAI | ✅ | ✅ | ✅ | ✅ native | ✅ | ✅ | ❌ |
| Google Gemini | ✅ | ✅ | ✅ | ✅ native | ✅ | ✅ | ✅ |
| Anthropic Claude | ✅ | ✅ | ✅ | ✅ via prompt | ❌ | ✅ | ❌ |
| Custom (OpenAI-compatible) | ✅ | ✅ | ✅ | ✅ native* | ✅* | ✅* | ❌ |

\* Depends on what the server implements. Describe it with the
`capabilities` parameter of `AiProvider.custom` (by default the full OpenAI
set is assumed), and read it back from `provider.capabilities` at runtime.
`AiClient` refuses tools and streaming the provider does not support, and
`generate` falls back to prompt-based JSON when `structuredOutput` is false.

**Default models** are used when neither the request nor
`AiClient.defaultModel` names one. Set a model explicitly in production so
upgrades never change it:

| Provider | Chat | Embeddings |
|----------|------|------------|
| OpenAI | `gpt-6-luna` | `text-embedding-3-small` |
| Gemini | `gemini-flash-latest` | `gemini-embedding-001` |
| Anthropic | `claude-sonnet-5` (`max_tokens` 1024, thinking included) | — |
| Custom | `gpt-6-luna` (always set a model) | `text-embedding-3-small` |

Provider notes:

- **OpenAI:** `gpt-6-luna` supports function calling in Chat Completions only
  with `reasoning_effort: "none"`, so `OpenAiProvider` sends that whenever a
  `gpt-6-luna` request includes tools.
- **Anthropic thinking:** Claude 5 models think by default. When the model
  thinks before calling a tool, its `thinking` blocks are kept in
  `AiToolCallContent.metadata` and sent back unchanged with the tool results,
  as the API requires. `max_tokens` covers thinking and answer together, so
  raise `maxTokens` for long answers.
- **Anthropic sampling:** Claude Sonnet 5, Opus 4.7 and later, Haiku 5.5 and
  Fable reject `temperature` and `top_p` (HTTP 400), as does every model on
  API version `2026-10-21` or later. For those models `AnthropicProvider`
  omits `temperature`/`topP`, and `AiClient` logs a one-time warning per
  model through its `logger`. Older models still receive them.

Every factory accepts optional `headers` (sent with every request) and
`httpClient`. The concrete classes (`OpenAiProvider`, `GeminiProvider`,
`AnthropicProvider`, `CustomProvider`) are exported too.

---

## Features

### Streaming

```dart
await for (final chunk in ai.stream(messages: [AiMessage.user('Write a poem')])) {
  stdout.write(chunk.text);
}

// Text only:
await for (final text in ai.streamText(messages: [AiMessage.user('Hello')])) {
  stdout.write(text);
}
```

Stream semantics are the same for all providers:

- `chunk.finishReason` is `null` on every chunk except the last one. With
  OpenAI, the last chunk also carries the usage.
- Tool calls arrive once, with complete arguments.
- `chunk.usage` (when the provider reports it) holds cumulative totals.
- Breaking out of `await for` cancels the HTTP request.
- An OpenAI refusal arrives as text, and the last chunk's `finishReason` is
  `contentFilter`.

### Conversations

```dart
final conversation = ai.conversation();

await conversation.send('My name is Alice.');
final reply = await conversation.send('What is my name?');
print(reply.text); // "Your name is Alice."

await for (final chunk in conversation.stream('Tell me a joke.')) {
  stdout.write(chunk.text);
}
```

A turn is added to `conversation.messages` only after it succeeds. If a
request fails, or you cancel a stream, the history is left unchanged, so you
can simply retry. Await each call before starting the next.

### Tool calling

```dart
final weatherTool = AiTool(
  name: 'get_weather',
  description: 'Gets the current weather for a location.',
  parameters: AiJsonSchema.object(
    properties: {
      'location': AiJsonSchema.string(description: 'The city name'),
    },
    required: ['location'],
  ),
  execute: (args) async => 'Sunny, 22°C in ${args['location']}',
);

final response = await ai.chat(
  messages: [AiMessage.user('What is the weather in London?')],
  tools: [weatherTool],
);

final toolCalls = response.message.content.whereType<AiToolCallContent>();
final results = await ToolExecutor([weatherTool]).executeAll(toolCalls.toList());
```

A tool's return value is sent to the model as-is if it is a string, and
JSON-encoded otherwise. `ToolExecutor` catches exceptions a tool throws and
reports them to the model as error results.

### Agents (automatic tool loop)

```dart
final agent = AiAgent(
  client: ai,
  instructions: 'You are a helpful weather assistant.',
  tools: [weatherTool],
  maxIterations: 5,
);

final answer = await agent.run('Should I bring an umbrella to London?');
```

The agent calls the model, runs any requested tools (in parallel), feeds the
results back, and repeats until the model answers without calling a tool.
`maxIterations` limits the rounds of tool execution. After the last round the
results go back to the model once more so it can answer, so a run makes at
most `maxIterations + 1` model calls. If the model still asks for tools then,
the agent throws `AiToolException` **without** running them, so no tool side
effect (such as a refund) happens unless its result reaches the model.

### Structured output

```dart
final profile = await ai.generate<Map<String, dynamic>>(
  prompt: 'Create a fictional user profile.',
  schema: AiJsonSchema.object(
    properties: {
      'name': AiJsonSchema.string(),
      'age': AiJsonSchema.integer(),
      'hobbies': AiJsonSchema.array(items: AiJsonSchema.string()),
    },
    required: ['name', 'age', 'hobbies'],
  ),
  decoder: (json) => json, // or UserProfile.fromJson
);
```

- **OpenAI:** when every property of every object is listed in `required`,
  OpenAI's strict mode is used, which guarantees the reply matches the schema.
  Otherwise the schema is sent as a best-effort hint.
- **Gemini:** the schema is sent as `responseSchema`.
- **Anthropic:** the schema is added to the prompt as an instruction.

The first valid JSON object in the reply is decoded. Text or braces around it
are ignored. If there is no valid JSON object, the model refused (OpenAI
`refusal`), or `decoder` throws, `generate` throws
`AiStructuredOutputException`; its `rawResponse` holds the reply.

### Images and audio

```dart
final imageBytes = await File('photo.png').readAsBytes();

final response = await ai.chat(
  messages: [
    AiMessage(
      role: AiMessageRole.user,
      content: [
        const AiTextContent('Describe this image.'),
        AiImageContent(mimeType: 'image/png', bytes: imageBytes),
      ],
    ),
  ],
);
```

`AiAudioContent` is supported by Gemini. Unsupported content types throw
`AiUnsupportedCapabilityException`.

### Embeddings and RAG

```dart
final result = await ai.embeddings.create(input: 'Hello world');
print(result.vector);

final batch = await ai.embeddings.createBatch(inputs: ['a', 'b', 'c']);

final kb = AiKnowledgeBase(client: ai);
await kb.ingest(id: 'doc1', content: 'Dart was created by Google in 2011.');
await kb.ingest(id: 'doc2', content: 'Flutter uses Dart for cross-platform apps.');

// Many documents: embedded `batchSize` (default 100) per request.
await kb.ingestBatch(contents: faqEntries, batchSize: 100);

final hits = await kb.search('Who created Dart?');
final answer = await kb.ask('What is Dart used for?');
print(answer.text);
```

`AiKnowledgeBase` accepts any `AiVectorStore`. The built-in
`MemoryVectorStore` does a linear cosine-similarity scan and is meant for up
to a few thousand documents. Implement `AiVectorStore` to plug in a real
vector database. Documents are keyed by id, so re-ingesting an id replaces it.

### Middleware: retries, caching, logging, metrics

```dart
final metrics = MetricsMiddleware();

final ai = AiClient(
  provider: AiProvider.openAI(apiKey: apiKey),
  timeout: const Duration(seconds: 60),
  retryPolicy: const AiRetryPolicy(maxAttempts: 3), // AiRetryPolicy.none to disable
  cache: MemoryAiCache(ttl: const Duration(minutes: 30), maxEntries: 500),
  logger: const ConsoleAiLogger(),
  middlewares: [metrics],
);
```

- **Retries:** rate limits (429), timeouts, network errors and 5xx responses
  are retried with exponential backoff and jitter. The provider's
  `retry-after` hint (on 429 and on 5xx, such as OpenAI's 503 "overloaded")
  is honoured, capped at `maxDelay`. A stream is retried only if it fails
  before its first chunk, so output is never duplicated. Invalid requests,
  including an API key with a stray newline, are not retried.
- **Timeout:** for `chat`, the timeout applies to each attempt, and an attempt
  that times out is aborted, so the provider stops generating (and billing)
  it. For `stream`, it is an idle timeout between chunks, and a stream that
  times out is cancelled.
- **Cache:** keys are SHA-256 digests of the provider and its base URL plus
  the whole request (model, parameters, tools, schema, all message content
  including images). One cache can therefore be shared by clients for
  different providers or servers. Streams are not cached. Implement `AiCache`
  for persistent storage.
- **Logging:** only metadata and latency are logged, never message content
  or API keys.

**Cancelling a request:** `AiRequest.abortTrigger` aborts the HTTP request
(or the response stream) when the future completes, and the call fails with
`AiTimeoutException`. Requests whose trigger has fired are not retried. Set it
from a middleware, or pass it when calling a provider directly:

```dart
final cancel = Completer<void>();
final reply = provider.chat(AiRequest(messages: messages, abortTrigger: cancel.future));
// Later, for example when the user leaves the screen:
cancel.complete();
```

Custom middleware extends `AiMiddleware` and overrides what it needs:

```dart
class AuditMiddleware extends AiMiddleware {
  @override
  Future<AiResponse> handleChat(AiRequest request, AiRequestHandler next) async {
    final response = await next(request);
    audit(request.model, response.usage);
    return response;
  }
}
```

### Prompt templates

```dart
const template = AiPromptTemplate('Summarize this {{language}} code:\n\n{{code}}');

final prompt = template.render({'language': 'Dart', 'code': source});
```

Whitespace inside the braces is allowed (`{{ language }}`). A placeholder
without a value throws `ArgumentError`. Substitution happens in a single
pass. A `{{placeholder}}` inside an inserted value is left untouched, so user
input cannot pull in other variables.

### Cost tracking

```dart
final tracker = AiCostTracker(
  pricing: const AiPricing(
    inputCostPerToken: 0.0000025, // $2.50 per 1M tokens
    outputCostPerToken: 0.00001, // $10 per 1M tokens
  ),
);

tracker.addUsage(response.usage);
print('Total cost: \$${tracker.estimatedCost.toStringAsFixed(4)}');
```

Gemini's `outputTokens` include thinking tokens, which Gemini bills as
output, so `inputTokens + outputTokens` matches `totalTokens`.

### Conversation storage

```dart
final storage = InMemoryConversationStorage(); // or your own AiConversationStorage

await storage.save(conversation.id, conversation.messages);

final messages = await storage.load(conversation.id);
final restored = ai.conversation(id: conversation.id, initialMessages: messages ?? []);
```

When persisting tool calls, keep `AiToolCallContent.metadata`. Gemini
requires its `thoughtSignature` to be sent back, and Anthropic its `thinking`
blocks (stored under `AnthropicProvider.thinkingMetadataKey`).

---

## Error handling

Every error thrown by the SDK extends `AiException`, which carries
`message` (including the provider's own error text), `provider`,
`statusCode` and `requestId` when available.

```dart
try {
  final response = await ai.chat(messages: [AiMessage.user('Hi')]);
} on AiAuthenticationException {
  print('Invalid API key');
} on AiRateLimitException catch (e) {
  print('Rate limited. Retry after: ${e.retryAfter}');
} on AiTimeoutException {
  print('Request timed out');
} on AiException catch (e) {
  print('AI error: $e'); // Includes provider, status and request id.
}
```

| Exception | When |
|-----------|------|
| `AiAuthenticationException` | Invalid API key (401, or Gemini's 400 `API_KEY_INVALID`) |
| `AiAuthorizationException` | Insufficient permissions (403) |
| `AiRateLimitException` | Rate limited (429); `retryAfter` from response headers |
| `AiTimeoutException` | Client-side timeout, aborted request (`abortTrigger`), or HTTP 408 |
| `AiNetworkException` | Connection failed or dropped |
| `AiInvalidRequestException` | Other 4xx (bad parameters, unknown model, ...), or a header value (such as an API key) or body that cannot be sent |
| `AiProviderException` | Server error (5xx; `retryAfter` when sent) or error event inside a stream |
| `AiParsingException` | Unexpected response format |
| `AiContentFilterException` | Prompt blocked by the provider's safety system |
| `AiUnsupportedCapabilityException` | Feature not supported by the provider |
| `AiStructuredOutputException` | JSON extraction or decoding failed in `generate` |
| `AiToolException` | Agent still requested tools after `maxIterations` tool rounds |

All errors, validation errors included, are delivered through the returned
`Future` or `Stream`.

---

## Security

- **Never hardcode API keys.** Load them from the environment or secure
  storage:

  ```dart
  final apiKey = Platform.environment['OPENAI_API_KEY']!;
  ```

- **Client apps (Flutter, web):** a key shipped inside an app can be
  extracted, and on the web it is visible in the browser. For production
  apps, route requests through your own backend, and point `baseUrl` at it.
- API keys are sent only in request headers (Gemini uses `x-goog-api-key`).
  They are never put in URLs, never logged, and never included in exception
  messages. A key with characters that HTTP headers cannot carry (such as the
  trailing newline of a key read from a file) is rejected with an
  `AiInvalidRequestException` that names the header but not its value.
- `response.raw` and `AiParsingException.rawResponse` contain provider
  payloads. Treat them as sensitive.

---

## Testing your code

Inject a mock HTTP client from `package:http/testing.dart`:

```dart
import 'package:ai_plus/ai_plus.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final provider = OpenAiProvider(
  apiKey: 'test-key',
  httpClient: AiHttpClient(
    client: MockClient((request) async => http.Response(jsonEncode({...}), 200)),
  ),
);
```

Alternatively, implement `AiProvider` with a small fake for fully offline
tests.

---

## Limitations

- Only the first candidate or choice of a response is returned.
- `MemoryVectorStore` and `MemoryAiCache` keep data in process memory.
- Streaming responses are not cached, and streams are not resumed after a
  mid-stream failure.
- Provider-specific features beyond the common surface (for example
  reasoning-effort settings or prompt caching) are not exposed as typed
  options.

## Migrating to 0.1.0

0.1.0 only adds to the 0.0.2 API, but some behaviour changes.
The full list is in the [changelog](CHANGELOG.md):

- Default OpenAI and custom model: `gpt-4o-mini` → `gpt-6-luna`. The old
  model is deprecated and leaves the API on 2027-01-14.
- Gemini `outputTokens` include thinking tokens.
- An invalid Gemini key raises `AiAuthenticationException`.
- `AiAgent` makes one final model call after `maxIterations` tool rounds, and
  never runs tools it cannot report back.
- Cache keys changed (prefix `ai_plus:v2:`), so persistent caches start cold.
- Anthropic omits `temperature`/`topP` for models that reject them.
- `http` 1.6.0 or later is required.

## Migrating from 0.0.1

0.0.2 keeps the 0.0.1 API. The behaviour changes worth knowing about are
listed in the [changelog](CHANGELOG.md). In short: failed conversation turns
no longer stay in the history, Gemini and Anthropic default models were
updated, and `AiKnowledgeBase.ask(systemPrompt:)` now keeps the retrieved
context.

---

## Contributing

Issues and pull requests are welcome at
[github.com/nisargratani/ai_plus](https://github.com/nisargratani/ai_plus).
Before submitting, please run:

```bash
dart format .
dart analyze
dart test
```

## License

MIT. See [LICENSE](LICENSE).
