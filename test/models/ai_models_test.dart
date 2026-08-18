import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:ai_plus/ai_plus.dart';

void main() {
  group('AiMessage', () {
    test('creates user message', () {
      final msg = AiMessage.user('Hello');
      expect(msg.role, AiMessageRole.user);
      expect(msg.text, 'Hello');
    });

    test('creates system message', () {
      final msg = AiMessage.system('Be helpful');
      expect(msg.role, AiMessageRole.system);
      expect(msg.text, 'Be helpful');
    });

    test('creates assistant message', () {
      final msg = AiMessage.assistant('Hi there');
      expect(msg.role, AiMessageRole.assistant);
      expect(msg.text, 'Hi there');
    });

    test('creates developer message', () {
      final msg = AiMessage.developer('Internal note');
      expect(msg.role, AiMessageRole.developer);
      expect(msg.text, 'Internal note');
    });

    test('creates tool message', () {
      final msg = AiMessage.tool('result data');
      expect(msg.role, AiMessageRole.tool);
      expect(msg.text, 'result data');
    });

    test('creates multimodal message', () {
      final msg = AiMessage(
        role: AiMessageRole.user,
        content: [
          const AiTextContent('What is this?'),
          AiImageContent(
              mimeType: 'image/png', bytes: Uint8List.fromList([1, 2, 3])),
        ],
      );
      expect(msg.content.length, 2);
      expect(msg.content.first, isA<AiTextContent>());
      expect(msg.content.last, isA<AiImageContent>());
    });

    test('text getter concatenates multiple text parts', () {
      const msg = AiMessage(
        role: AiMessageRole.assistant,
        content: [
          AiTextContent('Hello'),
          AiTextContent('World'),
        ],
      );
      expect(msg.text, 'Hello\nWorld');
    });

    test('text getter ignores non-text content', () {
      final msg = AiMessage(
        role: AiMessageRole.assistant,
        content: [
          const AiTextContent('Hello'),
          AiImageContent(mimeType: 'image/png', bytes: Uint8List.fromList([1])),
        ],
      );
      expect(msg.text, 'Hello');
    });
  });

  group('AiContent', () {
    test('AiTextContent stores text', () {
      const content = AiTextContent('hello');
      expect(content.text, 'hello');
    });

    test('AiImageContent stores bytes and mimeType', () {
      final content = AiImageContent(
          mimeType: 'image/png', bytes: Uint8List.fromList([1, 2]));
      expect(content.mimeType, 'image/png');
      expect(content.bytes.length, 2);
    });

    test('AiAudioContent stores bytes and mimeType', () {
      final content = AiAudioContent(
          mimeType: 'audio/mp3', bytes: Uint8List.fromList([3, 4]));
      expect(content.mimeType, 'audio/mp3');
      expect(content.bytes.length, 2);
    });

    test('AiFileContent stores bytes and mimeType', () {
      final content = AiFileContent(
          mimeType: 'application/pdf', bytes: Uint8List.fromList([5]));
      expect(content.mimeType, 'application/pdf');
      expect(content.bytes.length, 1);
    });

    test('AiToolCallContent stores tool call data', () {
      const content = AiToolCallContent(
        id: 'call_1',
        name: 'get_weather',
        arguments: {'city': 'London'},
      );
      expect(content.id, 'call_1');
      expect(content.name, 'get_weather');
      expect(content.arguments['city'], 'London');
    });

    test('AiToolResultContent stores result data', () {
      const content = AiToolResultContent(
        id: 'call_1',
        name: 'get_weather',
        result: 'sunny',
      );
      expect(content.id, 'call_1');
      expect(content.name, 'get_weather');
      expect(content.result, 'sunny');
      expect(content.isError, isFalse);
    });

    test('AiToolResultContent with error', () {
      const content = AiToolResultContent(
        id: 'call_1',
        name: 'get_weather',
        result: 'Error: API down',
        isError: true,
      );
      expect(content.isError, isTrue);
    });

    test('AiContent is sealed', () {
      // Verify we can pattern match all subtypes
      const AiContent content = AiTextContent('test');
      final result = switch (content) {
        AiTextContent() => 'text',
        AiImageContent() => 'image',
        AiAudioContent() => 'audio',
        AiFileContent() => 'file',
        AiToolCallContent() => 'tool_call',
        AiToolResultContent() => 'tool_result',
      };
      expect(result, 'text');
    });
  });

  group('AiUsage', () {
    test('creates with all fields', () {
      const usage = AiUsage(
        inputTokens: 10,
        outputTokens: 20,
        totalTokens: 30,
      );
      expect(usage.inputTokens, 10);
      expect(usage.outputTokens, 20);
      expect(usage.totalTokens, 30);
    });

    test('empty usage has null fields', () {
      expect(AiUsage.empty.inputTokens, isNull);
      expect(AiUsage.empty.outputTokens, isNull);
      expect(AiUsage.empty.totalTokens, isNull);
    });
  });

  group('AiFinishReason', () {
    test('has all expected values', () {
      expect(AiFinishReason.values, contains(AiFinishReason.stop));
      expect(AiFinishReason.values, contains(AiFinishReason.length));
      expect(AiFinishReason.values, contains(AiFinishReason.toolCalls));
      expect(AiFinishReason.values, contains(AiFinishReason.contentFilter));
      expect(AiFinishReason.values, contains(AiFinishReason.cancelled));
      expect(AiFinishReason.values, contains(AiFinishReason.unknown));
    });
  });

  group('AiModel', () {
    test('creates with name', () {
      const model = AiModel(name: 'gpt-4o');
      expect(model.name, 'gpt-4o');
      expect(model.provider, isNull);
    });

    test('creates with provider', () {
      const model = AiModel(name: 'gpt-4o', provider: 'openai');
      expect(model.provider, 'openai');
    });

    test('equality works', () {
      const a = AiModel(name: 'gpt-4o', provider: 'openai');
      const b = AiModel(name: 'gpt-4o', provider: 'openai');
      const c = AiModel(name: 'gpt-4o-mini', provider: 'openai');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('toString returns displayName when available', () {
      const model = AiModel(name: 'gpt-4o', displayName: 'GPT-4o');
      expect(model.toString(), 'GPT-4o');
    });

    test('toString returns name when no displayName', () {
      const model = AiModel(name: 'gpt-4o');
      expect(model.toString(), 'gpt-4o');
    });
  });
}
