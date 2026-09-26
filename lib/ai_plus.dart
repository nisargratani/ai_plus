/// A provider-agnostic AI SDK for Dart & Flutter.
///
/// Start with `AiClient` and one of the `AiProvider` factories:
///
/// ```dart
/// import 'package:ai_plus/ai_plus.dart';
///
/// final ai = AiClient(
///   provider: AiProvider.openAI(apiKey: apiKey),
/// );
///
/// final response = await ai.chat(
///   messages: [AiMessage.user('Hello!')],
/// );
/// print(response.text);
/// ```
///
/// Higher-level building blocks: `AiConversation` (multi-turn chat),
/// `AiAgent` (automatic tool loop), `AiKnowledgeBase` (RAG) and
/// `AiClient.generate` (typed structured output).
library;

export 'src/agent/ai_agent.dart';
export 'src/cache/ai_cache.dart';
export 'src/cache/memory_ai_cache.dart';
export 'src/chat/conversation.dart';
export 'src/chat/conversation_storage.dart';
export 'src/core/ai_capabilities.dart';
export 'src/core/ai_client.dart';
export 'src/core/ai_provider.dart';
export 'src/core/ai_request.dart';
export 'src/core/ai_response.dart';
export 'src/core/ai_stream.dart';
export 'src/embeddings/embedding.dart';
export 'src/embeddings/embedding_service.dart';
export 'src/errors/ai_exception.dart';
export 'src/http/ai_http_client.dart';
export 'src/logging/ai_logger.dart';
export 'src/middleware/ai_middleware.dart';
export 'src/middleware/cache_middleware.dart';
export 'src/middleware/logging_middleware.dart';
export 'src/middleware/metrics_middleware.dart';
export 'src/middleware/retry_middleware.dart';
export 'src/models/ai_content.dart';
export 'src/models/ai_finish_reason.dart';
export 'src/models/ai_message.dart';
export 'src/models/ai_model.dart';
export 'src/models/ai_usage.dart';
export 'src/providers/anthropic/anthropic_provider.dart';
export 'src/providers/custom/custom_provider.dart';
export 'src/providers/gemini/gemini_provider.dart';
export 'src/providers/openai/openai_provider.dart';
export 'src/rag/knowledge_base.dart';
export 'src/rag/vector_store.dart';
export 'src/retry/retry_policy.dart';
export 'src/structured_output/schema.dart';
export 'src/tools/ai_tool.dart';
export 'src/tools/tool_executor.dart';
export 'src/utils/cost_tracker.dart';
export 'src/utils/prompt_template.dart';
