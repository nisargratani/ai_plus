## 0.1.1

Completes the cancellation support added in 0.1.0. No behaviour changes for
existing code.

### New features

- `AiKnowledgeBase.ask` and `AiKnowledgeBase.ingestBatch` accept
  `abortTrigger`, like the other chat entry points. Completing it fails the
  call with `AiTimeoutException`:
  - `ask` aborts the answer request, or does not start it if the trigger
    fires during the search. The search's embeddings request runs to
    completion.
  - `ingestBatch` sends no further slice and stores nothing. A slice
    already in flight finishes.

### Documentation

- The example shows cancelling a request with `abortTrigger`, the usage
  breakdown (`AiUsage` now prints reasoning and cached tokens), and
  describing an OpenAI-compatible server with `capabilities`.
- The README lists every method that accepts `abortTrigger`.

## 0.1.0

This release fixes 19 issues found in an external QA pass (2026-11-02) and
revisits several defaults. The API only grows, so code that calls it
compiles unchanged. Classes that override or implement `AiClient`,
`AiConversation`, `AiAgent`, `AiHttpClient` or `AiRequest` methods need the
new `abortTrigger` parameter. Callers can observe several behaviour changes,
listed below, so the minor version is bumped.

### Security

- An API key (or any header value) containing a character that HTTP headers
  cannot carry, such as the trailing newline of a key read from a file or a
  pasted non-breaking or zero-width space, was printed in full in exception
  messages and logs, and the request was retried three times. Header values
  are now validated before sending, and the request fails at once with an
  `AiInvalidRequestException` that names the header but not its value.
  Network errors of unknown types are now described by type only.

### Bug fixes

**Anthropic**

- Claude 5 models (including the default `claude-sonnet-5`) think by
  default, and the API requires the `thinking` blocks of a tool-use turn to
  be sent back unchanged. They were dropped, so agent and conversation tool
  loops failed with HTTP 400. `thinking` and `redacted_thinking` blocks are
  now kept, both from regular responses and from streams, in the first tool
  call's `metadata` (`AnthropicProvider.thinkingMetadataKey`), and sent back
  before the tool calls.
- `temperature` and `topP` made the default model fail with HTTP 400. They
  are now sent only to models that accept them; see Behaviour changes.

**Gemini**

- Tool results that are not JSON-encodable (for example a map holding a
  `DateTime`) crashed request encoding with a raw `JsonUnsupportedObjectError`.
  The 0.0.2 fix covered OpenAI and Anthropic only. Gemini now normalises tool
  results the same way (`toJson()`, then `toString()`).
- Usage ignored `thoughtsTokenCount` and `toolUsePromptTokenCount`, so
  `outputTokens` and `AiCostTracker` under-reported billed output on
  thinking models (the default included). See Behaviour changes.
- An invalid API key (HTTP 400 with reason `API_KEY_INVALID`) raised
  `AiInvalidRequestException`. It now raises `AiAuthenticationException`.

**OpenAI and OpenAI-compatible servers**

- In OpenAI streams, the finish reason came on the second-to-last chunk and
  the usage on the last one, which then had `finishReason: null`. The two
  are now merged, so the last chunk carries both, as the README states.
- Refusals were returned as an empty reply with finish reason `stop`.
  The refusal text is now the reply text, with `AiFinishReason.contentFilter`,
  in both `chat` and `stream`. `generate` reports it.
- `CustomProvider` claimed the full OpenAI capability set for every server.
  The capabilities are now configurable; see New features.

**Client, middleware and helpers**

- A chat timeout threw `AiTimeoutException` but left the HTTP request
  running, so the provider kept generating (and billing) abandoned
  completions, and retries piled up. Timed-out attempts are now aborted.
- A cache shared by several clients (or a persistent cache) served one
  provider's or server's answer to another, because keys ignored the
  provider. Keys now include the provider and its base URL.
