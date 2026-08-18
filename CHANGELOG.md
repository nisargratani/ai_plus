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
