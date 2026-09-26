import 'dart:convert';

import '../../core/ai_capabilities.dart';
import '../../core/ai_provider.dart';
import '../../core/ai_request.dart';
import '../../core/ai_response.dart';
import '../../core/ai_stream.dart';
import '../../embeddings/embedding.dart';
import '../../errors/ai_exception.dart';
import '../../http/ai_http_client.dart';
import '../../models/ai_content.dart';
import '../../models/ai_finish_reason.dart';
import '../../models/ai_message.dart';
import '../../models/ai_usage.dart';
import '../../utils/json_utils.dart';
import '../closeable_provider.dart';

/// An AI provider implementation for Anthropic (Claude).
///
/// Supports chat, streaming (including streamed tool calls), tool calling
/// and image input. Anthropic does not provide an embeddings endpoint, and
/// structured output is handled by `AiClient.generate` via prompting.
///
/// ```dart
/// final provider = AiProvider.anthropic(apiKey: 'sk-ant-...');
/// ```
///
/// Defaults to the `claude-sonnet-5` model and `max_tokens: 1024` (the
/// Messages API requires an explicit output limit).
class AnthropicProvider implements AiProvider, CloseableProvider {
  /// Creates an Anthropic provider.
  ///
  /// [headers] are sent with every request (for example `anthropic-beta`).
  /// A [httpClient] passed in is not closed by [close]; the caller owns it.
  AnthropicProvider({
    required this.apiKey,
    this.baseUrl = 'https://api.anthropic.com/v1',
    this.apiVersion = '2023-06-01',
    Map<String, String> headers = const {},
    AiHttpClient? httpClient,
  })  : _headers = {
          'x-api-key': apiKey,
          'anthropic-version': apiVersion,
          ...headers,
        },
        _ownsHttpClient = httpClient == null,
        _httpClient = httpClient ?? AiHttpClient();

  /// The model used when a request does not specify one.
  static const defaultModel = 'claude-sonnet-5';

  /// The `max_tokens` used when a request does not specify one.
  static const defaultMaxTokens = 1024;

  static const _provider = 'Anthropic';

  /// The API key for authentication.
  final String apiKey;

  /// The base URL for the Anthropic API.
  final String baseUrl;

  /// The Anthropic API version header.
  final String apiVersion;

  final Map<String, String> _headers;
  final AiHttpClient _httpClient;
  final bool _ownsHttpClient;

  @override
  AiCapabilities get capabilities => const AiCapabilities(
        streaming: true,
        toolCalling: true,
        imageInput: true,
      );

  Uri get _messagesUri {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base/messages');
  }

  @override
  Future<AiResponse> chat(AiRequest request) async {
    final result = await _httpClient.post(
      _messagesUri,
      headers: _headers,
      body: _buildRequestBody(request),
      provider: _provider,
    );
    return _parseResponse(result);
  }

