import '../embeddings/embedding.dart';
import '../http/ai_http_client.dart';
import '../providers/anthropic/anthropic_provider.dart';
import '../providers/custom/custom_provider.dart';
import '../providers/gemini/gemini_provider.dart';
import '../providers/openai/openai_provider.dart';
import 'ai_capabilities.dart';
import 'ai_request.dart';
import 'ai_response.dart';
import 'ai_stream.dart';

/// The base interface for all AI provider adapters.
///
/// Use the factory constructors for the built-in providers, or implement this
/// interface to integrate any other backend:
///
/// ```dart
/// class MyProvider implements AiProvider {
///   @override
///   AiCapabilities get capabilities => const AiCapabilities(streaming: true);
///   // ...
/// }
/// ```
abstract interface class AiProvider {
  /// Creates an [OpenAiProvider].
  ///
  /// [headers] are sent with every request. See [OpenAiProvider] for details.
  factory AiProvider.openAI({
    required String apiKey,
    String baseUrl = 'https://api.openai.com/v1',
    Map<String, String> headers = const {},
    AiHttpClient? httpClient,
  }) {
    return OpenAiProvider(
      apiKey: apiKey,
      baseUrl: baseUrl,
      headers: headers,
      httpClient: httpClient,
    );
  }

  /// Creates a [GeminiProvider] for the Google Gemini API.
  factory AiProvider.gemini({
    required String apiKey,
    String baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    Map<String, String> headers = const {},
    AiHttpClient? httpClient,
  }) {
    return GeminiProvider(
      apiKey: apiKey,
      baseUrl: baseUrl,
      headers: headers,
      httpClient: httpClient,
    );
  }

  /// Creates an [AnthropicProvider] (Claude).
  factory AiProvider.anthropic({
    required String apiKey,
    String baseUrl = 'https://api.anthropic.com/v1',
    String apiVersion = '2023-06-01',
    Map<String, String> headers = const {},
    AiHttpClient? httpClient,
  }) {
    return AnthropicProvider(
      apiKey: apiKey,
      baseUrl: baseUrl,
      apiVersion: apiVersion,
      headers: headers,
      httpClient: httpClient,
    );
  }

  /// Creates a [CustomProvider] for any OpenAI-compatible endpoint
  /// (Ollama, LocalAI, vLLM, Groq, OpenRouter, Azure OpenAI, ...).
  ///
  /// Pass an empty [apiKey] for servers that need no authentication, and use
  /// [headers] for non-bearer schemes such as Azure's `api-key` header.
  factory AiProvider.custom({
    required String baseUrl,
    required String apiKey,
    Map<String, String> headers = const {},
    AiHttpClient? httpClient,
  }) {
    return CustomProvider(
      baseUrl: baseUrl,
      apiKey: apiKey,
      headers: headers,
      httpClient: httpClient,
    );
  }

  /// Sends a request to the provider and returns a single response.
  Future<AiResponse> chat(AiRequest request);

  /// Sends a request to the provider and streams the response back in chunks.
  ///
  /// Implementations should emit [AiStreamChunk.finishReason] only on the
  /// final chunk, and emit each tool call once, with complete arguments.
  Stream<AiStreamChunk> stream(AiRequest request);

  /// Generates embeddings for the given input text(s), in input order.
  Future<AiEmbeddingResult> embeddings(List<String> inputs, {String? model});

  /// Returns the capabilities supported by this provider.
  AiCapabilities get capabilities;
}
