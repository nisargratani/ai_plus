import 'dart:typed_data';

import 'ai_message.dart';

/// Represents a piece of content within an [AiMessage].
///
/// This is a sealed hierarchy, so a `switch` over an [AiContent] can be
/// checked for exhaustiveness.
sealed class AiContent {
  /// Base constructor for subclasses.
  const AiContent();
}

/// Represents text content within an [AiMessage].
class AiTextContent extends AiContent {
  /// The text.
  final String text;

  /// Creates a text content part.
  const AiTextContent(this.text);
}

/// Represents an image within an [AiMessage].
class AiImageContent extends AiContent {
  /// The MIME type of the image.
  final String mimeType;

  /// The raw bytes of the image.
  final Uint8List bytes;

  /// Creates an image content part from raw [bytes].
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

  /// Creates an audio content part from raw [bytes].
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

  /// Creates a file content part from raw [bytes].
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
  ///
  /// Empty when the model supplied no arguments or produced invalid JSON.
  final Map<String, dynamic> arguments;

  /// Opaque, provider-specific data that must be sent back to the provider
  /// together with this tool call (for example Gemini's `thoughtSignature`).
  ///
  /// Providers populate and consume this automatically. Preserve it when
  /// persisting and restoring conversations that contain tool calls.
  final Map<String, dynamic> metadata;

  /// Creates a tool call content part.
  const AiToolCallContent({
    required this.id,
    required this.name,
    required this.arguments,
    this.metadata = const {},
  });
}

/// Represents the result of a tool execution.
class AiToolResultContent extends AiContent {
  /// The unique identifier of the tool call this result belongs to.
  final String id;

  /// The name of the tool that was executed.
  final String name;

  /// The result of the execution.
  ///
  /// Strings are sent verbatim; other values are JSON-encoded (using
  /// `toJson()` when available, otherwise `toString()`).
  final dynamic result;

  /// Whether the tool execution resulted in an error.
  final bool isError;

  /// Creates a tool result content part.
  const AiToolResultContent({
    required this.id,
    required this.name,
    required this.result,
    this.isError = false,
  });
}
