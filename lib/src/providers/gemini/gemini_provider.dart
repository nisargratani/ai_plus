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

/// An AI provider implementation for Google Gemini.
///
/// Supports chat, streaming, tool calling, multimodal input, and embeddings.
///
/// ```dart
/// final provider = AiProvider.gemini(apiKey: 'AIza...');
/// ```
class GeminiProvider implements AiProvider {
  /// The API key for authentication.
  final String apiKey;

  /// The base URL for the Gemini API.
  final String baseUrl;

  final AiHttpClient _httpClient;

  /// Creates a Gemini provider.
  ///
  /// An optional [httpClient] can be provided for testing.
  GeminiProvider({
    required this.apiKey,
    this.baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    AiHttpClient? httpClient,
  }) : _httpClient = httpClient ?? AiHttpClient();

  @override
  AiCapabilities get capabilities => const AiCapabilities(
        streaming: true,
        toolCalling: true,
        structuredOutput: true,
        embeddings: true,
        imageInput: true,
        audioInput: true,
        fileInput: false,
      );

  @override
  Future<AiResponse> chat(AiRequest request) async {
    final model = request.model ?? 'gemini-2.0-flash';
    final url = Uri.parse('$baseUrl/models/$model:generateContent?key=$apiKey');
    final body = _buildRequestBody(request);

    final result = await _httpClient.post(url, body: body);
    return _parseResponse(result);
  }

