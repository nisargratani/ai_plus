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

/// An AI provider implementation for the OpenAI API.
///
/// Supports chat completions, streaming, tool calling, multimodal input,
/// structured output, and embeddings.
///
/// ```dart
/// final provider = AiProvider.openAI(apiKey: 'sk-...');
/// ```
class OpenAiProvider implements AiProvider {
  /// The API key for authentication.
  final String apiKey;

  /// The base URL for the OpenAI API.
  final String baseUrl;

  final AiHttpClient _httpClient;

  /// Creates an OpenAI provider.
  ///
  /// An optional [httpClient] can be provided for testing.
  OpenAiProvider({
    required this.apiKey,
    this.baseUrl = 'https://api.openai.com/v1',
    AiHttpClient? httpClient,
  }) : _httpClient = httpClient ?? AiHttpClient();

  @override
  AiCapabilities get capabilities => const AiCapabilities(
        streaming: true,
        toolCalling: true,
        structuredOutput: true,
        embeddings: true,
        imageInput: true,
        audioInput: false,
        fileInput: false,
      );

  @override
  Future<AiResponse> chat(AiRequest request) async {
    final body = _buildRequestBody(request);

    final result = await _httpClient.post(
      Uri.parse('$baseUrl/chat/completions'),
      headers: _buildHeaders(),
      body: body,
    );

    return _parseResponse(result);
  }