- `Retry-After` on 5xx responses (for example OpenAI's 503 "model
  overloaded") was ignored. It is now honoured like on 429, capped at
  `maxDelay`.
- `AiAgent` ran the tools requested in its last iteration (side effects such
  as a refund) and then threw without sending their results to the model.
  It no longer runs tools whose results it cannot send back; see Behaviour
  changes.
- `generate` took the text from the first `{` to the last `}`, so a brace
  after the JSON (for example in a note) broke decoding. It now decodes the
  first balanced, valid JSON object, skipping braces inside strings.
- `AiPromptTemplate` silently left `{{ name }}` (with spaces) unrendered.
  Whitespace inside the braces is now allowed, and the variable is listed in
  `variables` and checked like any other.
- `AiKnowledgeBase.ingestBatch` sent every document in one embeddings
  request, which OpenAI rejects above 2048 inputs. Documents are now
  embedded in slices; see New features.
- Request bodies that cannot be JSON-encoded raise `AiInvalidRequestException`
  instead of a raw `JsonUnsupportedObjectError`.
- The `AiModel` documentation used the retired `gemini-2.0-flash`.

### Behaviour changes

- **Default model:** OpenAI and custom providers default to `gpt-6-luna`
  instead of `gpt-4o-mini`, which OpenAI deprecated on 2026-10-14 and removes
  from the API on 2027-01-14. `gpt-6-luna` supports function calling in Chat
  Completions only with `reasoning_effort: "none"`, so `OpenAiProvider` sends
  that when a `gpt-6-luna` request has tools. Set a model explicitly if you
  depended on the old default.
- **Gemini usage:** `outputTokens` now includes thinking tokens
  (`candidatesTokenCount + thoughtsTokenCount`), which Gemini bills as
  output, and `inputTokens` includes `toolUsePromptTokenCount`. Costs from
  `AiCostTracker` go up accordingly; input plus output now equals
  `totalTokens`.
- **Gemini invalid key:** raises `AiAuthenticationException` (status 400)
  instead of `AiInvalidRequestException`.
- **Cache keys:** the prefix changed from `ai_plus:v1:` to `ai_plus:v2:` and
  keys include the provider and base URL. Entries written by 0.0.2 are no
  longer found, so **persistent caches start cold** after upgrading. Old
  entries can be deleted or left to expire.
- **`AiAgent.maxIterations`** now limits rounds of tool execution. After the
  last round the model gets one more call to answer; if it still asks for
  tools, `AiToolException` is thrown without running them. A run makes at
  most `maxIterations + 1` model calls (0.0.2 made at most `maxIterations`
  and allowed only `maxIterations - 1` useful tool rounds).
- **Anthropic sampling parameters:** `temperature` and `topP` are sent only
  to Claude 3.x and Claude 4 models up to 4.6, on API versions before
  `2026-10-21`. Other models (Claude Sonnet 5, Opus 4.7 and later, Haiku 5.5,
  Fable and unknown model names) reject them, so they are omitted. Claude 4.x
  models accept only one of the two per request, so when both are set only
  `temperature` is sent. `AiClient` logs a one-time warning per model
  through its `logger` whenever a parameter is omitted.
- **Anthropic default `max_tokens`:** 1024 → 16000 (4096 for Claude 3.x
  models, whose output limits are lower). Claude 5 models think by default
  and thinking counts toward `max_tokens`, so 1024 often cut answers short.
  It is a cap, not a charge; set `maxTokens` to limit spend.
- **Anthropic usage:** `inputTokens` now includes prompt-cache reads and
  writes (`cache_read_input_tokens`, `cache_creation_input_tokens`), like
  OpenAI's and Gemini's prompt counts, so it is the whole prompt.
- **Provider names in exceptions:** errors raised by `AiClient` and
  `AiAgent` (timeouts, unsupported capabilities, structured output, tool
  limit) now use the same `provider` names as HTTP errors: `OpenAI`,
  `Gemini`, `Anthropic`, `Custom` (was `OpenAiProvider`, ...). Other
  providers still use their type name.
- **Timeouts:** `AiClient.timeout` aborts the HTTP request of a timed-out
  `chat` attempt.
- **Header validation:** header values with control or non-ASCII characters
  are rejected before sending (see Security). Such values never reached the
  provider before either: dart:io rejected them.
- **`http` 1.6.0 or later** is required (was 1.2.0). http 1.2.x buffered
  whole responses on the web, so streaming did not work there; 1.5.0 added
  abortable requests and 1.6.0 fixed web stream cancellation. The minimum
  Dart SDK is still 3.4.

### New features

- **Cancellation:** `abortTrigger` parameter on `AiClient.chat`, `stream`,
  `streamText` and `generate`, `AiConversation.send` and `stream`, and
  `AiAgent.run`. Completing the future aborts the HTTP request or response
  stream and fails the call with `AiTimeoutException`; it is not retried, a
  conversation's history is left unchanged, and an agent starts no further
  tools. It reaches middleware and providers as `AiRequest.abortTrigger`
  (not part of the cache key); `AiHttpClient.post`, `postStream` and
  `postSse` accept it too.
- `AiUsage.reasoningTokens` (OpenAI `reasoning_tokens`, Gemini
  `thoughtsTokenCount`) and `AiUsage.cachedInputTokens` (OpenAI
  `cached_tokens`, Gemini `cachedContentTokenCount`, Anthropic
  `cache_read_input_tokens`), as parts of `outputTokens` and `inputTokens`.
  `AiUsage.toString` lists all counts.
- `AiPricing.cachedInputCostPerToken` and
  `AiCostTracker.totalCachedInputTokens`: cached input is charged at its own
  rate when one is set.
- `AiProviderException.retryAfter`, parsed from `retry-after` /
  `retry-after-ms` on 5xx responses.
- `capabilities` parameter on `CustomProvider` and `AiProvider.custom`
  (default: the full OpenAI set). `AiClient` checks it before sending tools
  or streaming, and `generate` falls back to prompt-based JSON when
  `structuredOutput` is false.
- `CacheMiddleware(cache, namespace:)` and
  `CacheMiddleware.cacheKey(request, namespace:)`. `AiClient` sets the
  namespace automatically.
- `AiKnowledgeBase.ingestBatch(batchSize:)` (default 100). Documents are
  stored only after every slice has been embedded.
- `AnthropicProvider.thinkingMetadataKey`,
  `AnthropicProvider.legacyDefaultMaxTokens`, `OpenAiProvider.defaultModel`
  and `CustomProvider.defaultModel`.

### Documentation

- README snippets that did not compile (the provider-switching example
  redeclared `ai`; the middleware example called an undefined function) are
  fixed.

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
