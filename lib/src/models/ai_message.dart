import 'ai_content.dart';

/// Defines the role of the message sender.
enum AiMessageRole {
  system,
  developer,
  user,
  assistant,
  tool,
}

/// Represents a single message in a conversation.
class AiMessage {
  /// The role of the message sender.
  final AiMessageRole role;

  /// The content of the message.
  final List<AiContent> content;

  const AiMessage({
    required this.role,
    required this.content,
  });

  /// Convenience constructor for a message containing only text.
  factory AiMessage.text({
    required AiMessageRole role,
    required String text,
  }) {
    return AiMessage(
      role: role,
      content: [AiTextContent(text)],
    );
  }

  /// Convenience constructor for a system message.
  factory AiMessage.system(String text) {
    return AiMessage.text(
      role: AiMessageRole.system,
      text: text,
    );
  }

  /// Convenience constructor for a developer message.
  factory AiMessage.developer(String text) {
    return AiMessage.text(
      role: AiMessageRole.developer,
      text: text,
    );
  }

  /// Convenience constructor for a user message.
  factory AiMessage.user(String text) {
    return AiMessage.text(
      role: AiMessageRole.user,
      text: text,
    );
  }

  /// Convenience constructor for an assistant message.
  factory AiMessage.assistant(String text) {
    return AiMessage.text(
      role: AiMessageRole.assistant,
      text: text,
    );
  }

  /// Convenience constructor for a tool response message.
  factory AiMessage.tool(String text) {
    return AiMessage.text(
      role: AiMessageRole.tool,
      text: text,
    );
  }

  /// Convenience getter for the text content of the message, assuming it contains text.
  /// If it contains multiple text elements, they are concatenated.
  String get text {
    return content.whereType<AiTextContent>().map((e) => e.text).join('\n');
  }
}
