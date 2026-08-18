import '../core/ai_client.dart';
import '../core/ai_response.dart';
import '../core/ai_stream.dart';
import '../models/ai_message.dart';
import '../models/ai_content.dart';
import '../tools/ai_tool.dart';

/// Represents an ongoing conversation with an AI model.
///
/// A conversation maintains message history across multiple exchanges,
/// making it easy to build multi-turn interactions.
///
/// ```dart
/// final conversation = ai.conversation();
/// final response = await conversation.send('Hello');
/// final followUp = await conversation.send('Tell me more');
///
/// print(conversation.messages.length); // 4 (user + assistant × 2)
/// ```
class AiConversation {
  final AiClient _client;
  final List<AiMessage> _messages = [];

  /// A unique identifier for this conversation.
  final String id;

  /// The model to use for this conversation.
  final String? model;

  /// The tools available in this conversation.
  final List<AiTool>? tools;

  /// The maximum number of tokens per response.
  final int? maxTokens;

  /// The sampling temperature for this conversation.
  final double? temperature;

  /// Retrieves an unmodifiable copy of the current message history.
  List<AiMessage> get messages => List.unmodifiable(_messages);

  /// Creates a new conversation.
  ///
  /// Typically you would use [AiClient.conversation] instead of
  /// constructing this directly.
  AiConversation(
    this._client, {
    String? id,
    this.model,
    this.tools,
    this.maxTokens,
    this.temperature,
    List<AiMessage> initialMessages = const [],
  }) : id = id ?? DateTime.now().millisecondsSinceEpoch.toString() {
    _messages.addAll(initialMessages);
  }

  /// Sends a text message to the AI and returns the response.
  ///
  /// The user message and the assistant's response are both automatically
  /// added to the conversation history.
  Future<AiResponse> send(String text) async {
    _messages.add(AiMessage.user(text));

    final response = await _client.chat(
      messages: _messages,
      model: model,
      tools: tools,
      maxTokens: maxTokens,
      temperature: temperature,
    );

    _messages.add(response.message);
    return response;
  }

  /// Sends a text message to the AI and streams the response.
  ///
  /// The user message is added to history immediately. The full assistant
  /// response is assembled from stream chunks and added to history when
  /// the stream completes.
  ///
  /// ```dart
  /// await for (final chunk in conversation.stream('Tell me a joke')) {
  ///   stdout.write(chunk.text);
  /// }
  /// // After the stream completes, the full response is in conversation.messages
  /// ```
  Stream<AiStreamChunk> stream(String text) async* {
    _messages.add(AiMessage.user(text));

    final chunks = <AiStreamChunk>[];

    await for (final chunk in _client.stream(
      messages: _messages,
      model: model,
      tools: tools,
      maxTokens: maxTokens,
      temperature: temperature,
    )) {
      chunks.add(chunk);
      yield chunk;
    }

    // Assemble the full assistant message from all chunks
    final allContent = <AiContent>[];
    for (final chunk in chunks) {
      allContent.addAll(chunk.content);
    }

    if (allContent.isNotEmpty) {
      _messages.add(AiMessage(
        role: AiMessageRole.assistant,
        content: allContent,
      ));
    }
  }

  /// Adds a raw message to the history without triggering a request.
  ///
  /// Useful for restoring conversation state or injecting tool results.
  void addMessage(AiMessage message) {
    _messages.add(message);
  }

  /// Removes the last message from the history.
  void removeLast() {
    if (_messages.isNotEmpty) {
      _messages.removeLast();
    }
  }

  /// Clears the entire conversation history.
  void clear() {
    _messages.clear();
  }
}
