import 'package:test/test.dart';
import 'package:ai_plus/ai_plus.dart';

void main() {
  group('ToolExecutor', () {
    late ToolExecutor executor;
    late AiTool weatherTool;
    late AiTool calcTool;

    setUp(() {
      weatherTool = AiTool(
        name: 'get_weather',
        description: 'Gets weather',
        parameters: AiJsonSchema.object(
          properties: {'city': AiJsonSchema.string()},
          required: ['city'],
        ),
        execute: (args) async => {'temp': 72, 'condition': 'sunny'},
      );

      calcTool = AiTool(
        name: 'calculate',
        description: 'Calculates',
        parameters: AiJsonSchema.object(
          properties: {'expression': AiJsonSchema.string()},
        ),
        execute: (args) async => 42,
      );

      executor = ToolExecutor([weatherTool, calcTool]);
    });

    test('executes registered tool successfully', () async {
      const call = AiToolCallContent(
        id: 'call_1',
        name: 'get_weather',
        arguments: {'city': 'London'},
      );

      final result = await executor.execute(call);
      expect(result.id, 'call_1');
      expect(result.name, 'get_weather');
      expect(result.isError, isFalse);
      expect((result.result as Map)['condition'], 'sunny');
    });

    test('returns error for unknown tool', () async {
      const call = AiToolCallContent(
        id: 'call_1',
        name: 'unknown_tool',
        arguments: {},
      );

      final result = await executor.execute(call);
      expect(result.isError, isTrue);
      expect(result.result.toString(), contains('not found'));
    });

    test('handles tool execution errors gracefully', () async {
      final failingTool = AiTool(
        name: 'failing',
        description: 'Always fails',
        parameters: AiJsonSchema.object(properties: {}),
        execute: (args) async => throw Exception('Tool crashed!'),
      );

      final failingExecutor = ToolExecutor([failingTool]);
      const call = AiToolCallContent(
        id: 'call_1',
        name: 'failing',
        arguments: {},
      );

      final result = await failingExecutor.execute(call);
      expect(result.isError, isTrue);
      expect(result.result.toString(), contains('Tool crashed'));
    });

    test('executes multiple tools concurrently', () async {
      const calls = [
        AiToolCallContent(
            id: 'c1', name: 'get_weather', arguments: {'city': 'NYC'}),
        AiToolCallContent(
            id: 'c2', name: 'calculate', arguments: {'expression': '1+1'}),
      ];

      final results = await executor.executeAll(calls);
      expect(results.length, 2);
      expect(results[0].id, 'c1');
      expect(results[1].id, 'c2');
      expect(results[0].isError, isFalse);
      expect(results[1].isError, isFalse);
    });

    test('mix of found and not-found tools', () async {
      const calls = [
        AiToolCallContent(id: 'c1', name: 'get_weather', arguments: {}),
        AiToolCallContent(id: 'c2', name: 'nonexistent', arguments: {}),
      ];

      final results = await executor.executeAll(calls);
      expect(results[0].isError, isFalse);
      expect(results[1].isError, isTrue);
    });
  });

  group('AiTool', () {
    test('toJson produces valid schema', () {
      final tool = AiTool(
        name: 'get_weather',
        description: 'Gets weather',
        parameters: AiJsonSchema.object(
          properties: {
            'city': AiJsonSchema.string(description: 'City name'),
          },
          required: ['city'],
        ),
        execute: (args) async => null,
      );

      final json = tool.toJson();
      expect(json['type'], 'function');
      expect(json['function']['name'], 'get_weather');
      expect(json['function']['description'], 'Gets weather');
      expect(json['function']['parameters']['type'], 'object');
      expect(json['function']['parameters']['required'], ['city']);
    });
  });
}
