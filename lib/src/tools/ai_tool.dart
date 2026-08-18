import '../structured_output/schema.dart';

/// Represents a tool (function) that the AI model can call.
class AiTool {
  /// The name of the tool (must follow provider naming constraints, usually alphanumeric and underscores).
  final String name;

  /// A description of what the tool does.
  final String description;

  /// The JSON Schema defining the parameters this tool accepts.
  final AiJsonSchema parameters;

  /// The callback to execute when the AI model requests this tool.
  final Future<dynamic> Function(Map<String, dynamic> arguments) execute;

  const AiTool({
    required this.name,
    required this.description,
    required this.parameters,
    required this.execute,
  });

  /// Converts the tool definition to a JSON map representing the schema.
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
