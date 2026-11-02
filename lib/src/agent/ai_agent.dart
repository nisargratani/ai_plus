// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import '../core/ai_client.dart';
import '../errors/ai_exception.dart';
import '../models/ai_content.dart';
import '../models/ai_message.dart';
import '../providers/provider_name.dart';
import '../tools/ai_tool.dart';
import '../tools/tool_executor.dart';

/// A high-level autonomous agent capable of using tools to achieve a goal.
///
/// The agent iterates between the AI model and tool execution until the
/// model produces a final text response. It runs at most [maxIterations]
/// rounds of tools, then gives the model one last call to answer; it never
/// runs tools whose results it would not send back.
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

  /// The maximum number of tool-execution rounds. Defaults to 10.
  ///
  /// After the last round the results are sent to the model once more so it
  /// can answer, so a run makes at most `maxIterations + 1` model calls. If
  /// the model still asks for tools then, the agent throws
  /// [AiToolException] without running them. This prevents infinite loops.
  final int maxIterations;

  /// Creates a new autonomous agent.
  ///
  /// - [client]: The AI client to use.
  /// - [tools]: The tools available to the agent.
  /// - [instructions]: Optional system instructions for the agent.
  /// - [model]: Optional model override.
  /// - [maxIterations]: Maximum tool-execution rounds (default: 10).
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
  /// Completing [abortTrigger] cancels the run: the model call in flight is
  /// aborted, no further tools are started, and the run fails with
  /// [AiTimeoutException]. Tools that are already running finish.
  ///
  /// Throws [AiToolException] if the model still requests tools after
  /// [maxIterations] tool rounds. Those last tool calls are not executed, so
  /// no tool side effect happens without its result reaching the model.
  Future<String> run(String prompt, {Future<void>? abortTrigger}) async {
    var aborted = false;
    if (abortTrigger != null) {
      unawaited(abortTrigger.then((_) => aborted = true,
          onError: (Object _) => aborted = true));
    }
    void checkAborted() {
      if (aborted) {
        throw AiTimeoutException('Agent run aborted',
            provider: providerName(_client.provider));
      }
    }

    final messages = <AiMessage>[];

    // Add system instructions if provided
    final instructions = _instructions;
    if (instructions != null) {
      messages.add(AiMessage.system(instructions));
    }

    messages.add(AiMessage.user(prompt));

    for (var round = 0;; round++) {
      // 1. Ask the model
      checkAborted();
      final response = await _client.chat(
        // A snapshot, so middleware holding on to the request does not see
        // later turns appended to it.
        messages: List.unmodifiable(messages),
        model: _model,
        tools: _tools,
        abortTrigger: abortTrigger,
      );

      final message = response.message;
      messages.add(message);

      // 2. Check if the model called any tools
      final toolCalls = message.content.whereType<AiToolCallContent>().toList();

      // The presence of tool calls is the signal to continue. The finish
      // reason is not reliable here: Gemini reports `STOP` for tool turns.
      if (toolCalls.isEmpty) return message.text;

      // 3. Stop before running tools whose results could not be sent back.
      if (round >= maxIterations) {
        final names = {for (final c in toolCalls) c.name}.join(', ');
        String plural(String word) => maxIterations == 1 ? word : '${word}s';
        throw AiToolException(
          'Agent failed to complete task within $maxIterations '
          '${plural('iteration')}: after $maxIterations tool '
          '${plural('round')} the model requested more tool calls ($names), '
          'which were not executed.',
          provider: providerName(_client.provider),
        );
      }

      // 4. Execute the tools concurrently (unless the run was cancelled)
      checkAborted();
      final results = await _executor.executeAll(toolCalls);

      // 5. Feed the results back into the conversation
      messages.add(AiMessage(
        role: AiMessageRole.tool,
        content: List<AiContent>.of(results),
      ));
    }
  }
}
