// Internal to the package; not exported.

import '../core/ai_provider.dart';
import 'anthropic/anthropic_provider.dart';
import 'custom/custom_provider.dart';
import 'gemini/gemini_provider.dart';
import 'openai/openai_provider.dart';

/// The name put in the `provider` field of exceptions about [provider].
///
/// The same short names the built-in providers use for HTTP errors
/// (`OpenAI`, `Gemini`, `Anthropic`, `Custom`), or the runtime type of any
/// other provider.
String providerName(AiProvider provider) {
  final Object p = provider;
  return switch (p) {
    OpenAiProvider() => 'OpenAI',
    GeminiProvider() => 'Gemini',
    AnthropicProvider() => 'Anthropic',
    CustomProvider() => 'Custom',
    _ => p.runtimeType.toString(),
  };
}

/// Identifies [provider] and its endpoint, for cache keys.
String providerNamespace(AiProvider provider) {
  final Object p = provider;
  final baseUrl = switch (p) {
    OpenAiProvider(:final baseUrl) => baseUrl,
    GeminiProvider(:final baseUrl) => baseUrl,
    AnthropicProvider(:final baseUrl) => baseUrl,
    CustomProvider(:final baseUrl) => baseUrl,
    _ => null,
  };
  final name = providerName(provider);
  return baseUrl == null ? name : '$name|$baseUrl';
}
