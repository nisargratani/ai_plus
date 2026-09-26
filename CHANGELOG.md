## 0.0.2

This release fixes a number of correctness and security issues found in a
full audit. It is source-compatible with 0.0.1; the behaviour changes are
listed below.

### Security

- Gemini: the API key is now sent in the `x-goog-api-key` header instead of
  the `?key=` URL query parameter. Before, network errors could put the key
  into exception messages and logs.
- Network exceptions no longer include the request URL.
- `AiPromptTemplate.render` substitutes in a single pass. Before, a
  `{{variable}}` inside a user-supplied value was expanded, which allowed
  template injection.

### Bug fixes

- Streaming tool calls were broken for OpenAI, custom providers and
  Anthropic. Argument fragments are now accumulated, and each tool call is
  emitted once with complete arguments.
- OpenAI streams reported `AiFinishReason.unknown` on every chunk. Gemini
  streams had the same problem. Now `finishReason` is `null` except on the
  final chunk.
- OpenAI: only the first result of a multi-tool turn was sent, so parallel
  tool calls (as produced by `AiAgent`) failed with HTTP 400. Each result is
  now sent as its own `tool` message.
- OpenAI structured output always used strict mode, which rejects schemas
  with optional properties (including the README example). Strict mode is
  now used only for schemas that meet its requirements, and strict schemas
  get `additionalProperties: false`.
- `AiAgent` stopped without running tools when a provider returned tool calls
  with a `stop` finish reason, which Gemini always does. The loop now
  continues whenever tool calls are present.
- Gemini tool turns are marked `toolCalls`, and function responses use the
  `user` role. Gemini thought signatures are preserved and sent back, which
  newer Gemini models require for function calling.
- `AiConversation.stream` stored every streamed token as a separate text part,
  so `message.text` in the saved history had a newline between tokens.
  Streamed replies are now stored as one text part.
- `CacheMiddleware` keyed responses only on model, role and text, so requests
  that differed in images, tools, schema, temperature or other parameters
  could get each other's cached answers. Keys are now a SHA-256 digest of the
  whole request.
- `RetryMiddleware` replayed a stream from the start if it failed mid-way,
  duplicating output. Streams are now retried only before their first chunk.
  `retry-after` delays are capped at `AiRetryPolicy.maxDelay`.
- `AiRateLimitException.retryAfter` and `AiException.requestId` were never
  set. They are now parsed from response headers (`retry-after`,
  `retry-after-ms`, `x-request-id`, `request-id`).
- Error messages for 401, 403, 429 and 5xx responses now include the
  provider's own error message. HTTP 408 maps to `AiTimeoutException`.
- A connection dropped mid-stream now raises `AiNetworkException` instead of
  a raw `http.ClientException`.
- `LoggingMiddleware` and `MetricsMiddleware` missed errors on streams.
  Metrics now also record stream latency.
- `AiClient.close()` was a no-op. It now closes the HTTP client that a
  built-in provider created. Clients you inject stay open.
- Anthropic streams ignored `error` events, dropped input-token usage, and
  treated an empty `content` array as a parsing error. All three are handled.
- Gemini prompts blocked by safety filters now raise
  `AiContentFilterException` instead of `AiParsingException`.
- `AiClient.generate` never sent the schema to providers without native
  structured output (Anthropic), so the model rarely replied with JSON. The
  schema is now included as an instruction.
- `AiKnowledgeBase.ask(systemPrompt:)` dropped the retrieved context
  entirely. The context is now appended to the custom prompt.
- `AiKnowledgeBase.ingestBatch` validates `ids` and `metadataList` lengths.
  Generated ids are unique.
- Tool results that are not JSON-encodable no longer crash request encoding.
  They fall back to `toJson()` or `toString()`.
- Timeout messages are accurate for sub-second timeouts.
- Conversation ids generated within the same millisecond no longer collide.

### Behaviour changes

- `AiConversation.send`/`stream` add the user message and the reply to the
  history only after the turn succeeds. A failed or cancelled turn leaves the
  history unchanged.
- `AiClient.chat` and `AiClient.stream` deliver validation errors through the
  returned `Future`/`Stream` instead of throwing synchronously. `await` and
  `await for` code is unaffected.
- `MemoryVectorStore.add` replaces an existing document with the same id
  instead of storing a duplicate.
- Default models: Gemini `gemini-2.0-flash` → `gemini-flash-latest`, Gemini
  embeddings `text-embedding-004` → `gemini-embedding-001` (the old models
  have been retired), Anthropic `claude-sonnet-4-20250514` → `claude-sonnet-5`.
