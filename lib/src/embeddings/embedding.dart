import '../models/ai_usage.dart';

/// Represents a single vector embedding.
class AiEmbedding {
  /// The floating point vector representation of the input text.
  final List<double> vector;

  /// Creates an embedding from its [vector].
  const AiEmbedding(this.vector);
}

/// Represents the result of an embedding request.
class AiEmbeddingResult {
  /// The list of embeddings returned by the provider.
  final List<AiEmbedding> embeddings;

  /// The usage statistics for this request.
  final AiUsage usage;

  /// Creates an embedding result.
  const AiEmbeddingResult({
    required this.embeddings,
    this.usage = AiUsage.empty,
  });

  /// Convenience getter for the first embedding vector.
  ///
  /// Throws a [StateError] if [embeddings] is empty.
  List<double> get vector => embeddings.first.vector;
}
