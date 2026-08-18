// ignore_for_file: prefer_initializing_formals

import '../core/ai_client.dart';
import '../models/ai_message.dart';
import '../core/ai_response.dart';
import '../embeddings/embedding_service.dart';
import 'vector_store.dart';

/// A high-level helper for Retrieval-Augmented Generation (RAG).
///
/// Combines embeddings, vector search, and AI chat to answer questions
/// based on ingested documents.
///
/// ```dart
/// final kb = AiKnowledgeBase(
///   client: ai,
///   embeddingService: ai.embeddings,
/// );
///
/// await kb.ingest(id: 'doc1', content: 'Flutter is a UI toolkit by Google.');
/// final answer = await kb.ask('What is Flutter?');
/// print(answer.text);
/// ```
class AiKnowledgeBase {
  final AiClient _client;
  final AiEmbeddingService _embeddingService;
  final MemoryVectorStore _store;
  final String? _embeddingModel;

  /// Creates a knowledge base.
  ///
  /// - [client]: The AI client used for answering questions.
  /// - [embeddingService]: The service for generating embeddings.
  /// - [store]: An optional vector store (defaults to [MemoryVectorStore]).
  /// - [embeddingModel]: An optional model override for embeddings.
  AiKnowledgeBase({
    required AiClient client,
    required AiEmbeddingService embeddingService,
    MemoryVectorStore? store,
    String? embeddingModel,
  })  : _client = client,
        _embeddingService = embeddingService,
        _store = store ?? MemoryVectorStore(),
        _embeddingModel = embeddingModel;

  /// Ingests a text document into the knowledge base.
  ///
  /// The document is embedded and stored in the vector store for
  /// later retrieval during [ask] or [search] calls.
  Future<void> ingest({
    required String id,
    required String content,
    Map<String, dynamic> metadata = const {},
  }) async {
    final result =
        await _embeddingService.create(input: content, model: _embeddingModel);

    final doc = AiDocument(
      id: id,
      content: content,
      embedding: result.embeddings.first,
      metadata: metadata,
    );

    await _store.add(doc);
  }

  /// Ingests multiple text documents into the knowledge base.
  Future<void> ingestBatch({
    required List<String> contents,
    List<String>? ids,
    List<Map<String, dynamic>>? metadataList,
  }) async {
    final result = await _embeddingService.createBatch(
        inputs: contents, model: _embeddingModel);

    final docs = <AiDocument>[];
    for (int i = 0; i < contents.length; i++) {
      docs.add(AiDocument(
        id: ids != null
            ? ids[i]
            : '${DateTime.now().millisecondsSinceEpoch}_$i',
        content: contents[i],
        embedding: result.embeddings[i],
        metadata: metadataList != null ? metadataList[i] : const {},
      ));
    }

    await _store.addAll(docs);
  }

  /// Searches the knowledge base for relevant documents.
  ///
  /// Returns up to [k] documents sorted by relevance.
  Future<List<AiSearchResult>> search(String query, {int k = 4}) async {
    final result =
        await _embeddingService.create(input: query, model: _embeddingModel);
    return _store.similaritySearch(result.embeddings.first, k: k);
  }

  /// Asks a question using the knowledge base for context.
  ///
  /// This performs a RAG flow:
  /// 1. Embeds the [question]
  /// 2. Searches the vector store for relevant documents
  /// 3. Constructs a context-enriched prompt
  /// 4. Sends to the AI model
  ///
  /// Returns the AI response.
  ///
  /// ```dart
  /// final answer = await kb.ask('What is Flutter?');
  /// print(answer.text);
  /// ```
  Future<AiResponse> ask(
    String question, {
    int k = 4,
    String? model,
    String? systemPrompt,
  }) async {
    final results = await search(question, k: k);

    final context = results.map((r) => r.document.content).join('\n\n---\n\n');

    final system = systemPrompt ??
        'Answer the question based on the following context. '
            'If the context does not contain enough information, say so.\n\n'
            'Context:\n$context';

    return _client.chat(
      messages: [
        AiMessage.system(system),
        AiMessage.user(question),
      ],
      model: model,
    );
  }

  /// Adds a pre-embedded document directly to the store.
  void addDocument(AiDocument document) {
    _store.add(document);
  }
}
