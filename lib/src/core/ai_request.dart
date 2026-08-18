import '../models/ai_message.dart';
import '../tools/ai_tool.dart';
import '../structured_output/schema.dart';

/// Represents a request to an AI provider.
///
/// This is an immutable value object that encapsulates all parameters
/// needed for a chat completion request.
class AiRequest {
  /// The list of messages in the conversation so far.
  final List<AiMessage> messages;

  /// The model to use for the request (optional, falls back to provider default).
  final String? model;

  /// The maximum number of tokens to generate.
  final int? maxTokens;

  /// The sampling temperature to use, between 0 and 2.
  ///
  /// Higher values (e.g. 0.8) make output more random, lower values
  /// (e.g. 0.2) make it more focused and deterministic.
  final double? temperature;

  /// An alternative to sampling with temperature, called nucleus sampling.
  ///
  /// The model considers the results of the tokens with top_p probability mass.
  final double? topP;

  /// Stop sequences where the model will stop generating further tokens.
  final List<String>? stop;

  /// A list of tools the model may call.
  final List<AiTool>? tools;

  /// An optional JSON schema for structured output.
  ///
  /// When provided, providers that support structured output natively
  /// will use this to constrain the model's response format.
  final AiJsonSchema? schema;

  const AiRequest({
    required this.messages,
    this.model,
    this.maxTokens,
    this.temperature,
    this.topP,
    this.stop,
    this.tools,
    this.schema,
  });

  /// Creates a copy of this request with the given fields replaced with the new values.
  AiRequest copyWith({
    List<AiMessage>? messages,
    String? model,
    int? maxTokens,
    double? temperature,
    double? topP,
    List<String>? stop,
    List<AiTool>? tools,
    AiJsonSchema? schema,
  }) {
    return AiRequest(
      messages: messages ?? this.messages,
      model: model ?? this.model,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      stop: stop ?? this.stop,
      tools: tools ?? this.tools,
      schema: schema ?? this.schema,
    );
  }
}