  @override
  Stream<AiStreamChunk> stream(AiRequest request) async* {
    final model = request.model ?? 'gemini-2.0-flash';
    final url = Uri.parse(
        '$baseUrl/models/$model:streamGenerateContent?key=$apiKey&alt=sse');
    final body = _buildRequestBody(request);

    final rawStream = _httpClient.postStream(url, body: body);

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
          yield _parseStreamChunk(json);
        } catch (e) {
          if (e is AiException) rethrow;
          throw AiParsingException('Failed to parse Gemini stream chunk: $e',
              provider: 'Gemini', rawResponse: data);
        }
      }
    }
  }

  @override
  Future<AiEmbeddingResult> embeddings(List<String> inputs,
      {String? model}) async {
    final defaultModel = model ?? 'text-embedding-004';

    if (inputs.length == 1) {
      final url =
          Uri.parse('$baseUrl/models/$defaultModel:embedContent?key=$apiKey');
      final body = <String, dynamic>{
        'model': 'models/$defaultModel',
        'content': {
          'parts': [
            {'text': inputs.first}
          ]
        }
      };

      final result = await _httpClient.post(url, body: body);

      try {
        final embeddingObj = result['embedding'] as Map<String, dynamic>;
        final values = (embeddingObj['values'] as List)
            .cast<num>()
            .map((n) => n.toDouble())
            .toList();
        return AiEmbeddingResult(embeddings: [AiEmbedding(values)]);
      } catch (e) {
        if (e is AiException) rethrow;
        throw AiParsingException(
            'Failed to parse Gemini embedding response: $e',
            provider: 'Gemini',
            rawResponse: jsonEncode(result));
      }
    } else {
      final url = Uri.parse(
          '$baseUrl/models/$defaultModel:batchEmbedContents?key=$apiKey');
      final requests = inputs
          .map((input) => <String, dynamic>{
                'model': 'models/$defaultModel',
                'content': {
                  'parts': [
                    {'text': input}
                  ]
                }
              })
          .toList();

      final result = await _httpClient.post(url, body: {'requests': requests});

      try {
        final embeddingsList = result['embeddings'] as List;
        final embeddingsResult = embeddingsList.map((e) {
          final values = (e['values'] as List)
              .cast<num>()
              .map((n) => n.toDouble())
              .toList();
          return AiEmbedding(values);
        }).toList();
        return AiEmbeddingResult(embeddings: embeddingsResult);
      } catch (e) {
        if (e is AiException) rethrow;
        throw AiParsingException(
            'Failed to parse Gemini batch embedding response: $e',
            provider: 'Gemini',
            rawResponse: jsonEncode(result));
      }
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────

  Map<String, dynamic> _buildRequestBody(AiRequest request) {
    // Separate system messages from conversation messages
    final systemParts = <String>[];
    final contentMessages = <Map<String, dynamic>>[];

    for (final message in request.messages) {
      if (message.role == AiMessageRole.system ||
          message.role == AiMessageRole.developer) {
        systemParts.add(message.text);
      } else {
        contentMessages.add(_mapMessage(message));
      }
    }

    final body = <String, dynamic>{
      'contents': contentMessages,
    };

    if (systemParts.isNotEmpty) {
      body['systemInstruction'] = {
        'parts': [
          {'text': systemParts.join('\n')}
        ]
      };
    }

    // Generation config
    final generationConfig = <String, dynamic>{};
    if (request.maxTokens != null) {
      generationConfig['maxOutputTokens'] = request.maxTokens;
    }
    if (request.temperature != null) {
      generationConfig['temperature'] = request.temperature;
    }
    if (request.topP != null) {
      generationConfig['topP'] = request.topP;
    }
    if (request.stop != null) {
      generationConfig['stopSequences'] = request.stop;
    }

    // Structured output via responseSchema
    if (request.schema != null) {
      generationConfig['responseMimeType'] = 'application/json';
      generationConfig['responseSchema'] = request.schema!.toJson();
    }

    if (generationConfig.isNotEmpty) {
      body['generationConfig'] = generationConfig;
    }

    // Tool definitions
    if (request.tools != null && request.tools!.isNotEmpty) {
      body['tools'] = [
        {
          'functionDeclarations': request.tools!
              .map((t) => {
                    'name': t.name,
                    'description': t.description,
                    'parameters': t.parameters.toJson(),
                  })
              .toList(),
        }
      ];
    }

    return body;
  }

  Map<String, dynamic> _mapMessage(AiMessage message) {
    final role = _mapRole(message.role);
    final parts = <Map<String, dynamic>>[];

    for (final content in message.content) {
      switch (content) {
        case AiTextContent(:final text):
          parts.add({'text': text});
        case AiImageContent(:final mimeType, :final bytes):
          parts.add({
            'inlineData': {
              'mimeType': mimeType,
              'data': base64Encode(bytes),
            }
          });
        case AiAudioContent(:final mimeType, :final bytes):
          parts.add({
            'inlineData': {
              'mimeType': mimeType,
              'data': base64Encode(bytes),
            }
          });
        case AiFileContent():
          throw const AiUnsupportedCapabilityException(
            'Generic file content is not supported by Gemini inline',
            provider: 'Gemini',
          );
        case AiToolCallContent(:final name, :final arguments):
          parts.add({
            'functionCall': {
              'name': name,
              'args': arguments,
            }
          });
        case AiToolResultContent(:final name, :final result):
          parts.add({
            'functionResponse': {
              'name': name,
              'response':
                  result is Map<String, dynamic> ? result : {'result': result},
            }
          });
      }
    }

    if (parts.isEmpty) {
      parts.add({'text': ''});
    }

    return {
      'role': role,
      'parts': parts,
    };
  }

  String _mapRole(AiMessageRole role) {
    switch (role) {
      case AiMessageRole.user:
        return 'user';
      case AiMessageRole.assistant:
        return 'model';
      case AiMessageRole.tool:
        return 'function';
      case AiMessageRole.system:
      case AiMessageRole.developer:
        return 'user'; // Handled separately in _buildRequestBody
    }
  }

  AiResponse _parseResponse(Map<String, dynamic> json) {
    try {
      final candidates = json['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw const AiParsingException('No candidates returned by Gemini',
            provider: 'Gemini');
      }

      final candidate = candidates.first as Map<String, dynamic>;
      final message = _parseAssistantContent(candidate);

      final usageJson = json['usageMetadata'] as Map<String, dynamic>?;
      final usage = usageJson != null
          ? AiUsage(
              inputTokens: usageJson['promptTokenCount'] as int?,
              outputTokens: usageJson['candidatesTokenCount'] as int?,
              totalTokens: usageJson['totalTokenCount'] as int?,
            )
          : AiUsage.empty;

      return AiResponse(
        message: message,
        finishReason: _parseFinishReason(candidate['finishReason']),
        usage: usage,
        raw: json,
      );
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiParsingException('Failed to parse Gemini response: $e',
          provider: 'Gemini', rawResponse: jsonEncode(json));
    }
  }

  AiMessage _parseAssistantContent(Map<String, dynamic> candidate) {
    final contentObj = candidate['content'] as Map<String, dynamic>?;
    final parts = contentObj?['parts'] as List? ?? [];
    final contentParts = <AiContent>[];

    for (final part in parts) {
      final partMap = part as Map<String, dynamic>;

      if (partMap.containsKey('text')) {
        final text = partMap['text'] as String? ?? '';
        if (text.isNotEmpty) {
          contentParts.add(AiTextContent(text));
        }
      }

      if (partMap.containsKey('functionCall')) {
        final fc = partMap['functionCall'] as Map<String, dynamic>;
        contentParts.add(AiToolCallContent(
          id: fc['name'] as String, // Gemini doesn't use separate IDs
          name: fc['name'] as String,
          arguments: (fc['args'] as Map<String, dynamic>?) ?? {},
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
    final candidates = json['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      return AiStreamChunk(raw: json);
    }

    final candidate = candidates.first;
    final contentObj = candidate['content'] as Map<String, dynamic>?;
    final parts = contentObj?['parts'] as List? ?? [];
    final contentParts = <AiContent>[];

    for (final part in parts) {
      final partMap = part as Map<String, dynamic>;
      if (partMap.containsKey('text')) {
        contentParts.add(AiTextContent(partMap['text'] as String? ?? ''));
      }
      if (partMap.containsKey('functionCall')) {
        final fc = partMap['functionCall'] as Map<String, dynamic>;
        contentParts.add(AiToolCallContent(
          id: fc['name'] as String,
          name: fc['name'] as String,
          arguments: (fc['args'] as Map<String, dynamic>?) ?? {},
        ));
      }
    }

    final usageJson = json['usageMetadata'] as Map<String, dynamic>?;

    return AiStreamChunk(
      content: contentParts,
      finishReason: _parseFinishReason(candidate['finishReason']),
      usage: usageJson != null
          ? AiUsage(
              inputTokens: usageJson['promptTokenCount'] as int?,
              outputTokens: usageJson['candidatesTokenCount'] as int?,
              totalTokens: usageJson['totalTokenCount'] as int?,
            )
          : null,
      raw: json,
    );
  }

  AiFinishReason _parseFinishReason(dynamic reason) {
    switch (reason) {
      case 'STOP':
        return AiFinishReason.stop;
      case 'MAX_TOKENS':
        return AiFinishReason.length;
      case 'SAFETY':
        return AiFinishReason.contentFilter;
      case 'RECITATION':
        return AiFinishReason.unknown;
      default:
        return AiFinishReason.unknown;
    }
  }
}
