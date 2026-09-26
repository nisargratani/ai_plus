import '../core/ai_provider.dart';
import 'embedding.dart';

/// Creates embeddings through an [AiProvider].
///
/// Obtain one from `AiClient.embeddings`.
class AiEmbeddingService {
  final AiProvider _provider;

  /// Creates an embedding service backed by the given provider.
  const AiEmbeddingService(this._provider);

  /// Creates an embedding for a single string input.
  Future<AiEmbeddingResult> create({
    required String input,
    String? model,
  }) {
    return _provider.embeddings([input], model: model);
  }

  /// Creates embeddings for a batch of strings in one request.
  ///
  /// The returned embeddings are in the same order as [inputs]. An empty
  /// [inputs] list returns an empty result without a network call.
  Future<AiEmbeddingResult> createBatch({
    required List<String> inputs,
    String? model,
  }) async {
    if (inputs.isEmpty) return const AiEmbeddingResult(embeddings: []);
    return _provider.embeddings(inputs, model: model);
  }
}
