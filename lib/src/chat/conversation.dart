import '../agent/ai_agent.dart';
import '../core/ai_client.dart';
import '../core/ai_response.dart';
import '../core/ai_stream.dart';
import '../models/ai_content.dart';
import '../models/ai_message.dart';
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

  static int _idCounter = 0;

  /// A unique identifier for this conversation.
  final String id;

  /// The model to use for this conversation.
  final String? model;

  /// The tools available in this conversation.
  ///
  /// Tool calls are returned to you but not executed automatically; use
  /// [AiAgent] for an automatic tool loop.
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
  /// constructing this directly. When [id] is omitted a process-unique id is
  /// generated.
  AiConversation(
    this._client, {
    String? id,
    this.model,
    this.tools,
    this.maxTokens,
    this.temperature,
    List<AiMessage> initialMessages = const [],
  }) : id = id ?? '${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}' {
    _messages.addAll(initialMessages);
  }

  /// Sends a text message to the AI and returns the response.
  ///
  /// The user message and the assistant's response are added to the history
  /// together once the request succeeds. If the request fails the history is
  /// left unchanged, so the call can simply be retried.
  ///
  /// Calls should not overlap: await each [send] before the next one.
  Future<AiResponse> send(String text) async {
    final userMessage = AiMessage.user(text);

    final response = await _client.chat(
      messages: [..._messages, userMessage],
      model: model,
      tools: tools,
      maxTokens: maxTokens,
      temperature: temperature,
    );

    _messages
      ..add(userMessage)
      ..add(response.message);
    return response;
  }

  /// Sends a text message to the AI and streams the response.
  ///
  /// When the stream completes successfully, the user message and the full
  /// assistant response (assembled from the chunks) are added to the
  /// history. If the stream fails or is cancelled, the history is left
  /// unchanged.
  ///
  /// ```dart
  /// await for (final chunk in conversation.stream('Tell me a joke')) {
  ///   stdout.write(chunk.text);
  /// }
  /// // After the stream completes, the full response is in conversation.messages
  /// ```
  Stream<AiStreamChunk> stream(String text) async* {
    final userMessage = AiMessage.user(text);
    final textBuffer = StringBuffer();
    final otherContent = <AiContent>[];

    await for (final chunk in _client.stream(
      messages: [..._messages, userMessage],
      model: model,
      tools: tools,
      maxTokens: maxTokens,
      temperature: temperature,
    )) {
      for (final part in chunk.content) {
        if (part is AiTextContent) {
          textBuffer.write(part.text);
        } else {
          otherContent.add(part);
        }
      }
      yield chunk;
    }

    _messages
      ..add(userMessage)
      ..add(AiMessage(
        role: AiMessageRole.assistant,
        content: [
          if (textBuffer.isNotEmpty || otherContent.isEmpty)
            AiTextContent(textBuffer.toString()),
          ...otherContent,
        ],
      ));
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
