// ignore_for_file: prefer_initializing_formals

import '../core/ai_client.dart';
import '../errors/ai_exception.dart';
import '../models/ai_content.dart';
import '../models/ai_message.dart';
import '../tools/ai_tool.dart';
import '../tools/tool_executor.dart';

/// A high-level autonomous agent capable of using tools to achieve a goal.
///
/// The agent iterates between the AI model and tool execution until the
/// model produces a final text response or the [maxIterations] limit is hit.
///
/// ```dart
/// final agent = AiAgent(
///   client: ai,
///   instructions: 'You are a helpful math assistant.',
///   tools: [calculatorTool],
/// );
///
/// final result = await agent.run('What is 20% of 500?');
/// print(result);
/// ```
class AiAgent {
  final AiClient _client;
  final ToolExecutor _executor;
  final String? _model;
  final List<AiTool> _tools;
  final String? _instructions;

  /// The maximum number of tool-calling iterations before the agent stops.
  ///
  /// This prevents infinite loops. Defaults to 10.
  final int maxIterations;

  /// Creates a new autonomous agent.
  ///
  /// - [client]: The AI client to use.
  /// - [tools]: The tools available to the agent.
  /// - [instructions]: Optional system instructions for the agent.
  /// - [model]: Optional model override.
  /// - [maxIterations]: Maximum tool loop iterations (default: 10).
  AiAgent({
    required AiClient client,
    required List<AiTool> tools,
    String? instructions,
    String? model,
    this.maxIterations = 10,
  })  : _client = client,
        _tools = tools,
        _instructions = instructions,
        _model = model,
        _executor = ToolExecutor(tools);

  /// Runs the agent autonomously until the model answers without calling a
  /// tool, or the maximum number of iterations is reached.
  ///
  /// The [prompt] is the user's request. The agent will iterate between
  /// calling the AI model and executing tools until a final response
  /// is produced.
  ///
  /// Tool failures are reported back to the model as error results rather
  /// than thrown. Errors from the client (network, authentication, ...)
  /// propagate unchanged.
  ///
  /// Throws [AiToolException] if the agent fails to complete within
  /// [maxIterations] iterations.
  Future<String> run(String prompt) async {
    final messages = <AiMessage>[];

    // Add system instructions if provided
    final instructions = _instructions;
    if (instructions != null) {
      messages.add(AiMessage.system(instructions));
    }

    messages.add(AiMessage.user(prompt));

    int iteration = 0;

    while (iteration < maxIterations) {
      // 1. Ask the model
      final response = await _client.chat(
        // A snapshot, so middleware holding on to the request does not see
        // later turns appended to it.
        messages: List.unmodifiable(messages),
        model: _model,
        tools: _tools,
      );

      final message = response.message;
      messages.add(message);

      // 2. Check if the model called any tools
      final toolCalls = message.content.whereType<AiToolCallContent>().toList();

      // The presence of tool calls is the signal to continue. The finish
      // reason is not reliable here: Gemini reports `STOP` for tool turns.
      if (toolCalls.isEmpty) return message.text;

      // 3. Execute the tools concurrently
      final results = await _executor.executeAll(toolCalls);

      // 4. Feed the results back into the conversation
      messages.add(AiMessage(
        role: AiMessageRole.tool,
        content: List<AiContent>.of(results),
      ));

      iteration++;
    }

    throw AiToolException(
      'Agent failed to complete task within $maxIterations iterations.',
      provider: _client.provider.runtimeType.toString(),
    );
  }
}
