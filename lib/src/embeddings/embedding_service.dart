import 'embedding.dart';
import '../core/ai_provider.dart';

/// Service to handle embedding creation.
class AiEmbeddingService {
  final AiProvider _provider;

  const AiEmbeddingService(this._provider);

  /// Creates embeddings for a single string input.
  Future<AiEmbeddingResult> create({
    required String input,
    String? model,
  }) {
    return _provider.embeddings([input], model: model);
  }

  /// Creates embeddings for a batch of strings.
  Future<AiEmbeddingResult> createBatch({
    required List<String> inputs,
    String? model,
  }) {
    return _provider.embeddings(inputs, model: model);
  }
}
