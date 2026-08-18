import 'dart:convert';
import '../../core/ai_provider.dart';
import '../../core/ai_request.dart';
import '../../core/ai_response.dart';
import '../../core/ai_stream.dart';
import '../../core/ai_capabilities.dart';
import '../../models/ai_message.dart';
import '../../models/ai_content.dart';
import '../../models/ai_usage.dart';
import '../../models/ai_finish_reason.dart';
import '../../embeddings/embedding.dart';
import '../../http/ai_http_client.dart';
import '../../errors/ai_exception.dart';

/// An AI provider implementation for Anthropic (Claude).
///
/// Supports chat, streaming, tool calling, and multimodal (image) input.
/// Anthropic does not provide a native embeddings endpoint.
///
/// ```dart
/// final provider = AiProvider.anthropic(apiKey: 'sk-ant-...');
/// ```
class AnthropicProvider implements AiProvider {
  /// The API key for authentication.
  final String apiKey;

  /// The base URL for the Anthropic API.
  final String baseUrl;

  /// The Anthropic API version header.
  final String apiVersion;

  final AiHttpClient _httpClient;

  /// Creates an Anthropic provider.
  ///
  /// An optional [httpClient] can be provided for testing.
  AnthropicProvider({
    required this.apiKey,
    this.baseUrl = 'https://api.anthropic.com/v1',
    this.apiVersion = '2023-06-01',
    AiHttpClient? httpClient,
  }) : _httpClient = httpClient ?? AiHttpClient();

  @override
  AiCapabilities get capabilities => const AiCapabilities(
        streaming: true,
        toolCalling: true,
        structuredOutput: false,
        embeddings: false,
        imageInput: true,
        audioInput: false,
        fileInput: false,
      );

  @override
  Future<AiResponse> chat(AiRequest request) async {
    final body = _buildRequestBody(request);

    final result = await _httpClient.post(
      Uri.parse('$baseUrl/messages'),
      headers: _buildHeaders(),
      body: body,
    );

    return _parseResponse(result);
  }

