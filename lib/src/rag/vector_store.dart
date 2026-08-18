import 'dart:math' as math;
import '../embeddings/embedding.dart';

/// A simple document representation with an embedding.
class AiDocument {
  /// The unique identifier for this document.
  final String id;

  /// The text content of this document.
  final String content;

  /// The vector embedding of this document.
  final AiEmbedding embedding;

  /// Optional metadata associated with the document.
  final Map<String, dynamic> metadata;

  /// Alias for [embedding].
  AiEmbedding get vector => embedding;

  /// Creates a document with its embedding.
  const AiDocument({
    required this.id,
    required this.content,
    required this.embedding,
    this.metadata = const {},
  });
}

/// A result from a similarity search.
class AiSearchResult {
  /// The matching document.
  final AiDocument document;

  /// The similarity score (higher is more similar).
  final double score;

  /// Creates a search result.
  const AiSearchResult({
    required this.document,
    required this.score,
  });
}

/// Abstract interface for vector stores.
///
/// Implement this interface to create custom vector store backends
/// (e.g. Pinecone, Weaviate, pgvector, etc.).
///
/// An in-memory implementation is provided via [MemoryVectorStore].
abstract interface class AiVectorStore {
  /// Adds a document to the store.
  Future<void> add(AiDocument document);

  /// Adds multiple documents to the store.
  Future<void> addAll(List<AiDocument> documents);

  /// Searches for the most similar documents to the given [query] embedding.
  ///
  /// Returns up to [k] results, sorted by descending similarity score.
  Future<List<AiSearchResult>> search(AiEmbedding query, {int k = 4});

  /// Deletes a document by its [id].
  Future<void> delete(String id);

  /// Clears all documents from the store.
  Future<void> clear();
}

/// A simple, in-memory vector store for testing and simple RAG applications.
///
/// Uses cosine similarity for similarity search.
///
/// ```dart
/// final store = MemoryVectorStore();
/// store.add(AiDocument(id: '1', content: '...', embedding: embedding));
/// final results = await store.search(queryEmbedding, k: 3);
/// ```
class MemoryVectorStore implements AiVectorStore {
  final List<AiDocument> _documents = [];

  @override
  Future<void> add(AiDocument document) async {
    _documents.add(document);
  }

  @override
  Future<void> addAll(List<AiDocument> documents) async {
    _documents.addAll(documents);
  }

  @override
  Future<List<AiSearchResult>> search(AiEmbedding query, {int k = 4}) async {
    if (_documents.isEmpty) return [];

    final results = _documents.map((doc) {
      final score = _cosineSimilarity(query.vector, doc.embedding.vector);
      return AiSearchResult(document: doc, score: score);
    }).toList();

    results.sort((a, b) => b.score.compareTo(a.score));

    return results.take(k).toList();
  }

  @override
  Future<void> delete(String id) async {
    _documents.removeWhere((doc) => doc.id == id);
  }

  @override
  Future<void> clear() async {
    _documents.clear();
  }

  /// Performs synchronous similarity search (convenience for in-memory use).
  List<AiSearchResult> similaritySearch(AiEmbedding query, {int k = 4}) {
    if (_documents.isEmpty) return [];

    final results = _documents.map((doc) {
      final score = _cosineSimilarity(query.vector, doc.embedding.vector);
      return AiSearchResult(document: doc, score: score);
    }).toList();

    results.sort((a, b) => b.score.compareTo(a.score));

    return results.take(k).toList();
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) {
      throw ArgumentError('Vectors must have the same length.');
    }

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA == 0.0 || normB == 0.0) return 0.0;

    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }
}
