/// A production-ready, provider-agnostic AI SDK for Dart & Flutter.
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
library ai_plus;

// Core Abstractions
export 'src/core/ai_client.dart';
export 'src/core/ai_provider.dart';
export 'src/core/ai_request.dart';
export 'src/core/ai_response.dart';
export 'src/core/ai_stream.dart';
export 'src/core/ai_capabilities.dart';

// Models
export 'src/models/ai_message.dart';
export 'src/models/ai_content.dart';
export 'src/models/ai_usage.dart';
export 'src/models/ai_finish_reason.dart';
export 'src/models/ai_model.dart';

// Errors
export 'src/errors/ai_exception.dart';

// Middleware & Plugins
export 'src/middleware/ai_middleware.dart';
export 'src/middleware/retry_middleware.dart';
export 'src/middleware/cache_middleware.dart';
export 'src/middleware/logging_middleware.dart';
export 'src/middleware/metrics_middleware.dart';
export 'src/retry/retry_policy.dart';
export 'src/cache/ai_cache.dart';
export 'src/cache/memory_ai_cache.dart';
export 'src/logging/ai_logger.dart';

// Tools & Structured Output
export 'src/tools/ai_tool.dart';
export 'src/tools/tool_executor.dart';
export 'src/structured_output/schema.dart';

// Chat & Conversations
export 'src/chat/conversation.dart';
export 'src/chat/conversation_storage.dart';

// Embeddings & RAG
export 'src/embeddings/embedding.dart';
export 'src/embeddings/embedding_service.dart';
export 'src/rag/vector_store.dart';
export 'src/rag/knowledge_base.dart';

// Agent
export 'src/agent/ai_agent.dart';

// Utilities
export 'src/utils/prompt_template.dart';
export 'src/utils/cost_tracker.dart';