  @override
  Stream<AiStreamChunk> stream(AiRequest request) async* {
    final body = _buildRequestBody(request)..['stream'] = true;

    final rawStream = _httpClient.postStream(
      Uri.parse('$baseUrl/messages'),
      headers: _buildHeaders(),
      body: body,
    );

    String buffer = '';

    await for (final chunk in rawStream) {
      buffer += chunk;
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (!trimmed.startsWith('data: ')) continue;

        final data = trimmed.substring(6).trim();
        if (data.isEmpty) continue;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final type = json['type'] as String?;

          if (type == 'content_block_start' ||
              type == 'content_block_delta' ||
              type == 'message_delta') {
            yield _parseStreamChunk(json);
          }
        } catch (e) {
          if (e is AiException) rethrow;
          throw AiParsingException('Failed to parse Anthropic stream chunk: $e',
              provider: 'Anthropic', rawResponse: data);
        }
      }
    }
  }

  @override
  Future<AiEmbeddingResult> embeddings(List<String> inputs,
      {String? model}) async {
    throw const AiUnsupportedCapabilityException(
      'Anthropic does not currently provide a native embeddings API endpoint.',
      provider: 'Anthropic',
    );
  }

  // ── Private helpers ──────────────────────────────────────────────────

  Map<String, String> _buildHeaders() {
    return {
      'x-api-key': apiKey,
      'anthropic-version': apiVersion,
    };
  }

  Map<String, dynamic> _buildRequestBody(AiRequest request) {
    // Extract system instructions
    final systemMessages = request.messages
        .where((m) =>
            m.role == AiMessageRole.system || m.role == AiMessageRole.developer)
        .map((m) => m.text)
        .join('\n');

    // Build conversation messages (must alternate user/assistant)
    final messages = <Map<String, dynamic>>[];
    for (final m in request.messages) {
      if (m.role == AiMessageRole.system || m.role == AiMessageRole.developer) {
        continue; // Handled as top-level system
      }
      messages.add(_mapMessage(m));
    }

    final body = <String, dynamic>{
      'model': request.model ?? 'claude-sonnet-4-20250514',
      'max_tokens': request.maxTokens ?? 1024,
      'messages': messages,
      if (systemMessages.isNotEmpty) 'system': systemMessages,
      if (request.temperature != null) 'temperature': request.temperature,
      if (request.topP != null) 'top_p': request.topP,
      if (request.stop != null) 'stop_sequences': request.stop,
    };

    // Tool definitions
    if (request.tools != null && request.tools!.isNotEmpty) {
      body['tools'] = request.tools!
          .map((t) => {
                'name': t.name,
                'description': t.description,
                'input_schema': t.parameters.toJson(),
              })
          .toList();
    }

    return body;
  }

  Map<String, dynamic> _mapMessage(AiMessage message) {
    final role = _mapRole(message.role);

    // Handle tool result messages
    final toolResults =
        message.content.whereType<AiToolResultContent>().toList();
    if (toolResults.isNotEmpty) {
      return {
        'role': 'user',
        'content': toolResults
            .map((r) => {
                  'type': 'tool_result',
                  'tool_use_id': r.id,
                  'content': r.result is String
                      ? r.result as String
                      : jsonEncode(r.result),
                  if (r.isError) 'is_error': true,
                })
            .toList(),
      };
    }

    // Handle assistant messages with tool calls
    final toolCalls = message.content.whereType<AiToolCallContent>().toList();
    if (toolCalls.isNotEmpty) {
      final contentBlocks = <Map<String, dynamic>>[];

      // Add text if present
      final text = message.text;
      if (text.isNotEmpty) {
        contentBlocks.add({'type': 'text', 'text': text});
      }

      // Add tool use blocks
      for (final tc in toolCalls) {
        contentBlocks.add({
          'type': 'tool_use',
          'id': tc.id,
          'name': tc.name,
          'input': tc.arguments,
        });
      }

      return {
        'role': role,
        'content': contentBlocks,
      };
    }

    // Handle multimodal content
    final hasMultimodal = message.content.any((c) =>
        c is AiImageContent || c is AiAudioContent || c is AiFileContent);

    if (hasMultimodal) {
      return {
        'role': role,
        'content': message.content.map(_mapContent).toList(),
      };
    }

    // Simple text message
    return {
      'role': role,
      'content': message.text,
    };
  }

  Map<String, dynamic> _mapContent(AiContent content) {
    switch (content) {
      case AiTextContent(:final text):
        return {'type': 'text', 'text': text};
      case AiImageContent(:final mimeType, :final bytes):
        return {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': mimeType,
            'data': base64Encode(bytes),
          },
        };
      case AiAudioContent():
        throw const AiUnsupportedCapabilityException(
          'Audio content is not supported by Anthropic',
          provider: 'Anthropic',
        );
      case AiFileContent():
        throw const AiUnsupportedCapabilityException(
          'File content is not supported by Anthropic',
          provider: 'Anthropic',
        );
      case AiToolCallContent():
        return {'type': 'text', 'text': ''};
      case AiToolResultContent():
        return {'type': 'text', 'text': ''};
    }
  }

  String _mapRole(AiMessageRole role) {
    switch (role) {
      case AiMessageRole.user:
        return 'user';
      case AiMessageRole.assistant:
        return 'assistant';
      case AiMessageRole.tool:
        return 'user'; // Tool results come as user messages in Anthropic
      case AiMessageRole.system:
      case AiMessageRole.developer:
        return 'user'; // Handled separately
    }
  }

  AiResponse _parseResponse(Map<String, dynamic> json) {
    try {
      final content = json['content'] as List?;
      if (content == null || content.isEmpty) {
        throw const AiParsingException('No content returned by Anthropic',
            provider: 'Anthropic');
      }

      final message = _parseAssistantContent(content);

      final usageJson = json['usage'] as Map<String, dynamic>?;
      final usage = usageJson != null
          ? AiUsage(
              inputTokens: usageJson['input_tokens'] as int?,
              outputTokens: usageJson['output_tokens'] as int?,
              totalTokens: (usageJson['input_tokens'] as int? ?? 0) +
                  (usageJson['output_tokens'] as int? ?? 0),
            )
          : AiUsage.empty;

      return AiResponse(
        message: message,
        finishReason: _parseFinishReason(json['stop_reason']),
        usage: usage,
        raw: json,
      );
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiParsingException('Failed to parse Anthropic response: $e',
          provider: 'Anthropic', rawResponse: jsonEncode(json));
    }
  }

  AiMessage _parseAssistantContent(List<dynamic> contentBlocks) {
    final contentParts = <AiContent>[];

    for (final block in contentBlocks) {
      final blockMap = block as Map<String, dynamic>;
      final type = blockMap['type'] as String?;

      if (type == 'text') {
        final text = blockMap['text'] as String? ?? '';
        if (text.isNotEmpty) {
          contentParts.add(AiTextContent(text));
        }
      } else if (type == 'tool_use') {
        contentParts.add(AiToolCallContent(
          id: blockMap['id'] as String,
          name: blockMap['name'] as String,
          arguments: (blockMap['input'] as Map<String, dynamic>?) ?? {},
        ));
      }
    }

    if (contentParts.isEmpty) {
      contentParts.add(const AiTextContent(''));
    }

    return AiMessage(
      role: AiMessageRole.assistant,
      content: contentParts,
    );
  }

  AiStreamChunk _parseStreamChunk(Map<String, dynamic> json) {
    final type = json['type'] as String?;

    if (type == 'content_block_start') {
      final contentBlock = json['content_block'] as Map<String, dynamic>?;
      if (contentBlock?['type'] == 'tool_use') {
        return AiStreamChunk(
          content: [
            AiToolCallContent(
              id: contentBlock!['id'] as String? ?? '',
              name: contentBlock['name'] as String? ?? '',
              arguments: const {},
            )
          ],
          raw: json,
        );
      }
      return AiStreamChunk(raw: json);
    }

    if (type == 'content_block_delta') {
      final delta = json['delta'] as Map<String, dynamic>?;
      if (delta?['type'] == 'text_delta') {
        final text = delta?['text'] as String? ?? '';
        return AiStreamChunk(
          content: [AiTextContent(text)],
          raw: json,
        );
      }
      if (delta?['type'] == 'input_json_delta') {
        // Partial JSON for tool call arguments — emit as text for now
        return AiStreamChunk(raw: json);
      }
    }

    if (type == 'message_delta') {
      final delta = json['delta'] as Map<String, dynamic>?;
      final usageJson = json['usage'] as Map<String, dynamic>?;

      return AiStreamChunk(
        finishReason: _parseFinishReason(delta?['stop_reason']),
        usage: usageJson != null
            ? AiUsage(outputTokens: usageJson['output_tokens'] as int?)
            : null,
        raw: json,
      );
    }

    return AiStreamChunk(raw: json);
  }

  AiFinishReason _parseFinishReason(dynamic reason) {
    switch (reason) {
      case 'end_turn':
        return AiFinishReason.stop;
      case 'max_tokens':
        return AiFinishReason.length;
      case 'stop_sequence':
        return AiFinishReason.stop;
      case 'tool_use':
        return AiFinishReason.toolCalls;
      default:
        return AiFinishReason.unknown;
    }
  }
}
