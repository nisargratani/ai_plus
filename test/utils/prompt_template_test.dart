import 'package:ai_plus/ai_plus.dart';
import 'package:test/test.dart';

void main() {
  group('AiPromptTemplate', () {
    test('renders simple template', () {
      const template = AiPromptTemplate('Hello, {{name}}!');
      expect(template.render({'name': 'World'}), 'Hello, World!');
    });

    test('renders template with multiple variables', () {
      const template =
          AiPromptTemplate('{{greeting}}, {{name}}! Welcome to {{place}}.');
      final result = template.render({
        'greeting': 'Hello',
        'name': 'Alice',
        'place': 'Wonderland',
      });
      expect(result, 'Hello, Alice! Welcome to Wonderland.');
    });

    test('throws on missing variables', () {
      const template = AiPromptTemplate('Hello, {{name}}!');
      expect(
        () => template.render({}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws with helpful message for missing variables', () {
      const template = AiPromptTemplate('{{a}} and {{b}}');
      try {
        template.render({'a': 'X'});
        fail('Should have thrown');
      } catch (e) {
        expect(e.toString(), contains('b'));
      }
    });

    test('variables getter returns all variable names', () {
      const template = AiPromptTemplate('{{x}} {{y}} {{z}}');
      expect(template.variables, {'x', 'y', 'z'});
    });

    test('handles template with no variables', () {
      const template = AiPromptTemplate('No variables here');
      expect(template.variables, isEmpty);
      expect(template.render({}), 'No variables here');
    });

    test('handles duplicate variable references', () {
      const template = AiPromptTemplate('{{name}} is {{name}}');
      expect(template.render({'name': 'Bob'}), 'Bob is Bob');
    });

    test('preserves whitespace and newlines', () {
      const template = AiPromptTemplate('Line 1: {{a}}\nLine 2: {{b}}');
      expect(template.render({'a': 'X', 'b': 'Y'}), 'Line 1: X\nLine 2: Y');
    });

    test('toString shows variables', () {
      const template = AiPromptTemplate('{{x}} {{y}}');
      expect(template.toString(), contains('x'));
      expect(template.toString(), contains('y'));
    });
  });
}
