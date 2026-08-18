# ai_plus

[![pub package](https://img.shields.io/pub/v/ai_plus.svg)](https://pub.dev/packages/ai_plus)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Dart 3](https://img.shields.io/badge/Dart-3-blue.svg)](https://dart.dev)

**A production-ready, provider-agnostic AI SDK for Dart & Flutter.**

> Write your AI logic once. Switch between OpenAI, Gemini, Anthropic, or any
> OpenAI-compatible endpoint without changing a single line of business logic.

---

## Why ai_plus?

| Feature | `ai_plus` | Raw HTTP | Other SDKs |
|---------|:---------:|:--------:|:----------:|
| Provider-agnostic | ✅ | ❌ | ❌ |
| Tool calling | ✅ | Manual | Varies |
| Structured output | ✅ | Manual | Varies |
| Streaming | ✅ | Manual | ✅ |
| Retry + Caching | ✅ Built-in | ❌ | ❌ |
| RAG (Knowledge Base) | ✅ Built-in | ❌ | ❌ |
| Autonomous Agents | ✅ Built-in | ❌ | ❌ |
| Multimodal (images) | ✅ | Manual | Varies |
| Pure Dart (no Flutter dep) | ✅ | ✅ | Varies |

---

## Supported Providers

| Provider | Chat | Streaming | Tool Calling | Structured Output | Embeddings | Image Input |
|----------|:----:|:---------:|:------------:|:-----------------:|:----------:|:-----------:|
| **OpenAI** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Google Gemini** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Anthropic (Claude)** | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **Custom (OpenAI-compatible)** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

Custom providers cover Ollama, LocalAI, Azure OpenAI, Together AI, Groq, and any
service exposing an OpenAI-compatible `/v1/chat/completions` endpoint.

---

## Installation

```yaml
dependencies:
  ai_plus: ^0.0.1
```

```bash
dart pub get
```

---

## Quick Start

```dart
import 'package:ai_plus/ai_plus.dart';

void main() async {
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
}
```

Switch providers by changing one line:

```dart
// Google Gemini
final ai = AiClient(provider: AiProvider.gemini(apiKey: apiKey));

// Anthropic Claude
final ai = AiClient(provider: AiProvider.anthropic(apiKey: apiKey));

// Ollama / LocalAI / Any OpenAI-compatible
final ai = AiClient(
  provider: AiProvider.custom(baseUrl: 'http://localhost:11434/v1', apiKey: ''),
);
```

---

## Features

### Streaming

```dart
await for (final chunk in ai.stream(messages: [AiMessage.user('Write a poem')])) {
  stdout.write(chunk.text);
}

// Or use the convenience method:
await for (final text in ai.streamText(messages: [AiMessage.user('Hello')])) {
  stdout.write(text);
}
```

### Conversations (Multi-Turn)

```dart
final conversation = ai.conversation();

final reply1 = await conversation.send('My name is Alice.');
print(reply1.text);

final reply2 = await conversation.send('What is my name?');
print(reply2.text); // "Your name is Alice."

// Stream within a conversation (history is auto-managed)
await for (final chunk in conversation.stream('Tell me a joke.')) {
  stdout.write(chunk.text);
}
```

### Tool Calling

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
  execute: (args) async {
    return 'Sunny, 72°F in ${args['location']}';
  },
);

final response = await ai.chat(
  messages: [AiMessage.user('What is the weather in London?')],
  tools: [weatherTool],
);

// The response may contain tool calls:
final toolCalls = response.message.content.whereType<AiToolCallContent>();
```

### Autonomous Agents

```dart
final agent = AiAgent(
  client: ai,
  instructions: 'You are a helpful weather assistant.',
  tools: [weatherTool],
  maxIterations: 5,
);

final answer = await agent.run('Should I bring an umbrella to San Francisco?');
print(answer);
```

### Structured Output

```dart
final schema = AiJsonSchema.object(
  properties: {
    'name': AiJsonSchema.string(),
    'age': AiJsonSchema.integer(),
    'hobbies': AiJsonSchema.array(items: AiJsonSchema.string()),
  },
  required: ['name', 'age'],
);

final profile = await ai.generate<Map<String, dynamic>>(
  prompt: 'Create a fictional user profile.',
  schema: schema,
  decoder: (json) => json,
);

print(profile['name']);
```

### Multimodal (Image Input)

```dart
import 'dart:io';
import 'dart:typed_data';

final imageBytes = File('photo.png').readAsBytesSync();

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

### Embeddings & RAG

```dart
// Create embeddings
final result = await ai.embeddings.create(input: 'Hello world');
print(result.vector); // [0.012, -0.034, ...]

// Knowledge Base (RAG)
final kb = AiKnowledgeBase(
  client: ai,
  embeddingService: ai.embeddings,
);

await kb.ingest(id: 'doc1', content: 'Dart was created by Google in 2011.');
await kb.ingest(id: 'doc2', content: 'Flutter uses Dart for cross-platform apps.');

// Search
final results = await kb.search('Who created Dart?');
print(results.first.document.content);

// Ask (full RAG pipeline: embed → search → answer)
final answer = await kb.ask('What is Dart used for?');
print(answer.text);
```

### Prompt Templates

```dart
const template = AiPromptTemplate(
  'Summarize the following {{language}} code:\n\n{{code}}',
);

final prompt = template.render({
  'language': 'Dart',
  'code': 'void main() => print("hello");',
});
```

### Middleware (Retries, Caching, Logging, Metrics)

```dart
final ai = AiClient(
  provider: AiProvider.openAI(apiKey: apiKey),
  // Automatic retries with exponential backoff
  retryPolicy: const AiRetryPolicy(
    maxAttempts: 3,
    backoffFactor: 2.0,
  ),
  // In-memory response cache
  cache: MemoryAiCache(ttl: const Duration(minutes: 30)),
  // Console logger
  logger: const ConsoleAiLogger(enableDebug: true),
  // Custom middleware
  middlewares: [MetricsMiddleware()],
);
```

### Cost Tracking

```dart
final tracker = AiCostTracker(
  pricing: const AiPricing(
    inputCostPerToken: 0.0000025,  // $2.50 per 1M tokens
    outputCostPerToken: 0.00001,   // $10 per 1M tokens
  ),
);

final response = await ai.chat(messages: [...]);
tracker.addUsage(response.usage);

print('Total cost: \$${tracker.estimatedCost.toStringAsFixed(4)}');
```

### Conversation Storage

```dart
// In-memory storage (provided)
final storage = InMemoryConversationStorage();

// Save a conversation
final conversation = ai.conversation(id: 'session-1');
await conversation.send('Hello!');
await storage.save(conversation.id, conversation.messages);

// Restore later
final messages = await storage.load('session-1');
final restored = ai.conversation(
  id: 'session-1',
  initialMessages: messages ?? [],
);
```

---

## Error Handling

All exceptions extend `AiException` for consistent error handling:

```dart
try {
  final response = await ai.chat(messages: [...]);
} on AiAuthenticationException {
  print('Invalid API key');
} on AiRateLimitException catch (e) {
  print('Rate limited. Retry after: ${e.retryAfter}');
} on AiTimeoutException {
  print('Request timed out');
} on AiUnsupportedCapabilityException {
  print('Provider does not support this feature');
} on AiException catch (e) {
  print('AI error: ${e.message}');
}
```

**Exception hierarchy:**

| Exception | When |
|-----------|------|
| `AiAuthenticationException` | Invalid API key (401) |
| `AiAuthorizationException` | Insufficient permissions (403) |
| `AiRateLimitException` | Rate limited (429) |
| `AiNetworkException` | Connection failed |
| `AiTimeoutException` | Request timed out |
| `AiInvalidRequestException` | Bad request (400) |
| `AiProviderException` | Server error (5xx) |
| `AiParsingException` | Response parsing failed |
| `AiContentFilterException` | Content safety filter |
| `AiUnsupportedCapabilityException` | Feature not supported |
| `AiStructuredOutputException` | JSON extraction/validation failed |
| `AiToolNotFoundException` | Unknown tool called |
| `AiToolException` | Tool execution failed |

---

## Architecture

```
┌─────────────────────────────┐
│       Your Application      │
└──────────────┬──────────────┘
               │
┌──────────────▼──────────────┐
│          AiClient           │  ← Middleware pipeline
│   (chat, stream, generate)  │  ← Retry, Cache, Logging
└──────────────┬──────────────┘
               │
┌──────────────▼──────────────┐
│         AiProvider          │  ← Abstract interface
└──────┬───────┬───────┬──────┘
       │       │       │
   ┌───▼──┐ ┌─▼───┐ ┌─▼────────┐
   │OpenAI│ │Gemini│ │Anthropic │
   └──────┘ └─────┘ └──────────┘
```

---

## Security

> ⚠️ **Never hardcode API keys** in your source code.

Use environment variables or secure storage:

```dart
import 'dart:io';

final apiKey = Platform.environment['OPENAI_API_KEY']!;
final ai = AiClient(provider: AiProvider.openAI(apiKey: apiKey));
```

- API keys are never logged by the SDK, even in debug mode.
- Raw responses (available via `response.raw`) may contain sensitive data; handle accordingly.
- The `ConsoleAiLogger` only logs request/response metadata, never full payloads.

---

## Testing

The SDK is designed to be testable. All providers accept an injectable HTTP client:

```dart
import 'package:http/testing.dart';
import 'package:ai_plus/src/http/ai_http_client.dart';

final mockClient = MockClient((request) async {
  return http.Response(jsonEncode({...}), 200);
});

final provider = OpenAiProvider(
  apiKey: 'test-key',
  httpClient: AiHttpClient(client: mockClient),
);
```

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

Please ensure all tests pass and the code is formatted before submitting:

```bash
dart format .
dart analyze
dart test
```

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
