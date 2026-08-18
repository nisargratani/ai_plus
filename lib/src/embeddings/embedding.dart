import '../models/ai_usage.dart';

/// Represents a single vector embedding.
class AiEmbedding {
  /// The floating point vector representation of the input text.
  final List<double> vector;

  const AiEmbedding(this.vector);
}

/// Represents the result of an embedding request.
class AiEmbeddingResult {
  /// The list of embeddings returned by the provider.
  final List<AiEmbedding> embeddings;

  /// The usage statistics for this request.
  final AiUsage usage;

  const AiEmbeddingResult({
    required this.embeddings,
    this.usage = AiUsage.empty,
  });

  /// Convenience getter for the first embedding vector.
  List<double> get vector => embeddings.first.vector;
}
