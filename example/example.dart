// A tour of the main `ai_plus` features.
//
// Run with:
//   OPENAI_API_KEY=sk-... dart run example/example.dart
//
// Swap the provider (see step 1) to run the same code against Gemini,
// Claude or a local Ollama server.
import 'dart:io';
import 'package:ai_plus/ai_plus.dart';

Future<void> main() async {
  // ──────────────────────────────────────────────────────────────────────
  // 1. INITIALIZATION — Provider-Agnostic Setup
  // ──────────────────────────────────────────────────────────────────────

  final apiKey = Platform.environment['OPENAI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print('Please set OPENAI_API_KEY environment variable.');
    return;
  }

  // Initialize with middleware (retries, caching, logging, metrics)
  final metrics = MetricsMiddleware();
  final costTracker = AiCostTracker(
    pricing: const AiPricing(
      inputCostPerToken: 0.00000015, // gpt-4o-mini pricing
      outputCostPerToken: 0.0000006,
    ),
  );

  final ai = AiClient(
    provider: AiProvider.openAI(apiKey: apiKey),
    defaultModel: 'gpt-4o-mini',
    timeout: const Duration(seconds: 60),
    retryPolicy: const AiRetryPolicy(maxAttempts: 3, backoffFactor: 2.0),
    cache: MemoryAiCache(ttl: const Duration(minutes: 30), maxEntries: 100),
    logger: const ConsoleAiLogger(enableDebug: false),
    middlewares: [metrics],
  );

  // You can switch providers without changing any code below:
  // provider: AiProvider.gemini(apiKey: geminiKey),
  // provider: AiProvider.anthropic(apiKey: claudeKey),
  // provider: AiProvider.custom(baseUrl: 'http://localhost:11434/v1', apiKey: ''),

  try {
    await _tour(ai, metrics, costTracker);
  } finally {
    // Releases the provider's HTTP connections.
    ai.close();
  }
}