  @override
  Stream<AiStreamChunk> stream(AiRequest request) async* {
    final body = _buildRequestBody(request)..['stream'] = true;

    final rawStream = _httpClient.postStream(
      Uri.parse('$baseUrl/chat/completions'),
      headers: _buildHeaders(),
      body: body,
    );

    // Buffer for handling partial SSE lines
    String buffer = '';

    await for (final chunk in rawStream) {
      buffer += chunk;
      final lines = buffer.split('\n');
      // Keep the last potentially incomplete line in buffer
      buffer = lines.removeLast();

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        if (!trimmed.startsWith('data: ')) continue;

        final data = trimmed.substring(6).trim();
        if (data == '[DONE]') return;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          yield _parseStreamChunk(json);
        } catch (e) {
          if (e is AiException) rethrow;
          throw AiParsingException('Failed to parse stream chunk: $e',
              provider: 'OpenAI', rawResponse: data);
        }
      }
    }

    // Process any remaining buffered data
    if (buffer.trim().isNotEmpty && buffer.trim().startsWith('data: ')) {
      final data = buffer.trim().substring(6).trim();
      if (data != '[DONE]' && data.isNotEmpty) {
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          yield _parseStreamChunk(json);
        } catch (_) {
          // Ignore trailing incomplete chunks
        }
      }
    }
  }

  @override
  Future<AiEmbeddingResult> embeddings(List<String> inputs,
      {String? model}) async {
    final body = <String, dynamic>{
      'model': model ?? 'text-embedding-3-small',
      'input': inputs,
    };

    final result = await _httpClient.post(
      Uri.parse('$baseUrl/embeddings'),
      headers: _buildHeaders(),
      body: body,
    );

    try {
      final data = result['data'] as List;
      final embeddingsList = data.map((e) {
        final vec = (e['embedding'] as List)
            .cast<num>()
            .map((n) => n.toDouble())
            .toList();
        return AiEmbedding(vec);
      }).toList();

      final usageJson = result['usage'] as Map<String, dynamic>?;
      final usage = usageJson != null
          ? AiUsage(
              inputTokens: usageJson['prompt_tokens'] as int?,
              totalTokens: usageJson['total_tokens'] as int?,
            )
          : AiUsage.empty;

      return AiEmbeddingResult(embeddings: embeddingsList, usage: usage);
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiParsingException('Failed to parse OpenAI embeddings response: $e',
          provider: 'OpenAI', rawResponse: jsonEncode(result));
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────

  Map<String, String> _buildHeaders() {
    return {
      'Authorization': 'Bearer $apiKey',
    };
  }

  Map<String, dynamic> _buildRequestBody(AiRequest request) {
    final body = <String, dynamic>{
      'model': request.model ?? 'gpt-4o-mini',
      'messages': request.messages.map(_mapMessage).toList(),
      if (request.maxTokens != null) 'max_tokens': request.maxTokens,
      if (request.temperature != null) 'temperature': request.temperature,
      if (request.topP != null) 'top_p': request.topP,
      if (request.stop != null) 'stop': request.stop,
    };

    // Tool definitions
    if (request.tools != null && request.tools!.isNotEmpty) {
      body['tools'] = request.tools!.map((t) => t.toJson()).toList();
    }

    // Structured output via response_format
    if (request.schema != null) {
      body['response_format'] = {
        'type': 'json_schema',
        'json_schema': {
          'name': 'structured_output',
          'strict': true,
          'schema': request.schema!.toJson(),
        },
      };
    }

    return body;
  }

  Map<String, dynamic> _mapMessage(AiMessage message) {
    final role = _mapRole(message.role);

    // Check for tool call content (assistant message with tool calls)
    final toolCalls = message.content.whereType<AiToolCallContent>().toList();
    if (toolCalls.isNotEmpty) {
      return {
        'role': role,
        'content': message.text.isNotEmpty ? message.text : null,
        'tool_calls': toolCalls
            .map((tc) => {
                  'id': tc.id,
                  'type': 'function',
                  'function': {
                    'name': tc.name,
                    'arguments': jsonEncode(tc.arguments),
                  },
                })
            .toList(),
      };
    }

    // Check for tool result content
    final toolResults =
        message.content.whereType<AiToolResultContent>().toList();
    if (toolResults.isNotEmpty) {
      // OpenAI expects one message per tool result
      // For simplicity, we return the first; callers should split if needed
      final result = toolResults.first;
      return {
        'role': 'tool',
        'tool_call_id': result.id,
        'content': result.result is String
            ? result.result as String
            : jsonEncode(result.result),
      };
    }

    // Check if the message has multimodal content
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
          'type': 'image_url',
          'image_url': {
            'url': 'data:$mimeType;base64,${base64Encode(bytes)}',
          },
        };
      case AiAudioContent():
        throw const AiUnsupportedCapabilityException(
          'Audio content is not supported by OpenAI chat completions',
          provider: 'OpenAI',
        );
      case AiFileContent():
        throw const AiUnsupportedCapabilityException(
          'File content is not supported by OpenAI chat completions',
          provider: 'OpenAI',
        );
      case AiToolCallContent():
        return {'type': 'text', 'text': ''};
      case AiToolResultContent():
        return {'type': 'text', 'text': ''};
    }
  }

  String _mapRole(AiMessageRole role) {
    switch (role) {
      case AiMessageRole.system:
        return 'system';
      case AiMessageRole.developer:
        return 'developer';
      case AiMessageRole.user:
        return 'user';
      case AiMessageRole.assistant:
        return 'assistant';
      case AiMessageRole.tool:
        return 'tool';
    }
  }

  AiResponse _parseResponse(Map<String, dynamic> json) {
    try {
      final choices = json['choices'] as List;
      if (choices.isEmpty) {
        throw const AiParsingException('No choices returned by OpenAI',
            provider: 'OpenAI');
      }

      final choice = choices.first;
      final messageJson = choice['message'] as Map<String, dynamic>;
      final message = _parseAssistantMessage(messageJson);

      final usageJson = json['usage'] as Map<String, dynamic>?;
      final usage = usageJson != null
          ? AiUsage(
              inputTokens: usageJson['prompt_tokens'] as int?,
              outputTokens: usageJson['completion_tokens'] as int?,
              totalTokens: usageJson['total_tokens'] as int?,
            )
          : AiUsage.empty;

      return AiResponse(
        message: message,
        finishReason: _parseFinishReason(choice['finish_reason']),
        usage: usage,
        raw: json,
      );
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiParsingException('Failed to parse response: $e',
          provider: 'OpenAI', rawResponse: jsonEncode(json));
    }
  }

  AiMessage _parseAssistantMessage(Map<String, dynamic> messageJson) {
    final contentParts = <AiContent>[];

    // Parse text content
    final contentStr = messageJson['content'] as String?;
    if (contentStr != null && contentStr.isNotEmpty) {
      contentParts.add(AiTextContent(contentStr));
    }

    // Parse tool calls
    final toolCallsJson = messageJson['tool_calls'] as List?;
    if (toolCallsJson != null) {
      for (final tc in toolCallsJson) {
        final function = tc['function'] as Map<String, dynamic>;
        Map<String, dynamic> arguments;
        try {
          arguments = jsonDecode(function['arguments'] as String)
              as Map<String, dynamic>;
        } catch (_) {
          arguments = {};
        }

        contentParts.add(AiToolCallContent(
          id: tc['id'] as String,
          name: function['name'] as String,
          arguments: arguments,
        ));
      }
    }

    return AiMessage(
      role: AiMessageRole.assistant,
      content: contentParts,
    );
  }

  AiStreamChunk _parseStreamChunk(Map<String, dynamic> json) {
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      // Could be usage metadata
      final usageJson = json['usage'] as Map<String, dynamic>?;
      if (usageJson != null) {
        return AiStreamChunk(
          usage: AiUsage(
            inputTokens: usageJson['prompt_tokens'] as int?,
            outputTokens: usageJson['completion_tokens'] as int?,
            totalTokens: usageJson['total_tokens'] as int?,
          ),
          raw: json,
        );
      }
      return AiStreamChunk(raw: json);
    }

    final choice = choices.first;
    final delta = choice['delta'] as Map<String, dynamic>?;
    final contentParts = <AiContent>[];

    // Text content
    final contentStr = delta?['content'] as String?;
    if (contentStr != null) {
      contentParts.add(AiTextContent(contentStr));
    }

    // Streaming tool calls
    final toolCallsJson = delta?['tool_calls'] as List?;
    if (toolCallsJson != null) {
      for (final tc in toolCallsJson) {
        final function = tc['function'] as Map<String, dynamic>?;
        if (function != null) {
          final argsStr = function['arguments'] as String? ?? '';
          Map<String, dynamic> arguments;
          try {
            arguments = argsStr.isNotEmpty
                ? jsonDecode(argsStr) as Map<String, dynamic>
                : {};
          } catch (_) {
            arguments = {};
          }

          contentParts.add(AiToolCallContent(
            id: tc['id'] as String? ?? '',
            name: function['name'] as String? ?? '',
            arguments: arguments,
          ));
        }
      }
    }

    return AiStreamChunk(
      content: contentParts,
      finishReason: _parseFinishReason(choice['finish_reason']),
      raw: json,
    );
  }

  AiFinishReason _parseFinishReason(dynamic reason) {
    switch (reason) {
      case 'stop':
        return AiFinishReason.stop;
      case 'length':
        return AiFinishReason.length;
      case 'tool_calls':
        return AiFinishReason.toolCalls;
      case 'content_filter':
        return AiFinishReason.contentFilter;
      default:
        return AiFinishReason.unknown;
    }
  }
}
