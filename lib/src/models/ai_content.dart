import 'dart:typed_data';

/// Represents a piece of content within an [AiMessage].
sealed class AiContent {
  const AiContent();
}

/// Represents text content within an [AiMessage].
class AiTextContent extends AiContent {
  final String text;

  const AiTextContent(this.text);
}

/// Represents an image within an [AiMessage].
class AiImageContent extends AiContent {
  /// The MIME type of the image.
  final String mimeType;

  /// The raw bytes of the image.
  final Uint8List bytes;

  const AiImageContent({
    required this.mimeType,
    required this.bytes,
  });
}

/// Represents an audio file within an [AiMessage].
class AiAudioContent extends AiContent {
  /// The MIME type of the audio.
  final String mimeType;

  /// The raw bytes of the audio.
  final Uint8List bytes;

  const AiAudioContent({
    required this.mimeType,
    required this.bytes,
  });
}

/// Represents a generic file attachment within an [AiMessage].
class AiFileContent extends AiContent {
  /// The MIME type of the file.
  final String mimeType;

  /// The raw bytes of the file.
  final Uint8List bytes;

  const AiFileContent({
    required this.mimeType,
    required this.bytes,
  });
}

/// Represents a tool call requested by the AI.
class AiToolCallContent extends AiContent {
  /// A unique identifier for this tool call.
  final String id;

  /// The name of the tool to call.
  final String name;

  /// The arguments provided by the model.
  final Map<String, dynamic> arguments;

  const AiToolCallContent({
    required this.id,
    required this.name,
    required this.arguments,
  });
}

/// Represents the result of a tool execution.
class AiToolResultContent extends AiContent {
  /// The unique identifier of the tool call this result belongs to.
  final String id;

  /// The name of the tool that was executed.
  final String name;

  /// The result of the execution.
  final dynamic result;

  /// Whether the tool execution resulted in an error.
  final bool isError;

  const AiToolResultContent({
    required this.id,
    required this.name,
    required this.result,
    this.isError = false,
  });
}
