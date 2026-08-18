import 'ai_tool.dart';
import '../models/ai_content.dart';

/// Helper class to safely execute tools requested by the AI model.
///
/// The executor matches tool call names against registered tools and
/// invokes them with the provided arguments, catching any errors.
///
/// ```dart
/// final executor = ToolExecutor([weatherTool, calculatorTool]);
/// final result = await executor.execute(toolCallContent);
/// ```
class ToolExecutor {
  final Map<String, AiTool> _tools;

  /// Creates a tool executor with the given list of tools.
  ToolExecutor(List<AiTool> tools) : _tools = {for (var t in tools) t.name: t};

  /// Executes a tool call requested by the AI model.
  ///
  /// Returns an [AiToolResultContent] containing the execution result or error.
  /// If the tool is not found, returns a result with [isError] set to true.
  Future<AiToolResultContent> execute(AiToolCallContent call) async {
    final tool = _tools[call.name];

    if (tool == null) {
      return AiToolResultContent(
        id: call.id,
        name: call.name,
        result: 'Error: Tool "${call.name}" not found.',
        isError: true,
      );
    }

    try {
      final result = await tool.execute(call.arguments);
      return AiToolResultContent(
        id: call.id,
        name: call.name,
        result: result,
      );
    } catch (e) {
      return AiToolResultContent(
        id: call.id,
        name: call.name,
        result: 'Error executing tool: $e',
        isError: true,
      );
    }
  }

  /// Executes multiple tool calls concurrently.
  Future<List<AiToolResultContent>> executeAll(
      List<AiToolCallContent> calls) async {
    return Future.wait(calls.map(execute));
  }
}
