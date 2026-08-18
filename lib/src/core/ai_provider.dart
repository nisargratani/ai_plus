import 'ai_capabilities.dart';
import 'ai_request.dart';
import 'ai_response.dart';
import 'ai_stream.dart';
import '../embeddings/embedding.dart';

import '../providers/openai/openai_provider.dart';
import '../providers/gemini/gemini_provider.dart';
import '../providers/anthropic/anthropic_provider.dart';
import '../providers/custom/custom_provider.dart';

/// The base interface for all AI provider adapters.
abstract interface class AiProvider {
  /// Creates an OpenAI provider.
  factory AiProvider.openAI({
    required String apiKey,
    String baseUrl = 'https://api.openai.com/v1',
  }) {
    return OpenAiProvider(apiKey: apiKey, baseUrl: baseUrl);
  }

  /// Creates a Google Gemini provider.
  factory AiProvider.gemini({
    required String apiKey,
    String baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
  }) {
    return GeminiProvider(apiKey: apiKey, baseUrl: baseUrl);
  }

  /// Creates an Anthropic (Claude) provider.
  factory AiProvider.anthropic({
    required String apiKey,
    String baseUrl = 'https://api.anthropic.com/v1',
    String apiVersion = '2023-06-01',
  }) {
    return AnthropicProvider(
        apiKey: apiKey, baseUrl: baseUrl, apiVersion: apiVersion);
  }

  /// Creates a custom provider that uses the OpenAI API specification.
  factory AiProvider.custom({
    required String baseUrl,
    required String apiKey,
  }) {
    return CustomProvider(baseUrl: baseUrl, apiKey: apiKey);
  }

  /// Sends a request to the provider and returns a single response.
  Future<AiResponse> chat(AiRequest request);

  /// Sends a request to the provider and streams the response back in chunks.
  Stream<AiStreamChunk> stream(AiRequest request);

  /// Generates embeddings for the given input text(s).
  Future<AiEmbeddingResult> embeddings(List<String> inputs, {String? model});

  /// Returns the capabilities supported by this provider.
  AiCapabilities get capabilities;
}
