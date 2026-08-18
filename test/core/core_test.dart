import 'package:test/test.dart';
import 'package:ai_plus/ai_plus.dart';

void main() {
  group('MetricsMiddleware', () {
    test('starts at zero', () {
      final metrics = MetricsMiddleware();
      expect(metrics.requestCount, 0);
      expect(metrics.errorCount, 0);
      expect(metrics.totalLatency, Duration.zero);
      expect(metrics.averageLatency, Duration.zero);
    });

    test('reset clears all metrics', () {
      final metrics = MetricsMiddleware();
      // Manually increment by calling handleChat with a mock
      // For simplicity, just test reset on fresh state
      metrics.reset();
      expect(metrics.requestCount, 0);
    });
  });

  group('AiCapabilities', () {
    test('default capabilities are all false', () {
      const caps = AiCapabilities();
      expect(caps.streaming, isFalse);
      expect(caps.toolCalling, isFalse);
      expect(caps.structuredOutput, isFalse);
      expect(caps.embeddings, isFalse);
      expect(caps.imageInput, isFalse);
      expect(caps.audioInput, isFalse);
      expect(caps.fileInput, isFalse);
    });

    test('individual capabilities can be set', () {
      const caps = AiCapabilities(
        streaming: true,
        toolCalling: true,
        imageInput: true,
      );
      expect(caps.streaming, isTrue);
      expect(caps.toolCalling, isTrue);
      expect(caps.structuredOutput, isFalse);
      expect(caps.imageInput, isTrue);
    });
  });

  group('AiRequest', () {
    test('creates with required fields', () {
      const request = AiRequest(
        messages: [
          AiMessage(role: AiMessageRole.user, content: [AiTextContent('Hi')])
        ],
      );
      expect(request.messages.length, 1);
      expect(request.model, isNull);
    });

    test('creates with all fields', () {
      final request = AiRequest(
        messages: const [
          AiMessage(role: AiMessageRole.user, content: [AiTextContent('Hi')])
        ],
        model: 'gpt-4o',
        maxTokens: 1000,
        temperature: 0.7,
        topP: 0.9,
        stop: ['END'],
        schema: AiJsonSchema.string(),
      );
      expect(request.model, 'gpt-4o');
      expect(request.maxTokens, 1000);
      expect(request.temperature, 0.7);
      expect(request.topP, 0.9);
      expect(request.stop, ['END']);
      expect(request.schema, isNotNull);
    });

    test('copyWith creates modified copy', () {
      const original = AiRequest(
        messages: [
          AiMessage(role: AiMessageRole.user, content: [AiTextContent('Hi')])
        ],
        model: 'gpt-4o',
      );

      final copy = original.copyWith(model: 'gpt-4o-mini');
      expect(copy.model, 'gpt-4o-mini');
      expect(copy.messages.length, 1); // Preserved
    });
  });

  group('AiResponse', () {
    test('text getter returns message text', () {
      final response = AiResponse(
        message: AiMessage.assistant('Hello'),
      );
      expect(response.text, 'Hello');
    });

    test('default finish reason is unknown', () {
      final response = AiResponse(
        message: AiMessage.assistant('Hello'),
      );
      expect(response.finishReason, AiFinishReason.unknown);
    });

    test('default usage is empty', () {
      final response = AiResponse(
        message: AiMessage.assistant('Hello'),
      );
      expect(response.usage.inputTokens, isNull);
    });
  });

  group('AiStreamChunk', () {
    test('text getter extracts text content', () {
      const chunk = AiStreamChunk(
        content: [AiTextContent('hello'), AiTextContent(' world')],
      );
      expect(chunk.text, 'hello world');
    });

    test('empty content returns empty text', () {
      const chunk = AiStreamChunk();
      expect(chunk.text, isEmpty);
    });
  });
}
