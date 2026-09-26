import '../core/ai_client.dart';
import '../core/ai_response.dart';
import '../embeddings/embedding_service.dart';
import '../errors/ai_exception.dart';
import '../models/ai_message.dart';
import 'vector_store.dart';

/// A high-level helper for Retrieval-Augmented Generation (RAG).
///
/// Combines embeddings, vector search, and AI chat to answer questions
/// based on ingested documents.
///
/// ```dart
/// final kb = AiKnowledgeBase(client: ai);
///
/// await kb.ingest(id: 'doc1', content: 'Flutter is a UI toolkit by Google.');
/// final answer = await kb.ask('What is Flutter?');
/// print(answer.text);
/// ```
class AiKnowledgeBase {
  final AiClient _client;
  final AiEmbeddingService _embeddingService;
  final AiVectorStore _store;
  final String? _embeddingModel;

  static int _idCounter = 0;

  /// Creates a knowledge base.
  ///
  /// - [client]: The AI client used for answering questions.
  /// - [embeddingService]: The service for generating embeddings. Defaults to
  ///   [AiClient.embeddings] of [client].
  /// - [store]: Any [AiVectorStore] (defaults to a new [MemoryVectorStore]).
  /// - [embeddingModel]: An optional model override for embeddings.
  AiKnowledgeBase({
    required AiClient client,
    AiEmbeddingService? embeddingService,
    AiVectorStore? store,
    String? embeddingModel,
  })  : _client = client,
        _embeddingService = embeddingService ?? client.embeddings,
        _store = store ?? MemoryVectorStore(),
        _embeddingModel = embeddingModel;

  /// The vector store holding the ingested documents.
  AiVectorStore get store => _store;

  /// Ingests a text document into the knowledge base.
  ///
  /// The document is embedded and stored in the vector store for later
  /// retrieval during [ask] or [search] calls. Re-ingesting an existing [id]
  /// replaces the document in stores with upsert semantics, such as
  /// [MemoryVectorStore].
  Future<void> ingest({
    required String id,
    required String content,
    Map<String, dynamic> metadata = const {},
  }) async {
    final result =
        await _embeddingService.create(input: content, model: _embeddingModel);

    await _store.add(AiDocument(
      id: id,
      content: content,
      embedding: result.embeddings.first,
      metadata: metadata,
    ));
  }

  /// Ingests multiple text documents with a single embeddings request.
  ///
  /// When given, [ids] and [metadataList] must have the same length as
  /// [contents]; otherwise an [ArgumentError] is thrown before any request
  /// is made. Documents without an explicit id get a generated unique one.
  Future<void> ingestBatch({
    required List<String> contents,
    List<String>? ids,
    List<Map<String, dynamic>>? metadataList,
  }) async {
    if (ids != null && ids.length != contents.length) {
      throw ArgumentError.value(
          ids, 'ids', 'must have the same length as contents');
    }
    if (metadataList != null && metadataList.length != contents.length) {
      throw ArgumentError.value(metadataList, 'metadataList',
          'must have the same length as contents');
    }
    if (contents.isEmpty) return;

    final result = await _embeddingService.createBatch(
        inputs: contents, model: _embeddingModel);
    if (result.embeddings.length != contents.length) {
      throw AiParsingException(
        'Expected ${contents.length} embeddings, '
        'got ${result.embeddings.length}',
      );
    }

    final prefix = DateTime.now().microsecondsSinceEpoch;
    await _store.addAll([
      for (var i = 0; i < contents.length; i++)
        AiDocument(
          id: ids?[i] ?? '${prefix}_${_idCounter++}',
          content: contents[i],
          embedding: result.embeddings[i],
          metadata: metadataList?[i] ?? const {},
        ),
    ]);
  }

  /// Searches the knowledge base for relevant documents.
  ///
  /// Returns up to [k] documents sorted by relevance.
  Future<List<AiSearchResult>> search(String query, {int k = 4}) async {
    final result =
        await _embeddingService.create(input: query, model: _embeddingModel);
    return _store.search(result.embeddings.first, k: k);
  }

  /// Asks a question using the knowledge base for context.
  ///
  /// This performs a RAG flow:
  /// 1. Embeds the [question]
  /// 2. Searches the vector store for the [k] most relevant documents
  /// 3. Constructs a context-enriched system prompt
  /// 4. Sends it to the AI model
  ///
  /// A custom [systemPrompt] replaces the default instructions; the
  /// retrieved context is always appended to it.
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

    final instructions = systemPrompt ??
        'Answer the question based on the following context. '
            'If the context does not contain enough information, say so.';

    return _client.chat(
      messages: [
        AiMessage.system('$instructions\n\nContext:\n$context'),
        AiMessage.user(question),
      ],
      model: model,
    );
  }

  /// Adds a pre-embedded document directly to the store.
  Future<void> addDocument(AiDocument document) => _store.add(document);
}
