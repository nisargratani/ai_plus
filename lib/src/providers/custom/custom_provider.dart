import '../../core/ai_provider.dart';
import '../../core/ai_request.dart';
import '../../core/ai_response.dart';
import '../../core/ai_stream.dart';
import '../../core/ai_capabilities.dart';
import '../../embeddings/embedding.dart';
import '../../http/ai_http_client.dart';
import '../openai/openai_provider.dart';

/// A custom provider that implements the OpenAI API specification.
/// Useful for LocalAI, Ollama (with OpenAI compatibility), or other compatible services.
class CustomProvider implements AiProvider {
  final OpenAiProvider _internalProvider;

  CustomProvider({
    required String baseUrl,
    required String apiKey,
    AiHttpClient? httpClient,
  }) : _internalProvider = OpenAiProvider(
          apiKey: apiKey,
          baseUrl: baseUrl,
          httpClient: httpClient,
        );

  @override
  AiCapabilities get capabilities => _internalProvider.capabilities;

  @override
  Future<AiResponse> chat(AiRequest request) {
    return _internalProvider.chat(request);
  }

  @override
  Stream<AiStreamChunk> stream(AiRequest request) {
    return _internalProvider.stream(request);
  }

  @override
  Future<AiEmbeddingResult> embeddings(List<String> inputs, {String? model}) {
    return _internalProvider.embeddings(inputs, model: model);
  }
}
