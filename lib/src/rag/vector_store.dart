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

/// A simple, in-memory vector store for testing and small RAG applications.
///
/// Uses cosine similarity. Search is a linear scan, O(n·d) for n documents
/// of dimension d, which is fast for a few thousand documents; use a
/// dedicated vector database for larger corpora.
///
/// Documents are keyed by [AiDocument.id]: adding a document with an
/// existing id replaces it.
///
/// ```dart
/// final store = MemoryVectorStore();
/// await store.add(AiDocument(id: '1', content: '...', embedding: embedding));
/// final results = await store.search(queryEmbedding, k: 3);
/// ```
class MemoryVectorStore implements AiVectorStore {
  /// Creates an empty store.
  MemoryVectorStore();

  final Map<String, _StoredDocument> _documents = {};

  /// The number of documents in the store.
  int get length => _documents.length;

  @override
  Future<void> add(AiDocument document) async {
    _documents[document.id] = _StoredDocument(document);
  }

  @override
  Future<void> addAll(List<AiDocument> documents) async {
    for (final document in documents) {
      _documents[document.id] = _StoredDocument(document);
    }
  }

  @override
  Future<List<AiSearchResult>> search(AiEmbedding query, {int k = 4}) async {
    return similaritySearch(query, k: k);
  }

  @override
  Future<void> delete(String id) async {
    _documents.remove(id);
  }

  @override
  Future<void> clear() async {
    _documents.clear();
  }

  /// Performs synchronous similarity search (convenience for in-memory use).
  ///
  /// Returns up to [k] results sorted by descending cosine similarity.
  /// Throws [ArgumentError] if a stored vector's dimension differs from
  /// [query]'s.
  List<AiSearchResult> similaritySearch(AiEmbedding query, {int k = 4}) {
    if (_documents.isEmpty || k <= 0) return [];

    final queryNorm = _norm(query.vector);
    final results = [
      for (final stored in _documents.values)
        AiSearchResult(
          document: stored.document,
          score: _cosineSimilarity(
            query.vector,
            queryNorm,
            stored.document.embedding.vector,
            stored.norm,
          ),
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));

    return results.length > k ? results.sublist(0, k) : results;
  }

  static double _norm(List<double> v) {
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    return math.sqrt(sum);
  }

  static double _cosineSimilarity(
    List<double> a,
    double normA,
    List<double> b,
    double normB,
  ) {
    if (a.length != b.length) {
      throw ArgumentError(
        'Vectors must have the same length (${a.length} != ${b.length}).',
      );
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;

    var dotProduct = 0.0;
    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
    }
    return dotProduct / (normA * normB);
  }
}

/// A document together with its precomputed vector norm.
class _StoredDocument {
  _StoredDocument(this.document)
      : norm = MemoryVectorStore._norm(document.embedding.vector);

  final AiDocument document;
  final double norm;
}