Future<void> _tour(
  AiClient ai,
  MetricsMiddleware metrics,
  AiCostTracker costTracker,
) async {
  // ──────────────────────────────────────────────────────────────────────
  // 2. SIMPLE CHAT
  // ──────────────────────────────────────────────────────────────────────

  print('\n═══ Simple Chat ═══');
  final response = await ai.chat(
    messages: [
      AiMessage.system('You are a helpful assistant. Be concise.'),
      AiMessage.user('What is the capital of France?'),
    ],
  );
  print('Response: ${response.text}');
  print('Tokens: ${response.usage.totalTokens}');
  costTracker.addUsage(response.usage);

  // ──────────────────────────────────────────────────────────────────────
  // 3. STREAMING
  // ──────────────────────────────────────────────────────────────────────

  print('\n═══ Streaming ═══');
  await for (final text
      in ai.streamText(messages: [AiMessage.user('Count from 1 to 5.')])) {
    stdout.write(text);
  }
  print('');

  // ──────────────────────────────────────────────────────────────────────
  // 4. CONVERSATIONS (Multi-Turn)
  // ──────────────────────────────────────────────────────────────────────

  print('\n═══ Conversation ═══');
  final conversation = ai.conversation(id: 'demo-session');
  final r1 = await conversation.send('My favorite color is blue.');
  print('AI: ${r1.text}');
  final r2 = await conversation.send('What is my favorite color?');
  print('AI: ${r2.text}');
  print('Message count: ${conversation.messages.length}');

  // ──────────────────────────────────────────────────────────────────────
  // 5. CONVERSATION STORAGE
  // ──────────────────────────────────────────────────────────────────────

  print('\n═══ Conversation Storage ═══');
  final storage = InMemoryConversationStorage();
  await storage.save(conversation.id, conversation.messages);
  final ids = await storage.listIds();
  print('Stored conversations: $ids');

  // ──────────────────────────────────────────────────────────────────────
  // 6. STRUCTURED OUTPUT
  // ──────────────────────────────────────────────────────────────────────

  print('\n═══ Structured Output ═══');
  final profile = await ai.generate<Map<String, dynamic>>(
    prompt: 'Create a fictional user profile with name, age, and city.',
    schema: AiJsonSchema.object(
      properties: {
        'name': AiJsonSchema.string(description: 'Full name'),
        'age': AiJsonSchema.integer(description: 'Age in years'),
        'city': AiJsonSchema.string(description: 'City of residence'),
      },
      required: ['name', 'age', 'city'],
    ),
    decoder: (json) => json,
  );
  print('Profile: $profile');

  // ──────────────────────────────────────────────────────────────────────
  // 7. TOOL CALLING
  // ──────────────────────────────────────────────────────────────────────

  print('\n═══ Tool Calling ═══');
  final weatherTool = AiTool(
    name: 'get_weather',
    description: 'Gets the current weather for a given city.',
    parameters: AiJsonSchema.object(
      properties: {
        'city': AiJsonSchema.string(description: 'The city name'),
      },
      required: ['city'],
    ),
    execute: (args) async => {'temp': '22°C', 'condition': 'sunny'},
  );

  final toolResponse = await ai.chat(
    messages: [AiMessage.user('What is the weather in London?')],
    tools: [weatherTool],
  );

  final toolCalls =
      toolResponse.message.content.whereType<AiToolCallContent>().toList();
  if (toolCalls.isNotEmpty) {
    print('Model wants to call: ${toolCalls.first.name}');
    print('With args: ${toolCalls.first.arguments}');

    // Execute the requested tools (AiAgent below automates this loop).
    final results = await ToolExecutor([weatherTool]).executeAll(toolCalls);
    print('Tool result: ${results.first.result}');
  } else {
    print('AI: ${toolResponse.text}');
  }

  // ──────────────────────────────────────────────────────────────────────
  // 8. AUTONOMOUS AGENT
  // ──────────────────────────────────────────────────────────────────────

  print('\n═══ Autonomous Agent ═══');
  final agent = AiAgent(
    client: ai,
    instructions:
        'You are a weather assistant. Always use the get_weather tool.',
    tools: [weatherTool],
    maxIterations: 3,
  );

  try {
    final agentResult =
        await agent.run('Should I bring an umbrella in London today?');
    print('Agent: $agentResult');
  } catch (e) {
    print('Agent error: $e');
  }

  // ──────────────────────────────────────────────────────────────────────
  // 9. EMBEDDINGS & RAG
  // ──────────────────────────────────────────────────────────────────────

  print('\n═══ Knowledge Base (RAG) ═══');
  final kb = AiKnowledgeBase(client: ai);
  await kb.ingestBatch(
    ids: ['dart', 'flutter'],
    contents: [
      'Dart is a client-optimized language created by Google in 2011.',
      'Flutter is a UI toolkit that uses Dart to build cross-platform apps.',
    ],
  );
  final answer = await kb.ask('Which language does Flutter use?', k: 1);
  print('Answer: ${answer.text}');

  // ──────────────────────────────────────────────────────────────────────
  // 10. PROMPT TEMPLATES
  // ──────────────────────────────────────────────────────────────────────

  print('\n═══ Prompt Templates ═══');
  const template = AiPromptTemplate(
    'Translate the following {{language}} text to English:\n\n{{text}}',
  );
  print('Variables: ${template.variables}');
  final prompt = template.render({
    'language': 'French',
    'text': 'Bonjour le monde',
  });
  print('Rendered: $prompt');

  // ──────────────────────────────────────────────────────────────────────
  // 11. ERROR HANDLING
  // ──────────────────────────────────────────────────────────────────────

  print('\n═══ Error Handling ═══');
  final badClient = AiClient(
    provider: AiProvider.openAI(apiKey: 'invalid-key'),
    retryPolicy: AiRetryPolicy.none,
  );
  try {
    await badClient.chat(messages: [AiMessage.user('Hello')]);
  } on AiAuthenticationException catch (e) {
    print('Auth error (expected): ${e.message}');
  } on AiException catch (e) {
    print('AI error: $e');
  } finally {
    badClient.close();
  }

  // ──────────────────────────────────────────────────────────────────────
  // 12. COST TRACKING & METRICS
  // ──────────────────────────────────────────────────────────────────────

  print('\n═══ Cost Tracking & Metrics ═══');
  print('Requests: ${metrics.requestCount}');
  print('Errors: ${metrics.errorCount}');
  print('Avg latency: ${metrics.averageLatency.inMilliseconds}ms');
  print(costTracker);
}
