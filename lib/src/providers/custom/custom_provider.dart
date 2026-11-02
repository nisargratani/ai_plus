import '../../core/ai_capabilities.dart';
import '../../core/ai_provider.dart';
import '../../core/ai_request.dart';
import '../../core/ai_response.dart';
import '../../core/ai_stream.dart';
import '../../embeddings/embedding.dart';
import '../../http/ai_http_client.dart';
import '../closeable_provider.dart';
import '../openai/openai_api.dart';

/// A provider for any service implementing the OpenAI Chat Completions API,
/// such as Ollama, LocalAI, vLLM, LM Studio, Groq, Together AI, OpenRouter
/// or Azure OpenAI.
///
/// Compared to `OpenAiProvider` it uses the widely supported `max_tokens`
/// parameter, sends developer messages with the `system` role, does not
/// request streaming usage via `stream_options`, and omits the
/// `Authorization` header when [apiKey] is empty (e.g. for a local Ollama).
///
/// Always pass a `model` (per request or via `AiClient.defaultModel`); the
/// fallback `gpt-6-luna` rarely exists on third-party servers.
///
/// Servers differ in what they implement, so describe yours with
/// `capabilities` (by default the full OpenAI set is assumed). `AiClient`
/// checks them before sending tools, schemas or streaming requests:
///
/// ```dart
/// final ollama = AiProvider.custom(
///   baseUrl: 'http://localhost:11434/v1',
///   apiKey: '',
/// );
///
/// // A model without tools, vision or embeddings:
/// final small = AiProvider.custom(
///   baseUrl: 'http://localhost:11434/v1',
///   apiKey: '',
///   capabilities: const AiCapabilities(streaming: true),
/// );
///
/// // Azure OpenAI authenticates with an `api-key` header:
/// final azure = AiProvider.custom(
///   baseUrl: 'https://my-resource.openai.azure.com/openai/v1',
///   apiKey: '',
///   headers: {'api-key': azureKey},
/// );
/// ```
class CustomProvider implements AiProvider, CloseableProvider {
  /// Creates a provider for an OpenAI-compatible endpoint at [baseUrl].
  ///
  /// [headers] are sent with every request. [capabilities] describes what
  /// the server supports (default: everything the OpenAI protocol offers).
  /// A [httpClient] passed in is not closed by [close]; the caller owns it.
  CustomProvider({
    required this.baseUrl,
    required this.apiKey,
    Map<String, String> headers = const {},
    this.capabilities = OpenAiApi.capabilities,
    AiHttpClient? httpClient,
  }) : _api = OpenAiApi(
          apiKey: apiKey,
          baseUrl: baseUrl,
          headers: headers,
          providerName: 'Custom',
          defaultModel: defaultModel,
          legacyMaxTokens: true,
          streamUsage: false,
          developerRole: false,
          httpClient: httpClient,
        );

  /// The base URL of the OpenAI-compatible API (e.g. `.../v1`).
  final String baseUrl;

  /// The API key sent as a bearer token; may be empty.
  final String apiKey;

  final OpenAiApi _api;

  /// The model used when a request does not specify one.
  static const defaultModel = 'gpt-6-luna';

  /// What the server supports, as given to the constructor.
  @override
  final AiCapabilities capabilities;

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