  @override
  Stream<AiStreamChunk> stream(AiRequest request) async* {
    final body = _buildRequestBody(request)..['stream'] = true;
    final state = _StreamState();

    await for (final data in _httpClient.postSse(
      _messagesUri,
      headers: _headers,
      body: body,
      provider: _provider,
    )) {
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(data) as Map<String, dynamic>;
      } catch (e) {
        throw AiParsingException(
          'Failed to parse Anthropic stream chunk: $e',
          provider: _provider,
          rawResponse: data,
        );
      }

      final chunk = _parseStreamEvent(json, state);
      if (chunk != null) yield chunk;
      if (json['type'] == 'message_stop') break;
    }
  }

  @override
  Future<AiEmbeddingResult> embeddings(
    List<String> inputs, {
    String? model,
  }) async {
    throw const AiUnsupportedCapabilityException(
      'Anthropic does not currently provide a native embeddings API endpoint.',
      provider: _provider,
    );
  }

  /// Closes the HTTP client created by this provider.
  ///
  /// Called automatically by `AiClient.close`.
  @override
  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  // ── Request building ────────────────────────────────────────────────

  Map<String, dynamic> _buildRequestBody(AiRequest request) {
    final system = request.messages
        .where((m) =>
            m.role == AiMessageRole.system || m.role == AiMessageRole.developer)
        .map((m) => m.text)
        .join('\n');

    final body = <String, dynamic>{
      'model': request.model ?? defaultModel,
      'max_tokens': request.maxTokens ?? defaultMaxTokens,
      'messages': [
        for (final m in request.messages)
          if (m.role != AiMessageRole.system &&
              m.role != AiMessageRole.developer)
            _mapMessage(m),
      ],
      if (system.isNotEmpty) 'system': system,
      if (request.temperature != null) 'temperature': request.temperature,
      if (request.topP != null) 'top_p': request.topP,
      if (request.stop != null) 'stop_sequences': request.stop,
    };

    final tools = request.tools;
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = [
        for (final t in tools)
          {
            'name': t.name,
            'description': t.description,
            'input_schema': t.parameters.toJson(),
          },
      ];
    }

    return body;
  }

  Map<String, dynamic> _mapMessage(AiMessage message) {
    final toolResults =
        message.content.whereType<AiToolResultContent>().toList();
    if (toolResults.isNotEmpty) {
      return {
        'role': 'user',
        'content': [
          for (final r in toolResults)
            {
              'type': 'tool_result',
              'tool_use_id': r.id,
              'content': encodeToolResult(r.result),
              if (r.isError) 'is_error': true,
            },
        ],
      };
    }

    final role = message.role == AiMessageRole.assistant ? 'assistant' : 'user';

    final toolCalls = message.content.whereType<AiToolCallContent>().toList();
    if (toolCalls.isNotEmpty) {
      final text = message.text;
      return {
        'role': role,
        'content': [
          if (text.isNotEmpty) {'type': 'text', 'text': text},
          for (final tc in toolCalls)
            {
              'type': 'tool_use',
              'id': tc.id,
              'name': tc.name,
              'input': tc.arguments,
            },
        ],
      };
    }

    final hasMultimodal = message.content.any(
      (c) => c is AiImageContent || c is AiAudioContent || c is AiFileContent,
    );
    if (hasMultimodal) {
      return {
        'role': role,
        'content': [
          for (final c in message.content)
            if (_mapContent(c) case final block?) block,
        ],
      };
    }

    return {'role': role, 'content': message.text};
  }

  Map<String, dynamic>? _mapContent(AiContent content) {
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
          provider: _provider,
        );
      case AiFileContent():
        throw const AiUnsupportedCapabilityException(
          'File content is not supported by Anthropic',
          provider: _provider,
        );
      case AiToolCallContent():
      case AiToolResultContent():
        return null; // Handled at the message level.
    }
  }

  // ── Response parsing ────────────────────────────────────────────────

  AiResponse _parseResponse(Map<String, dynamic> json) {
    try {
      // An empty `content` array is valid (e.g. an immediate stop sequence).
      final blocks = (json['content'] as List?) ?? const [];
      final content = <AiContent>[];

      for (final block in blocks.cast<Map<String, dynamic>>()) {
        switch (block['type']) {
          case 'text':
            final text = block['text'] as String? ?? '';
            if (text.isNotEmpty) content.add(AiTextContent(text));
          case 'tool_use':
            content.add(AiToolCallContent(
              id: block['id'] as String,
              name: block['name'] as String,
              arguments: (block['input'] as Map<String, dynamic>?) ?? {},
            ));
        }
      }

      final usageJson = json['usage'] as Map<String, dynamic>?;
      return AiResponse(
        message: AiMessage(
          role: AiMessageRole.assistant,
          content: content.isEmpty ? [const AiTextContent('')] : content,
        ),
        finishReason:
            _parseFinishReason(json['stop_reason']) ?? AiFinishReason.unknown,
        usage: usageJson != null
            ? _usage(
                usageJson['input_tokens'] as int?,
                usageJson['output_tokens'] as int?,
              )
            : AiUsage.empty,
        raw: json,
      );
    } catch (e) {
      throw AiParsingException(
        'Failed to parse Anthropic response: $e',
        provider: _provider,
        rawResponse: jsonEncode(json),
      );
    }
  }

  AiStreamChunk? _parseStreamEvent(
    Map<String, dynamic> json,
    _StreamState state,
  ) {
    switch (json['type']) {
      case 'message_start':
        final message = json['message'] as Map<String, dynamic>?;
        final usage = message?['usage'] as Map<String, dynamic>?;
        state.inputTokens = usage?['input_tokens'] as int?;
        return null;

      case 'content_block_start':
        final block = json['content_block'] as Map<String, dynamic>?;
        if (block?['type'] == 'tool_use') {
          state.toolCalls[json['index'] as int] = _ToolUseBuilder(
            id: block!['id'] as String? ?? '',
            name: block['name'] as String? ?? '',
          );
        }
        return null;

      case 'content_block_delta':
        final delta = json['delta'] as Map<String, dynamic>?;
        switch (delta?['type']) {
          case 'text_delta':
            final text = delta!['text'] as String? ?? '';
            if (text.isEmpty) return null;
            return AiStreamChunk(content: [AiTextContent(text)], raw: json);
          case 'input_json_delta':
            state.toolCalls[json['index']]?.json
                .write(delta!['partial_json'] as String? ?? '');
        }
        return null;

      case 'content_block_stop':
        final builder = state.toolCalls.remove(json['index']);
        if (builder == null) return null;
        return AiStreamChunk(content: [builder.build()], raw: json);

      case 'message_delta':
        final delta = json['delta'] as Map<String, dynamic>?;
        final usageJson = json['usage'] as Map<String, dynamic>?;
        return AiStreamChunk(
          finishReason: _parseFinishReason(delta?['stop_reason']),
          usage: usageJson != null
              ? _usage(
                  (usageJson['input_tokens'] as int?) ?? state.inputTokens,
                  usageJson['output_tokens'] as int?,
                )
              : null,
          raw: json,
        );

      case 'error':
        throw _streamError(json['error'] as Map<String, dynamic>?);
    }
    return null;
  }

  static AiException _streamError(Map<String, dynamic>? error) {
    final type = error?['type'] as String?;
    final message = 'Stream error: ${error?['message'] ?? type ?? 'unknown'}';
    switch (type) {
      case 'rate_limit_error':
        return AiRateLimitException(message, provider: _provider);
      case 'overloaded_error':
        return AiProviderException(message,
            provider: _provider, statusCode: 529);
      case 'api_error':
        return AiProviderException(message,
            provider: _provider, statusCode: 500);
      default:
        return AiProviderException(message, provider: _provider);
    }
  }

  static AiUsage _usage(int? input, int? output) => AiUsage(
        inputTokens: input,
        outputTokens: output,
        totalTokens: (input ?? 0) + (output ?? 0),
      );

  static AiFinishReason? _parseFinishReason(Object? reason) {
    switch (reason) {
      case null:
        return null;
      case 'end_turn':
      case 'stop_sequence':
        return AiFinishReason.stop;
      case 'max_tokens':
      case 'model_context_window_exceeded':
        return AiFinishReason.length;
      case 'tool_use':
        return AiFinishReason.toolCalls;
      case 'refusal':
        return AiFinishReason.contentFilter;
      default:
        return AiFinishReason.unknown;
    }
  }
}

class _StreamState {
  int? inputTokens;
  final Map<int, _ToolUseBuilder> toolCalls = {};
}

class _ToolUseBuilder {
  _ToolUseBuilder({required this.id, required this.name});

  final String id;
  final String name;
  final StringBuffer json = StringBuffer();

  AiToolCallContent build() => AiToolCallContent(
        id: id,
        name: name,
        arguments: decodeJsonObject(json.toString()),
      );
}
