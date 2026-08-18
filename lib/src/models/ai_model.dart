/// Represents an AI model identifier.
///
/// This is a lightweight descriptor class that can be used instead of
/// raw model name strings when you want more structure.
///
/// ```dart
/// const gpt4o = AiModel(name: 'gpt-4o', provider: 'openai');
/// const gemini = AiModel(name: 'gemini-2.0-flash', provider: 'gemini');
///
/// final response = await ai.chat(
///   messages: [...],
///   model: gpt4o.name,
/// );
/// ```
class AiModel {
  /// The model name as expected by the provider API.
  final String name;

  /// An optional provider hint (e.g. 'openai', 'gemini', 'anthropic').
  final String? provider;

  /// An optional human-readable display name.
  final String? displayName;

  /// Creates an AI model descriptor.
  const AiModel({
    required this.name,
    this.provider,
    this.displayName,
  });

  @override
  String toString() => displayName ?? name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AiModel &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          provider == other.provider;

  @override
  int get hashCode => name.hashCode ^ (provider?.hashCode ?? 0);
}
