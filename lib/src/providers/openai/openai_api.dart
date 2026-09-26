import 'dart:convert';

import '../../core/ai_capabilities.dart';
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
import '../../structured_output/schema.dart';
import '../../utils/json_utils.dart';

/// Shared implementation of the OpenAI Chat Completions / Embeddings wire
/// protocol, used by `OpenAiProvider` and `CustomProvider`.
///
/// Internal to the package; not exported.
class OpenAiApi {
  /// Creates the protocol implementation.
  ///
  /// - [legacyMaxTokens]: send `max_tokens` instead of the newer
  ///   `max_completion_tokens` (most OpenAI-compatible servers only
  ///   understand the former).
  /// - [streamUsage]: request a final usage chunk via `stream_options`.
  /// - [developerRole]: send [AiMessageRole.developer] as `developer`
  ///   rather than `system`.
  OpenAiApi({
    required this.apiKey,
    required this.baseUrl,
    required this.providerName,
    required this.defaultModel,
    this.headers = const {},
    this.legacyMaxTokens = false,
    this.streamUsage = true,
    this.developerRole = true,
    AiHttpClient? httpClient,
  })  : _ownsHttpClient = httpClient == null,
        _httpClient = httpClient ?? AiHttpClient();

  /// The API key sent as a bearer token. Omitted when empty.
  final String apiKey;

  /// The API base URL, e.g. `https://api.openai.com/v1`.
  final String baseUrl;

  /// Name attached to exceptions.
  final String providerName;

  /// Model used when the request does not specify one.
  final String defaultModel;

  /// Extra headers sent with every request.
  final Map<String, String> headers;

  /// See the constructor.
  final bool legacyMaxTokens;

  /// See the constructor.
  final bool streamUsage;

  /// See the constructor.
  final bool developerRole;

  final AiHttpClient _httpClient;
  final bool _ownsHttpClient;

  /// Capabilities of the OpenAI protocol.
  static const capabilities = AiCapabilities(
    streaming: true,
    toolCalling: true,
    structuredOutput: true,
    embeddings: true,
    imageInput: true,
  );

  /// The default embeddings model.
  static const defaultEmbeddingModel = 'text-embedding-3-small';

  /// Sends a chat completion request.
  Future<AiResponse> chat(AiRequest request) async {
    final result = await _httpClient.post(
      _endpoint('chat/completions'),
      headers: _headers,
      body: buildRequestBody(request),
      provider: providerName,
    );
    return _parseResponse(result);
  }

  /// Sends a streaming chat completion request.
  ///
  /// Tool-call fragments are accumulated internally and emitted as complete
  /// [AiToolCallContent]s in the chunk that carries the finish reason.
  Stream<AiStreamChunk> stream(AiRequest request) async* {
    final body = buildRequestBody(request)..['stream'] = true;
    if (streamUsage) {
      body['stream_options'] = {'include_usage': true};
    }

    final toolCalls = <int, _ToolCallBuilder>{};

    await for (final data in _httpClient.postSse(
      _endpoint('chat/completions'),
      headers: _headers,
      body: body,
      provider: providerName,
    )) {
      if (data == '[DONE]') break;

      final Map<String, dynamic> json;
      try {
        json = jsonDecode(data) as Map<String, dynamic>;
      } catch (e) {
        throw AiParsingException(
          'Failed to parse stream chunk: $e',
          provider: providerName,
          rawResponse: data,
        );
      }

      final error = json['error'];
      if (error != null) {
        throw AiProviderException(
          'Stream error: ${error is Map ? error['message'] : error}',
          provider: providerName,
        );
      }

      final chunk = _parseStreamChunk(json, toolCalls);
      if (chunk != null) yield chunk;
    }

    // Some compatible servers end the stream without a finish reason.
    if (toolCalls.isNotEmpty) {
      yield AiStreamChunk(content: _drainToolCalls(toolCalls));
    }
  }

  /// Creates embeddings for [inputs].
  Future<AiEmbeddingResult> embeddings(
    List<String> inputs, {
    String? model,
  }) async {
    if (inputs.isEmpty) return const AiEmbeddingResult(embeddings: []);

    final result = await _httpClient.post(
      _endpoint('embeddings'),
      headers: _headers,
      body: {'model': model ?? defaultEmbeddingModel, 'input': inputs},
      provider: providerName,
    );

    try {
      final data = (result['data'] as List).cast<Map<String, dynamic>>();
      // The API documents `data` as ordered, but each item carries its
      // `index`; sorting guarantees results line up with `inputs`.
      final sorted = [...data]..sort(
          (a, b) => ((a['index'] as int?) ?? 0).compareTo(
            (b['index'] as int?) ?? 0,
          ),
        );
      final embeddings = [
        for (final item in sorted)
          AiEmbedding([
            for (final n in item['embedding'] as List) (n as num).toDouble(),
          ]),
      ];

      final usageJson = result['usage'] as Map<String, dynamic>?;
      final usage = usageJson != null
          ? AiUsage(
              inputTokens: usageJson['prompt_tokens'] as int?,
              totalTokens: usageJson['total_tokens'] as int?,
            )
          : AiUsage.empty;

      return AiEmbeddingResult(embeddings: embeddings, usage: usage);
    } catch (e) {
      throw AiParsingException(
        'Failed to parse embeddings response: $e',
        provider: providerName,
        rawResponse: jsonEncode(result),
      );
    }
  }

