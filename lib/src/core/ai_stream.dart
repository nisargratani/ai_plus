import '../models/ai_content.dart';
import '../models/ai_usage.dart';
import '../models/ai_finish_reason.dart';

/// Represents a chunk of a streaming response from an AI provider.
class AiStreamChunk {
  /// The partial content generated in this chunk.
  final List<AiContent> content;

  /// The finish reason, if this is the final chunk.
  final AiFinishReason? finishReason;

  /// Usage information, typically only provided in the final chunk (if supported).
  final AiUsage? usage;

  /// The raw JSON chunk from the provider (optional).
  final Map<String, dynamic>? raw;

  const AiStreamChunk({
    this.content = const [],
    this.finishReason,
    this.usage,
    this.raw,
  });

  /// Convenience getter for the text content of this chunk.
  String get text {
    return content.whereType<AiTextContent>().map((e) => e.text).join();
  }
}