- OpenAI sends `max_completion_tokens` instead of the deprecated `max_tokens`,
  which reasoning models reject, and requests usage in streams via
  `stream_options`. `CustomProvider` keeps `max_tokens`, maps `developer`
  messages to `system`, and omits the `Authorization` header when the API key
  is empty.
- `ConsoleAiLogger.error` prints stack traces only when `enableDebug` is on.

### New features

- `headers` parameter on every provider and factory, for Azure `api-key`,
  OpenRouter, `anthropic-beta`, `OpenAI-Organization` and so on. The factories
  also accept `httpClient`.
- The providers (`OpenAiProvider`, `GeminiProvider`, `AnthropicProvider`,
  `CustomProvider`) and `AiHttpClient` are exported from
  `package:ai_plus/ai_plus.dart`, so importing `src/` is no longer needed.
- `AiHttpClient.postSse` for building custom SSE-based providers.
- `AiToolCallContent.metadata` carries provider-specific data that must be
  sent back with a tool call.
- `MemoryAiCache(maxEntries:)` adds LRU eviction and `length`.
- `AiMiddleware` is now an extendable base class, so a middleware can
  override just one method.
- `AiKnowledgeBase` accepts any `AiVectorStore` (it previously required
  `MemoryVectorStore`), `embeddingService` defaults to `client.embeddings`,
  and a `store` getter was added. `addDocument` now returns a `Future`.
- `MemoryVectorStore.length`, and faster search through precomputed norms.
- `CacheMiddleware.cacheKey` is public, for custom cache implementations.
- `AiNetworkException` and `AiTimeoutException` accept `statusCode` and
  `requestId`.

### Compatibility

- Minimum Dart SDK lowered from 3.12 to 3.4 (Flutter 3.22+). Verified by
  running the test suite on Dart 3.4.
- New dependency: `crypto` (for stable cache keys).
- API documentation for all public members. CI runs formatting, analysis,
  tests on stable and on the minimum SDK, and a publish dry run.

## 0.0.1

### Initial Release

**Core**
- `AiClient` — primary orchestrator with middleware pipeline
- `AiProvider` — abstract provider interface with factory constructors
- `AiRequest` / `AiResponse` / `AiStreamChunk` — core data models
- `AiCapabilities` — runtime capability introspection

**Providers**
- `OpenAiProvider` — full support: chat, streaming, tool calling, structured output, embeddings, image input
- `GeminiProvider` — full support: chat, streaming, tool calling, structured output, embeddings, multimodal
- `AnthropicProvider` — chat, streaming, tool calling, image input
- `CustomProvider` — any OpenAI-compatible endpoint (Ollama, LocalAI, Azure, Groq, etc.)

**Models**
- `AiMessage` — factory constructors for all roles (system, developer, user, assistant, tool)
- `AiContent` — sealed hierarchy: text, image, audio, file, tool call, tool result
- `AiUsage`, `AiFinishReason`, `AiModel`

**Features**
- **Tool Calling** — `AiTool` definition with schema + auto-execution via `ToolExecutor`
- **Structured Output** — `AiJsonSchema` + `ai.generate<T>()` with native provider support
- **Streaming** — SSE parsing with buffering for all providers
- **Conversations** — `AiConversation` with auto-managed history, streaming support
- **Conversation Storage** — `AiConversationStorage` interface + `InMemoryConversationStorage`
- **Embeddings** — `AiEmbeddingService` with single and batch support
- **RAG** — `AiKnowledgeBase` with `ingest()`, `search()`, `ask()`
- **Vector Store** — `AiVectorStore` interface + `MemoryVectorStore` with cosine similarity
- **Autonomous Agents** — `AiAgent` with tool loop, instructions, max iterations

**Middleware & Production**
- `AiRetryPolicy` — exponential backoff with jitter
- `RetryMiddleware` — automatic retry on transient failures
- `CacheMiddleware` + `MemoryAiCache` — response caching with TTL
- `LoggingMiddleware` + `ConsoleAiLogger` — debug and info logging
- `MetricsMiddleware` — request count, error count, latency tracking

**Utilities**
- `AiPromptTemplate` — `{{variable}}` template rendering with validation
- `AiCostTracker` + `AiPricing` — token usage and cost estimation

**Error Handling**
- Complete exception hierarchy extending `AiException`:
  `AiAuthenticationException`, `AiAuthorizationException`, `AiRateLimitException`,
  `AiNetworkException`, `AiTimeoutException`, `AiInvalidRequestException`,
  `AiProviderException`, `AiParsingException`, `AiContentFilterException`,
  `AiUnsupportedCapabilityException`, `AiStructuredOutputException`,
  `AiToolNotFoundException`, `AiToolException`

**Quality**
- 146 unit tests covering all modules
- Zero `dart analyze` issues
- Comprehensive DartDoc on all public APIs
- MIT License
