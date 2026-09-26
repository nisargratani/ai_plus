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
import '../closeable_provider.dart';

/// An AI provider implementation for the Google Gemini API.
///
/// Supports chat, streaming, tool calling, image and audio input,
/// structured output and embeddings.
///
/// ```dart
/// final provider = AiProvider.gemini(apiKey: 'AIza...');
/// ```
///
/// The API key is sent in the `x-goog-api-key` header (never in the URL).
/// Defaults to the `gemini-flash-latest` model alias and the
/// `gemini-embedding-001` embeddings model.
class GeminiProvider implements AiProvider, CloseableProvider {
  /// Creates a Gemini provider.
  ///
  /// [headers] are sent with every request. A [httpClient] passed in is not
  /// closed by [close]; the caller owns it.
  GeminiProvider({
    required this.apiKey,
    this.baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    Map<String, String> headers = const {},
    AiHttpClient? httpClient,
  })  : _headers = {'x-goog-api-key': apiKey, ...headers},
        _ownsHttpClient = httpClient == null,
        _httpClient = httpClient ?? AiHttpClient();

  /// The model used when a request does not specify one.
  static const defaultModel = 'gemini-flash-latest';

  /// The embeddings model used when none is specified.
  static const defaultEmbeddingModel = 'gemini-embedding-001';

  static const _provider = 'Gemini';

  /// The API key for authentication.
  final String apiKey;

  /// The base URL for the Gemini API.
  final String baseUrl;

  final Map<String, String> _headers;
  final AiHttpClient _httpClient;
  final bool _ownsHttpClient;

  @override
  AiCapabilities get capabilities => const AiCapabilities(
        streaming: true,
        toolCalling: true,
        structuredOutput: true,
        embeddings: true,
        imageInput: true,
        audioInput: true,
      );

  @override
  Future<AiResponse> chat(AiRequest request) async {
    final result = await _httpClient.post(
      _modelUri(request.model ?? defaultModel, 'generateContent'),
      headers: _headers,
      body: _buildRequestBody(request),
      provider: _provider,
    );
    return _parseResponse(result);
  }

