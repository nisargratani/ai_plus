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
import 'anthropic_sampling.dart';

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
/// Messages API requires an explicit output limit). `max_tokens` caps the
/// whole output, thinking included: Claude 5 models think by default, so
/// raise it for long or complex answers.
///
/// **Thinking:** when the model thinks before calling tools, its `thinking`
/// and `redacted_thinking` blocks are stored verbatim in the metadata of the
/// turn's first [AiToolCallContent] (under [thinkingMetadataKey]) and sent
/// back unchanged with the tool results, as the API requires. Keep
/// [AiToolCallContent.metadata] when persisting conversations.
///
/// **Sampling parameters:** `temperature` and `topP` are sent only to models
/// that accept them (Claude 3.x and Claude 4 up to 4.6, on API versions
/// before `2026-10-21`). Newer models, including the default, reject them
/// with HTTP 400, so they are omitted; `AiClient` logs a one-time warning
/// when that happens.
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
  ///
  /// It includes thinking tokens.
  static const defaultMaxTokens = 1024;

  /// The [AiToolCallContent.metadata] key holding the `thinking` and
  /// `redacted_thinking` blocks of a tool-use turn, as a list of the raw
  /// JSON blocks in their original order.
  static const thinkingMetadataKey = 'anthropic.thinking';

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
      abortTrigger: request.abortTrigger,
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
      abortTrigger: request.abortTrigger,
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

    final model = request.model ?? defaultModel;
    final sampling = anthropicAcceptsSampling(model, apiVersion);

    final body = <String, dynamic>{
      'model': model,
      'max_tokens': request.maxTokens ?? defaultMaxTokens,
      'messages': [
        for (final m in request.messages)
          if (m.role != AiMessageRole.system &&
              m.role != AiMessageRole.developer)
            _mapMessage(m),
      ],
      if (system.isNotEmpty) 'system': system,
      if (sampling && request.temperature != null)
        'temperature': request.temperature,
      if (sampling && request.topP != null) 'top_p': request.topP,
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
          // Thinking blocks must be sent back complete and unmodified,
          // before the tool_use blocks they accompanied.
          if (role == 'assistant') ..._thinkingBlocks(toolCalls),
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

  static List<Map<String, dynamic>> _thinkingBlocks(
    List<AiToolCallContent> toolCalls,
  ) {
    return [
      for (final call in toolCalls)
        if (call.metadata[thinkingMetadataKey] case final List<dynamic> blocks)
          for (final block in blocks)
            if (block is Map) Map<String, dynamic>.from(block),
    ];
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
      final thinking = <Map<String, dynamic>>[];

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
          case 'thinking':
          case 'redacted_thinking':
            thinking.add(Map<String, dynamic>.of(block));
        }
      }
      _attachThinking(content, thinking);

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

  /// Stores [thinking] on the first tool call in [content], which is where
  /// [_mapMessage] looks for it. Thinking is only needed for tool-use turns.
  static void _attachThinking(
    List<AiContent> content,
    List<Map<String, dynamic>> thinking,
  ) {
    if (thinking.isEmpty) return;
    final index = content.indexWhere((c) => c is AiToolCallContent);
    if (index < 0) return;
    content[index] = _withThinking(
      content[index] as AiToolCallContent,
      thinking,
    );
  }

  static AiToolCallContent _withThinking(
    AiToolCallContent call,
    List<Map<String, dynamic>> thinking,
  ) =>
      AiToolCallContent(
        id: call.id,
        name: call.name,
        arguments: call.arguments,
        metadata: {...call.metadata, thinkingMetadataKey: thinking},
      );

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
        final index = json['index'];
        if (index is! int) return null;
        switch (block?['type']) {
          case 'tool_use':
            state.toolCalls[index] = _ToolUseBuilder(
              id: block!['id'] as String? ?? '',
              name: block['name'] as String? ?? '',
            );
          case 'thinking':
            state.thinkingBlocks[index] = _ThinkingBuilder()
              ..text.write(block!['thinking'] as String? ?? '')
              ..signature.write(block['signature'] as String? ?? '');
          case 'redacted_thinking':
            state.thinkingBlocks[index] =
                _ThinkingBuilder(redacted: Map<String, dynamic>.of(block!));
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
          case 'thinking_delta':
            state.thinkingBlocks[json['index']]?.text
                .write(delta!['thinking'] as String? ?? '');
          case 'signature_delta':
            state.thinkingBlocks[json['index']]?.signature
                .write(delta!['signature'] as String? ?? '');
        }
        return null;

      case 'content_block_stop':
        final thinking = state.thinkingBlocks.remove(json['index']);
        if (thinking != null) {
          state.thinking.add(thinking.build());
          return null;
        }
        final builder = state.toolCalls.remove(json['index']);
        if (builder == null) return null;
        var call = builder.build();
        if (!state.thinkingAttached && state.thinking.isNotEmpty) {
          call = _withThinking(call, List.of(state.thinking));
          state.thinkingAttached = true;
        }
        return AiStreamChunk(content: [call], raw: json);

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

  /// Thinking blocks still being streamed, by content block index.
  final Map<int, _ThinkingBuilder> thinkingBlocks = {};

  /// Completed thinking blocks, in order.
  final List<Map<String, dynamic>> thinking = [];

  /// Whether [thinking] was attached to an emitted tool call.
  bool thinkingAttached = false;
}

/// Reassembles a `thinking` block from `thinking_delta` and
/// `signature_delta` events, or holds a `redacted_thinking` block verbatim.
class _ThinkingBuilder {
  _ThinkingBuilder({this.redacted});

  final Map<String, dynamic>? redacted;
  final StringBuffer text = StringBuffer();
  final StringBuffer signature = StringBuffer();

  // Same key order as the non-streaming API response.
  Map<String, dynamic> build() =>
      redacted ??
      {
        'type': 'thinking',
        'thinking': text.toString(),
        'signature': signature.toString(),
      };
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
