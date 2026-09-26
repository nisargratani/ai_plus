import 'dart:async';
import 'dart:convert';

import 'package:ai_plus/ai_plus.dart';
import 'package:http/http.dart' as http;

/// A scriptable [AiProvider] for testing client-level behaviour.
class FakeProvider implements AiProvider {
  FakeProvider({
    this.capabilities = const AiCapabilities(
      streaming: true,
      toolCalling: true,
      structuredOutput: true,
      embeddings: true,
    ),
    FutureOr<AiResponse> Function(AiRequest request)? onChat,
    Stream<AiStreamChunk> Function(AiRequest request)? onStream,
  })  : _onChat = onChat,
        _onStream = onStream;

  @override
  final AiCapabilities capabilities;

  final FutureOr<AiResponse> Function(AiRequest request)? _onChat;
  final Stream<AiStreamChunk> Function(AiRequest request)? _onStream;

  /// Every request received, in order.
  final List<AiRequest> requests = [];

  @override
  Future<AiResponse> chat(AiRequest request) async {
    requests.add(request);
    final onChat = _onChat;
    if (onChat == null) return textResponse('ok');
    return onChat(request);
  }

  @override
  Stream<AiStreamChunk> stream(AiRequest request) {
    requests.add(request);
    final onStream = _onStream;
    if (onStream == null) return const Stream.empty();
    return onStream(request);
  }

  @override
  Future<AiEmbeddingResult> embeddings(
    List<String> inputs, {
    String? model,
  }) async {
    // A deterministic 2-d embedding based on the input length.
    return AiEmbeddingResult(embeddings: [
      for (final input in inputs) AiEmbedding([input.length.toDouble(), 1.0]),
    ]);
  }
}

AiResponse textResponse(String text) => AiResponse(
      message: AiMessage.assistant(text),
      finishReason: AiFinishReason.stop,
    );

AiRequest userRequest(String text) =>
    AiRequest(messages: [AiMessage.user(text)]);

/// Builds a streamed SSE HTTP response from JSON [events].
http.StreamedResponse sseResponse(
  List<Object> events, {
  bool done = false,
}) {
  final body = StringBuffer();
  for (final e in events) {
    body.write('data: ${e is String ? e : jsonEncode(e)}\n\n');
  }
  if (done) body.write('data: [DONE]\n\n');
  return http.StreamedResponse(
    Stream.value(utf8.encode(body.toString())),
    200,
    headers: {'content-type': 'text/event-stream'},
  );
}

/// An [http.Client] that records whether it was closed.
class TrackingClient extends http.BaseClient {
  TrackingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);

  @override
  void close() => closed = true;
}
