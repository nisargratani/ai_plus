import '../../core/ai_capabilities.dart';
import '../../core/ai_provider.dart';
import '../../core/ai_request.dart';
import '../../core/ai_response.dart';
import '../../core/ai_stream.dart';
import '../../embeddings/embedding.dart';
import '../../http/ai_http_client.dart';
import '../closeable_provider.dart';
import 'openai_api.dart';

/// An AI provider implementation for the OpenAI API.
///
/// Supports chat completions, streaming (including streamed tool calls and
/// usage), tool calling, image input, structured output and embeddings.
///
/// ```dart
/// final provider = AiProvider.openAI(apiKey: 'sk-...');
/// ```
///
/// Defaults to the `gpt-4o-mini` model and `text-embedding-3-small`
/// embeddings when no model is specified.
class OpenAiProvider implements AiProvider, CloseableProvider {
  /// Creates an OpenAI provider.
  ///
  /// - [baseUrl]: override to use a proxy or an OpenAI-compatible gateway.
  /// - [headers]: extra headers sent with every request (for example
  ///   `OpenAI-Organization` or `OpenAI-Project`).
  /// - [httpClient]: inject a custom client, e.g. for testing. A client
  ///   passed in is not closed by [close]; the caller owns it.
  OpenAiProvider({
    required this.apiKey,
    this.baseUrl = 'https://api.openai.com/v1',
    Map<String, String> headers = const {},
    AiHttpClient? httpClient,
  }) : _api = OpenAiApi(
          apiKey: apiKey,
          baseUrl: baseUrl,
          headers: headers,
          providerName: 'OpenAI',
          defaultModel: 'gpt-4o-mini',
          httpClient: httpClient,
        );

  /// The API key for authentication.
  final String apiKey;

  /// The base URL for the OpenAI API.
  final String baseUrl;

  final OpenAiApi _api;

  @override
  AiCapabilities get capabilities => OpenAiApi.capabilities;

  @override
  Future<AiResponse> chat(AiRequest request) => _api.chat(request);

  @override
  Stream<AiStreamChunk> stream(AiRequest request) => _api.stream(request);

  @override
  Future<AiEmbeddingResult> embeddings(List<String> inputs, {String? model}) =>
      _api.embeddings(inputs, model: model);

  /// Closes the HTTP client created by this provider.
  ///
  /// Called automatically by `AiClient.close`.
  @override
  void close() => _api.close();
}
