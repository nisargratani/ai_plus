import 'package:test/test.dart';
import 'package:ai_plus/ai_plus.dart';

void main() {
  group('AiJsonSchema', () {
    test('string schema', () {
      final schema = AiJsonSchema.string(description: 'A name');
      final json = schema.toJson();
      expect(json['type'], 'string');
      expect(json['description'], 'A name');
    });

    test('integer schema', () {
      final schema = AiJsonSchema.integer(description: 'An age');
      final json = schema.toJson();
      expect(json['type'], 'integer');
      expect(json['description'], 'An age');
    });

    test('number schema', () {
      final schema = AiJsonSchema.number();
      expect(schema.toJson()['type'], 'number');
    });

    test('boolean schema', () {
      final schema = AiJsonSchema.boolean();
      expect(schema.toJson()['type'], 'boolean');
    });

    test('string schema with enum', () {
      final schema = AiJsonSchema.string(enumValues: ['red', 'green', 'blue']);
      final json = schema.toJson();
      expect(json['type'], 'string');
      expect(json['enum'], ['red', 'green', 'blue']);
    });

    test('object schema', () {
      final schema = AiJsonSchema.object(
        properties: {
          'name': AiJsonSchema.string(),
          'age': AiJsonSchema.integer(),
        },
        required: ['name'],
        description: 'A person',
      );

      final json = schema.toJson();
      expect(json['type'], 'object');
      expect(json['description'], 'A person');
      expect(json['properties']['name']['type'], 'string');
      expect(json['properties']['age']['type'], 'integer');
      expect(json['required'], ['name']);
    });

    test('array schema', () {
      final schema = AiJsonSchema.array(
        items: AiJsonSchema.string(),
        description: 'A list of names',
      );

      final json = schema.toJson();
      expect(json['type'], 'array');
      expect(json['description'], 'A list of names');
      expect(json['items']['type'], 'string');
    });

    test('nested object schema', () {
      final schema = AiJsonSchema.object(
        properties: {
          'user': AiJsonSchema.object(
            properties: {
              'name': AiJsonSchema.string(),
              'addresses': AiJsonSchema.array(
                items: AiJsonSchema.object(
                  properties: {
                    'street': AiJsonSchema.string(),
                    'zip': AiJsonSchema.string(),
                  },
                ),
              ),
            },
          ),
        },
      );

      final json = schema.toJson();
      final userProps = json['properties']['user']['properties'];
      expect(userProps['name']['type'], 'string');
      expect(userProps['addresses']['type'], 'array');
      expect(userProps['addresses']['items']['type'], 'object');
      expect(
        userProps['addresses']['items']['properties']['street']['type'],
        'string',
      );
    });

    test('toJson omits null fields', () {
      final schema = AiJsonSchema.string();
      final json = schema.toJson();
      expect(json.containsKey('description'), isFalse);
      expect(json.containsKey('properties'), isFalse);
      expect(json.containsKey('required'), isFalse);
      expect(json.containsKey('items'), isFalse);
      expect(json.containsKey('enum'), isFalse);
    });
  });
}
