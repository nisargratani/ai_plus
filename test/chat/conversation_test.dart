import 'package:test/test.dart';
import 'package:ai_plus/ai_plus.dart';

void main() {
  group('AiConversation', () {
    late AiClient client;

    setUp(() {
      client = AiClient(
        provider: AiProvider.openAI(apiKey: 'test-key'),
      );
    });

    test('starts with empty messages', () {
      final conversation = client.conversation();
      expect(conversation.messages, isEmpty);
    });

    test('starts with initial messages', () {
      final conversation = client.conversation(
        initialMessages: [
          AiMessage.system('Be helpful'),
          AiMessage.user('Hello'),
        ],
      );
      expect(conversation.messages.length, 2);
    });

    test('addMessage adds to history', () {
      final conversation = client.conversation();
      conversation.addMessage(AiMessage.user('Test'));
      expect(conversation.messages.length, 1);
      expect(conversation.messages.first.text, 'Test');
    });

    test('removeLast removes last message', () {
      final conversation = client.conversation(
        initialMessages: [
          AiMessage.user('First'),
          AiMessage.user('Second'),
        ],
      );
      conversation.removeLast();
      expect(conversation.messages.length, 1);
      expect(conversation.messages.first.text, 'First');
    });

    test('removeLast on empty does nothing', () {
      final conversation = client.conversation();
      conversation.removeLast(); // Should not throw
      expect(conversation.messages, isEmpty);
    });

    test('clear removes all messages', () {
      final conversation = client.conversation(
        initialMessages: [AiMessage.user('A'), AiMessage.user('B')],
      );
      conversation.clear();
      expect(conversation.messages, isEmpty);
    });

    test('messages returns unmodifiable list', () {
      final conversation = client.conversation(
        initialMessages: [AiMessage.user('Test')],
      );
      expect(
        () => conversation.messages.add(AiMessage.user('Hack')),
        throwsUnsupportedError,
      );
    });

    test('has an id', () {
      final conversation = client.conversation();
      expect(conversation.id, isNotEmpty);
    });

    test('accepts custom id', () {
      final conversation = client.conversation(id: 'custom-id');
      expect(conversation.id, 'custom-id');
    });
  });

  group('AiConversationStorage', () {
    late InMemoryConversationStorage storage;

    setUp(() {
      storage = InMemoryConversationStorage();
    });

    test('returns null for non-existent conversation', () async {
      expect(await storage.load('nonexistent'), isNull);
    });

    test('saves and loads conversation', () async {
      final messages = [
        AiMessage.user('Hello'),
        AiMessage.assistant('Hi'),
      ];

      await storage.save('conv1', messages);
      final loaded = await storage.load('conv1');

      expect(loaded, isNotNull);
      expect(loaded!.length, 2);
      expect(loaded[0].text, 'Hello');
      expect(loaded[1].text, 'Hi');
    });

    test('deletes conversation', () async {
      await storage.save('conv1', [AiMessage.user('Hello')]);
      await storage.delete('conv1');
      expect(await storage.load('conv1'), isNull);
    });

    test('lists all conversation ids', () async {
      await storage.save('a', [AiMessage.user('A')]);
      await storage.save('b', [AiMessage.user('B')]);

      final ids = await storage.listIds();
      expect(ids, containsAll(['a', 'b']));
    });

    test('overwrite existing conversation', () async {
      await storage.save('conv1', [AiMessage.user('Old')]);
      await storage.save('conv1', [AiMessage.user('New')]);

      final loaded = await storage.load('conv1');
      expect(loaded!.length, 1);
      expect(loaded[0].text, 'New');
    });
  });
}
