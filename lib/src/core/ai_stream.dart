import '../models/ai_content.dart';
import '../models/ai_finish_reason.dart';
import '../models/ai_usage.dart';

/// Represents a chunk of a streaming response from an AI provider.
class AiStreamChunk {
  /// The partial content generated in this chunk.
  final List<AiContent> content;

  /// The finish reason; non-null only on the chunk that ends the generation.
  final AiFinishReason? finishReason;

  /// Usage information, typically only provided near the end of the stream.
  ///
  /// Values are cumulative for the request, not per chunk.
  final AiUsage? usage;

  /// The raw JSON chunk from the provider (optional).
  final Map<String, dynamic>? raw;

  /// Creates a stream chunk.
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