  /// Closes the HTTP client if this instance created it.
  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  // ── Request building ────────────────────────────────────────────────

  Uri _endpoint(String path) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return Uri.parse('$base/$path');
  }

  Map<String, String> get _headers => {
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
        ...headers,
      };

  /// Builds the JSON body for a chat completion request.
  Map<String, dynamic> buildRequestBody(AiRequest request) {
    final body = <String, dynamic>{
      'model': request.model ?? defaultModel,
      'messages': [for (final m in request.messages) ..._mapMessage(m)],
      if (request.maxTokens != null)
        legacyMaxTokens ? 'max_tokens' : 'max_completion_tokens':
            request.maxTokens,
      if (request.temperature != null) 'temperature': request.temperature,
      if (request.topP != null) 'top_p': request.topP,
      if (request.stop != null) 'stop': request.stop,
    };

    final tools = request.tools;
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = [for (final t in tools) t.toJson()];
    }

    final schema = request.schema;
    if (schema != null) {
      // Strict mode requires every object to list all of its properties as
      // required; otherwise OpenAI rejects the request. Fall back to
      // best-effort (non-strict) mode for schemas with optional fields.
      final strict = _isStrictCompatible(schema);
      body['response_format'] = {
        'type': 'json_schema',
        'json_schema': {
          'name': 'structured_output',
          'strict': strict,
          'schema': strict ? _toStrictJson(schema) : schema.toJson(),
        },
      };
    }

    return body;
  }

  static bool _isStrictCompatible(AiJsonSchema schema) {
    final properties = schema.properties;
    if (schema.type == 'object') {
      if (properties == null) return false;
      final required = schema.required ?? const <String>[];
      if (!properties.keys.every(required.contains)) return false;
    }
    if (properties != null && !properties.values.every(_isStrictCompatible)) {
      return false;
    }
    final items = schema.items;
    return items == null || _isStrictCompatible(items);
  }

  /// [AiJsonSchema.toJson] plus `additionalProperties: false` on every
  /// object, as strict mode requires.
  static Map<String, dynamic> _toStrictJson(AiJsonSchema schema) {
    final json = schema.toJson();
    final properties = schema.properties;
    if (properties != null) {
      json['properties'] = {
        for (final e in properties.entries) e.key: _toStrictJson(e.value),
      };
    }
    final items = schema.items;
    if (items != null) json['items'] = _toStrictJson(items);
    if (schema.type == 'object') json['additionalProperties'] = false;
    return json;
  }

  /// Maps one [AiMessage] to one or more wire messages (OpenAI requires a
  /// separate `tool` message per tool result).
  List<Map<String, dynamic>> _mapMessage(AiMessage message) {
    final toolResults =
        message.content.whereType<AiToolResultContent>().toList();
    if (toolResults.isNotEmpty) {
      return [
        for (final r in toolResults)
          {
            'role': 'tool',
            'tool_call_id': r.id,
            'content': encodeToolResult(r.result),
          },
      ];
    }

    final role = _mapRole(message.role);

    final toolCalls = message.content.whereType<AiToolCallContent>().toList();
    if (toolCalls.isNotEmpty) {
      final text = message.text;
      return [
        {
          'role': role,
          'content': text.isNotEmpty ? text : null,
          'tool_calls': [
            for (final tc in toolCalls)
              {
                'id': tc.id,
                'type': 'function',
                'function': {
                  'name': tc.name,
                  'arguments': jsonEncode(tc.arguments),
                },
              },
          ],
        },
      ];
    }

    final hasMultimodal = message.content.any(
      (c) => c is AiImageContent || c is AiAudioContent || c is AiFileContent,
    );
    if (hasMultimodal) {
      return [
        {
          'role': role,
          'content': [
            for (final c in message.content)
              if (_mapContent(c) case final part?) part,
          ],
        },
      ];
    }

    return [
      {'role': role, 'content': message.text},
    ];
  }

  Map<String, dynamic>? _mapContent(AiContent content) {
    switch (content) {
      case AiTextContent(:final text):
        return {'type': 'text', 'text': text};
      case AiImageContent(:final mimeType, :final bytes):
        return {
          'type': 'image_url',
          'image_url': {'url': 'data:$mimeType;base64,${base64Encode(bytes)}'},
        };
      case AiAudioContent():
        throw AiUnsupportedCapabilityException(
          'Audio content is not supported by chat completions',
          provider: providerName,
        );
      case AiFileContent():
        throw AiUnsupportedCapabilityException(
          'File content is not supported by chat completions',
          provider: providerName,
        );
      case AiToolCallContent():
      case AiToolResultContent():
        return null; // Handled at the message level.
    }
  }

  String _mapRole(AiMessageRole role) {
    switch (role) {
      case AiMessageRole.system:
        return 'system';
      case AiMessageRole.developer:
        return developerRole ? 'developer' : 'system';
      case AiMessageRole.user:
        return 'user';
      case AiMessageRole.assistant:
        return 'assistant';
      case AiMessageRole.tool:
        return 'tool';
    }
  }

  // ── Response parsing ────────────────────────────────────────────────

  AiResponse _parseResponse(Map<String, dynamic> json) {
    try {
      final choices = json['choices'] as List;
      if (choices.isEmpty) {
        throw AiParsingException(
          'No choices returned',
          provider: providerName,
          rawResponse: jsonEncode(json),
        );
      }

      final choice = choices.first as Map<String, dynamic>;
      final message =
          _parseAssistantMessage(choice['message'] as Map<String, dynamic>);

      return AiResponse(
        message: message,
        finishReason: _parseFinishReason(choice['finish_reason']) ??
            AiFinishReason.unknown,
        usage: _parseUsage(json['usage']) ?? AiUsage.empty,
        raw: json,
      );
    } on AiException {
      rethrow;
    } catch (e) {
      throw AiParsingException(
        'Failed to parse response: $e',
        provider: providerName,
        rawResponse: jsonEncode(json),
      );
    }
  }

  AiMessage _parseAssistantMessage(Map<String, dynamic> json) {
    final parts = <AiContent>[];

    final text = json['content'] as String?;
    if (text != null && text.isNotEmpty) parts.add(AiTextContent(text));

    final toolCalls = json['tool_calls'] as List?;
    if (toolCalls != null) {
      for (final tc in toolCalls.cast<Map<String, dynamic>>()) {
        final function = tc['function'] as Map<String, dynamic>;
        parts.add(AiToolCallContent(
          id: tc['id'] as String,
          name: function['name'] as String,
          arguments: decodeJsonObject(function['arguments'] as String?),
        ));
      }
    }

    return AiMessage(role: AiMessageRole.assistant, content: parts);
  }

  AiStreamChunk? _parseStreamChunk(
    Map<String, dynamic> json,
    Map<int, _ToolCallBuilder> toolCalls,
  ) {
    final usage = _parseUsage(json['usage']);
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      // Final usage-only chunk (stream_options.include_usage).
      return AiStreamChunk(usage: usage, raw: json);
    }

    final choice = choices.first as Map<String, dynamic>;
    final delta = choice['delta'] as Map<String, dynamic>?;
    final content = <AiContent>[];

    final text = delta?['content'] as String?;
    if (text != null && text.isNotEmpty) content.add(AiTextContent(text));

    final toolCallDeltas = delta?['tool_calls'] as List?;
    if (toolCallDeltas != null) {
      for (final tc in toolCallDeltas.cast<Map<String, dynamic>>()) {
        final index = (tc['index'] as int?) ?? toolCalls.length;
        final builder = toolCalls.putIfAbsent(index, _ToolCallBuilder.new);
        final id = tc['id'] as String?;
        if (id != null && id.isNotEmpty) builder.id = id;
        final function = tc['function'] as Map<String, dynamic>?;
        final name = function?['name'] as String?;
        if (name != null && name.isNotEmpty) builder.name = name;
        final args = function?['arguments'] as String?;
        if (args != null) builder.arguments.write(args);
      }
    }

    final finishReason = _parseFinishReason(choice['finish_reason']);
    if (finishReason != null) content.addAll(_drainToolCalls(toolCalls));

    return AiStreamChunk(
      content: content,
      finishReason: finishReason,
      usage: usage,
      raw: json,
    );
  }

  static List<AiToolCallContent> _drainToolCalls(
    Map<int, _ToolCallBuilder> toolCalls,
  ) {
    final keys = toolCalls.keys.toList()..sort();
    final calls = [for (final k in keys) toolCalls[k]!.build()];
    toolCalls.clear();
    return calls;
  }

  static AiUsage? _parseUsage(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return AiUsage(
      inputTokens: json['prompt_tokens'] as int?,
      outputTokens: json['completion_tokens'] as int?,
      totalTokens: json['total_tokens'] as int?,
    );
  }

  static AiFinishReason? _parseFinishReason(Object? reason) {
    switch (reason) {
      case null:
        return null;
      case 'stop':
        return AiFinishReason.stop;
      case 'length':
        return AiFinishReason.length;
      case 'tool_calls':
      case 'function_call':
        return AiFinishReason.toolCalls;
      case 'content_filter':
        return AiFinishReason.contentFilter;
      default:
        return AiFinishReason.unknown;
    }
  }
}

class _ToolCallBuilder {
  String id = '';
  String name = '';
  final StringBuffer arguments = StringBuffer();

  AiToolCallContent build() => AiToolCallContent(
        id: id,
        name: name,
        arguments: decodeJsonObject(arguments.toString()),
      );
}
