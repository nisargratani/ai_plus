import '../models/ai_message.dart';

/// Interface for persisting conversation state.
///
/// Implement this interface to store conversations in any backend
/// (Hive, SQLite, SharedPreferences, Firebase, etc.).
///
/// An in-memory implementation is provided via [InMemoryConversationStorage].
///
/// ```dart
/// class HiveConversationStorage implements AiConversationStorage {
///   @override
///   Future<void> save(String id, List<AiMessage> messages) async {
///     // Save to Hive box
///   }
///   // ...
/// }
/// ```
abstract interface class AiConversationStorage {
  /// Saves the conversation messages for the given [id].
  Future<void> save(String id, List<AiMessage> messages);

  /// Loads the conversation messages for the given [id].
  ///
  /// Returns `null` if no conversation exists with the given ID.
  Future<List<AiMessage>?> load(String id);

  /// Deletes the conversation with the given [id].
  Future<void> delete(String id);

  /// Lists all stored conversation IDs.
  Future<List<String>> listIds();
}

/// An in-memory implementation of [AiConversationStorage].
///
/// Useful for testing and simple applications. Data is lost when
/// the application exits.
class InMemoryConversationStorage implements AiConversationStorage {
  /// Creates an empty in-memory storage.
  InMemoryConversationStorage();

  final Map<String, List<AiMessage>> _store = {};

  @override
  Future<void> save(String id, List<AiMessage> messages) async {
    _store[id] = List.unmodifiable(messages);
  }

  @override
  Future<List<AiMessage>?> load(String id) async {
    return _store[id];
  }

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<List<String>> listIds() async {
    return _store.keys.toList();
  }
}
