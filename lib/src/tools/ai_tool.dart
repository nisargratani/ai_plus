import '../structured_output/schema.dart';
import 'tool_executor.dart';

/// Represents a tool (function) that the AI model can call.
class AiTool {
  /// The name of the tool (must follow provider naming constraints, usually alphanumeric and underscores).
  final String name;

  /// A description of what the tool does.
  final String description;

  /// The JSON Schema defining the parameters this tool accepts.
  final AiJsonSchema parameters;

  /// The callback to execute when the AI model requests this tool.
  ///
  /// The returned value is sent back to the model: strings verbatim, other
  /// values JSON-encoded. Exceptions are caught by [ToolExecutor] and
  /// reported to the model as error results.
  final Future<dynamic> Function(Map<String, dynamic> arguments) execute;

  /// Creates a tool definition.
  const AiTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });

  /// Converts the tool definition to the OpenAI function-tool JSON format.
  Map<String, dynamic> toJson() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': parameters.toJson(),
      }
    };
  }
}