  @override
  Stream<AiStreamChunk> stream(AiRequest request) async* {
    final data = _httpClient.postSse(
      _modelUri(
        request.model ?? defaultModel,
        'streamGenerateContent',
        query: const {'alt': 'sse'},
      ),
      headers: _headers,
      body: _buildRequestBody(request),
      provider: _provider,
    );

    await for (final payload in data) {
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(payload) as Map<String, dynamic>;
      } catch (e) {
        throw AiParsingException(
          'Failed to parse Gemini stream chunk: $e',
          provider: _provider,
          rawResponse: payload,
        );
      }
      final error = json['error'];
      if (error != null) {
        throw AiProviderException(
          'Stream error: ${error is Map ? error['message'] : error}',
          provider: _provider,
        );
      }
      _throwIfPromptBlocked(json);
      yield _parseStreamChunk(json);
    }
  }

  @override
  Future<AiEmbeddingResult> embeddings(
    List<String> inputs, {
    String? model,
  }) async {
    if (inputs.isEmpty) return const AiEmbeddingResult(embeddings: []);

    final modelPath = _modelPath(model ?? defaultEmbeddingModel);
    Map<String, dynamic> requestFor(String input) => {
          'model': modelPath,
          'content': {
            'parts': [
              {'text': input},
            ],
          },
        };

    final single = inputs.length == 1;
    final result = await _httpClient.post(
      _modelUri(modelPath, single ? 'embedContent' : 'batchEmbedContents'),
      headers: _headers,
      body: single
          ? requestFor(inputs.first)
          : {'requests': inputs.map(requestFor).toList()},
      provider: _provider,
    );

    try {
      final raw = single
          ? [result['embedding']]
          : result['embeddings'] as List<dynamic>;
      return AiEmbeddingResult(embeddings: [
        for (final e in raw.cast<Map<String, dynamic>>())
          AiEmbedding([
            for (final n in e['values'] as List) (n as num).toDouble(),
          ]),
      ]);
    } catch (e) {
      throw AiParsingException(
        'Failed to parse Gemini embeddings response: $e',
        provider: _provider,
        rawResponse: jsonEncode(result),
      );
    }
  }

  /// Closes the HTTP client created by this provider.
  ///
  /// Called automatically by `AiClient.close`.
  @override
  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }

  // ── Private helpers ──────────────────────────────────────────────────

  /// Accepts `gemini-x`, `models/gemini-x` and `tunedModels/x`.
  static String _modelPath(String model) =>
      model.contains('/') ? model : 'models/$model';

  Uri _modelUri(
    String model,
    String method, {
    Map<String, String>? query,
  }) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse('$base/${_modelPath(model)}:$method');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Map<String, dynamic> _buildRequestBody(AiRequest request) {
    final systemParts = <String>[];
    final contents = <Map<String, dynamic>>[];

    for (final message in request.messages) {
      if (message.role == AiMessageRole.system ||
          message.role == AiMessageRole.developer) {
        systemParts.add(message.text);
      } else {
        contents.add(_mapMessage(message));
      }
    }

    final body = <String, dynamic>{'contents': contents};

    if (systemParts.isNotEmpty) {
      body['systemInstruction'] = {
        'parts': [
          {'text': systemParts.join('\n')},
        ],
      };
    }

    final generationConfig = <String, dynamic>{
      if (request.maxTokens != null) 'maxOutputTokens': request.maxTokens,
      if (request.temperature != null) 'temperature': request.temperature,
      if (request.topP != null) 'topP': request.topP,
      if (request.stop != null) 'stopSequences': request.stop,
    };
    final schema = request.schema;
    if (schema != null) {
      generationConfig['responseMimeType'] = 'application/json';
      generationConfig['responseSchema'] = schema.toJson();
    }
    if (generationConfig.isNotEmpty) {
      body['generationConfig'] = generationConfig;
    }

    final tools = request.tools;
    if (tools != null && tools.isNotEmpty) {
      body['tools'] = [
        {
          'functionDeclarations': [
            for (final t in tools)
              {
                'name': t.name,
                'description': t.description,
                'parameters': t.parameters.toJson(),
              },
          ],
        },
      ];
    }

    return body;
  }

  Map<String, dynamic> _mapMessage(AiMessage message) {
    final parts = <Map<String, dynamic>>[];

    for (final content in message.content) {
      switch (content) {
        case AiTextContent(:final text):
          parts.add({'text': text});
        case AiImageContent(:final mimeType, :final bytes):
        case AiAudioContent(:final mimeType, :final bytes):
          parts.add({
            'inlineData': {'mimeType': mimeType, 'data': base64Encode(bytes)},
          });
        case AiFileContent():
          throw const AiUnsupportedCapabilityException(
            'Generic file content is not supported by Gemini inline',
            provider: _provider,
          );
        case AiToolCallContent(:final id, :final name, :final arguments):
          final signature = content.metadata['thoughtSignature'];
          parts.add({
            'functionCall': {
              if (id != name) 'id': id,
              'name': name,
              'args': arguments,
            },
            // Gemini requires thought signatures to be echoed back verbatim.
            if (signature != null) 'thoughtSignature': signature,
          });
        case AiToolResultContent(:final id, :final name, :final result):
          parts.add({
            'functionResponse': {
              if (id != name) 'id': id,
              'name': name,
              'response':
                  result is Map<String, dynamic> ? result : {'result': result},
            },
          });
      }
    }

    if (parts.isEmpty) parts.add({'text': ''});

    return {
      // Gemini only accepts `user` and `model`; function responses are sent
      // as `user` turns.
      'role': message.role == AiMessageRole.assistant ? 'model' : 'user',
      'parts': parts,
    };
  }

  /// Gemini returns no candidates (HTTP 200) when the prompt itself is
  /// blocked; surface that as a content-filter error, not a parsing error.
  void _throwIfPromptBlocked(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List?;
    if (candidates != null && candidates.isNotEmpty) return;
    final feedback = json['promptFeedback'] as Map<String, dynamic>?;
    final blockReason = feedback?['blockReason'];
    if (blockReason != null) {
      throw AiContentFilterException(
        'Prompt blocked by Gemini: $blockReason',
        provider: _provider,
      );
    }
  }

  AiResponse _parseResponse(Map<String, dynamic> json) {
    _throwIfPromptBlocked(json);
    try {
      final candidates = json['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw AiParsingException(
          'No candidates returned by Gemini',
          provider: _provider,
          rawResponse: jsonEncode(json),
        );
      }

      final candidate = candidates.first as Map<String, dynamic>;
      final content = _parseParts(candidate);

      return AiResponse(
        message: AiMessage(
          role: AiMessageRole.assistant,
          content: content.isEmpty ? [const AiTextContent('')] : content,
        ),
        finishReason: _parseFinishReason(candidate['finishReason'], content) ??
            AiFinishReason.unknown,
        usage: _parseUsage(json['usageMetadata']) ?? AiUsage.empty,
        raw: json,
      );
    } on AiException {
      rethrow;
    } catch (e) {
      throw AiParsingException(
        'Failed to parse Gemini response: $e',
        provider: _provider,
        rawResponse: jsonEncode(json),
      );
    }
  }

  List<AiContent> _parseParts(Map<String, dynamic> candidate) {
    final contentObj = candidate['content'] as Map<String, dynamic>?;
    final parts = (contentObj?['parts'] as List?) ?? const [];
    final result = <AiContent>[];

    for (final part in parts.cast<Map<String, dynamic>>()) {
      // Thought summaries are not part of the answer.
      if (part['thought'] == true) continue;

      final text = part['text'] as String?;
      if (text != null && text.isNotEmpty) result.add(AiTextContent(text));

      final fc = part['functionCall'] as Map<String, dynamic>?;
      if (fc != null) {
        final name = fc['name'] as String;
        final signature = part['thoughtSignature'];
        result.add(AiToolCallContent(
          // Older models do not return call ids; fall back to the name.
          id: (fc['id'] as String?) ?? name,
          name: name,
          arguments: (fc['args'] as Map<String, dynamic>?) ?? {},
          metadata: signature != null ? {'thoughtSignature': signature} : {},
        ));
      }
    }
    return result;
  }

  AiStreamChunk _parseStreamChunk(Map<String, dynamic> json) {
    final candidates = json['candidates'] as List?;
    final usage = _parseUsage(json['usageMetadata']);
    if (candidates == null || candidates.isEmpty) {
      return AiStreamChunk(usage: usage, raw: json);
    }

    final candidate = candidates.first as Map<String, dynamic>;
    final content = _parseParts(candidate);
    return AiStreamChunk(
      content: content,
      finishReason: _parseFinishReason(candidate['finishReason'], content),
      usage: usage,
      raw: json,
    );
  }

  static AiUsage? _parseUsage(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return AiUsage(
      inputTokens: json['promptTokenCount'] as int?,
      outputTokens: json['candidatesTokenCount'] as int?,
      totalTokens: json['totalTokenCount'] as int?,
    );
  }

  static AiFinishReason? _parseFinishReason(
    Object? reason,
    List<AiContent> content,
  ) {
    if (reason == null) return null;
    // Gemini reports `STOP` even when the turn ends with function calls.
    if (content.any((c) => c is AiToolCallContent)) {
      return AiFinishReason.toolCalls;
    }
    switch (reason) {
      case 'STOP':
        return AiFinishReason.stop;
      case 'MAX_TOKENS':
        return AiFinishReason.length;
      case 'SAFETY':
      case 'RECITATION':
      case 'BLOCKLIST':
      case 'PROHIBITED_CONTENT':
      case 'SPII':
      case 'IMAGE_SAFETY':
        return AiFinishReason.contentFilter;
      default:
        return AiFinishReason.unknown;
    }
  }
}
